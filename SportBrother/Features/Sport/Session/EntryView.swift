import SwiftData
import SwiftUI

/// Saisie des séries d'un exo pour un profil, avec la dernière fois toujours sous les yeux.
struct EntryView: View {
    let entryID: UUID
    let sessionID: UUID
    @Environment(SportSync.self) private var sync
    @Environment(RestTimer.self) private var rest
    @Query private var sessions: [SportSession]
    @Query private var entries: [SportEntry]
    @Query private var sets: [SportSet]
    @Query private var profiles: [SportProfile]
    @Query private var overrides: [SportExercise]
    @Query private var feedback: [SportFeedback]
    @Query private var templateItems: [SportTemplateItem]
    @AppStorage(myProfileKey) private var myProfileID = ""
    @State private var profileID: UUID?
    @State private var recordTrigger = 0
    @State private var doneTrigger = 0
    @State private var editing: EditedValue?

    private var session: SportSession? { sessions.first { $0.id == sessionID } }
    private var entry: SportEntry? { entries.first { $0.id == entryID } }

    private var present: [SportProfile] {
        guard let session else { return [] }
        return profiles.live.filter { session.profileIDs.contains($0.id) }
    }

    private var selected: SportProfile? { present.first { $0.id == profileID } ?? present.first }

    private func mySets(_ profile: UUID) -> [SportSet] {
        sets.filter { $0.entryID == entryID && $0.profileID == profile && $0.deletedAt == nil }.sorted { $0.index < $1.index }
    }

    var body: some View {
        if let entry, let exercise = ExerciseCatalog.merged(overrides).byID[entry.exerciseRef], let profile = selected {
            let history = SportHistory(sessions: sessions, entries: entries, sets: sets)
            let last = history.last(profile: profile.id, exercise: exercise.id, excluding: sessionID)
            let previous = history.previous(profile: profile.id, exercise: exercise.id, excluding: sessionID)
            let current = mySets(profile.id)
            List {
                Section {
                    ExerciseHero(exercise: exercise, height: 140).listRowInsets(EdgeInsets())
                }

                if present.count > 1 {
                    Section {
                        Picker("Profil", selection: Binding(get: { profile.id }, set: { profileID = $0 })) {
                            ForEach(present) { Text($0.name).tag($0.id) }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }

                Section {
                    LastTimeView(last: last, suggestion: Progression.suggestion(
                        last: last, repRangeHigh: exercise.repRangeHigh, isBodyweight: exercise.isBodyweight
                    ))
                }

                Section {
                    ForEach(Array(current.enumerated()), id: \.element.id) { offset, set in
                        let earlier = current.prefix(offset).filter(\.isDone).map { SetValue(weight: $0.weightKg, reps: $0.reps) }
                        SetEditorRow(
                            number: offset + 1,
                            set: set,
                            isBodyweight: exercise.isBodyweight,
                            reference: last.map { $0.sets[min(offset, $0.sets.count - 1)] },
                            isRecord: set.isDone && StrengthStats.isRecord(
                                SetValue(weight: set.weightKg, reps: set.reps),
                                previous: previous + [Performance(sessionID: sessionID, day: .now, sets: earlier)]
                            ),
                            onEdit: { editing = $0 },
                            onChange: { sync.save(set) },
                            onToggle: { toggle(set, exercise: exercise, profile: profile, previous: previous, earlier: earlier, number: offset + 1, total: current.count) }
                        )
                        .swipeActions {
                            Button("Supprimer", systemImage: "trash", role: .destructive) { sync.delete(set) }
                        }
                    }
                    Button("Ajouter une série", systemImage: "plus") { addSet(profile: profile.id, last: last, current: current) }
                } header: {
                    Text(present.count > 1 ? "Séries de \(profile.name)" : "Séries")
                }

                FeedbackSection(entryID: entryID, profileID: profile.id, feedback: feedback)
            }
            .listSectionSpacing(.compact)
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Les stats s'empilent dans la séance : retour = saisie intacte, chrono et repos continuent.
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ExerciseProgressView(exerciseID: exercise.id, profileID: profile.id)
                    } label: {
                        Label("Stats de l'exo", systemImage: "chart.xyaxis.line")
                    }
                }
            }
            .sensoryFeedback(.success, trigger: recordTrigger)
            .sensoryFeedback(.impact(weight: .medium), trigger: doneTrigger)
            .task(id: profile.id) { prepare(profile: profile.id, exercise: exercise, last: last) }
            .onAppear {
                if profileID == nil, let me = UUID(uuidString: myProfileID), present.contains(where: { $0.id == me }) { profileID = me }
            }
            .alert(editing?.title ?? "", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                if let editing { ValueField(edited: editing) { apply(editing, value: $0) } }
                Button("Annuler", role: .cancel) {}
            }
        } else {
            ContentUnavailableView("Exo retiré de la séance", systemImage: "dumbbell")
        }
    }

    /// Première ouverture pour ce profil : les séries sont créées pré-remplies avec la dernière fois.
    private func prepare(profile: UUID, exercise: ExerciseInfo, last: Performance?) {
        guard mySets(profile).isEmpty else { return }
        let planned = session?.templateID.flatMap { templateID in
            templateItems.first { $0.templateID == templateID && $0.exerciseRef == exercise.id && $0.deletedAt == nil }?.setCount
        }
        let count = planned ?? last?.sets.count ?? 3
        for index in 0..<max(1, count) {
            let value = Progression.prefill(index: index, last: last, today: [])
            sync.save(SportSet(entryID: entryID, profileID: profile, index: index, weightKg: value.weight, reps: value.reps))
        }
    }

    private func addSet(profile: UUID, last: Performance?, current: [SportSet]) {
        let today = current.map { SetValue(weight: $0.weightKg, reps: $0.reps) }
        let value = current.last.map { SetValue(weight: $0.weightKg, reps: $0.reps) }
            ?? Progression.prefill(index: current.count, last: last, today: today)
        withAnimation(.snappy) {
            sync.save(SportSet(entryID: entryID, profileID: profile, index: (current.map(\.index).max() ?? -1) + 1, weightKg: value.weight, reps: value.reps))
        }
    }

    private func toggle(_ set: SportSet, exercise: ExerciseInfo, profile: SportProfile, previous: [Performance], earlier: [SetValue], number: Int, total: Int) {
        withAnimation(.snappy) { set.doneAt = set.isDone ? nil : .now }
        sync.save(set)
        guard set.isDone else { return }
        let value = SetValue(weight: set.weightKg, reps: set.reps)
        if StrengthStats.isRecord(value, previous: previous + [Performance(sessionID: sessionID, day: .now, sets: earlier)]) {
            recordTrigger += 1
        } else {
            doneTrigger += 1
        }
        let detail = number < total ? "Série \(number + 1)/\(total)" : "Dernière série faite"
        rest.start(seconds: exercise.restSeconds, exercise: exercise.name, detail: present.count > 1 ? "\(profile.name) · \(detail)" : detail)
    }

    private func apply(_ edited: EditedValue, value: Double) {
        guard let set = sets.first(where: { $0.id == edited.setID }) else { return }
        switch edited.field {
        case .weight: set.weightKg = max(0, value)
        case .reps: set.reps = max(0, Int(value.rounded()))
        }
        sync.save(set)
    }
}

struct EditedValue: Identifiable {
    enum Field { case weight, reps }
    let setID: UUID
    let field: Field
    let value: Double

    var id: String { "\(setID)-\(field)" }
    var title: String { field == .weight ? "Charge (kg)" : "Répétitions" }
}

/// Champ de saisie au clavier dans l'alerte (le texte de départ est déjà sélectionnable).
private struct ValueField: View {
    let edited: EditedValue
    let onCommit: (Double) -> Void
    @State private var text = ""

    var body: some View {
        TextField(edited.title, text: $text)
            .keyboardType(edited.field == .weight ? .decimalPad : .numberPad)
            .onAppear { text = edited.field == .weight ? Format.number(edited.value) : "\(Int(edited.value))" }
        Button("OK") {
            if let value = Double(text.replacingOccurrences(of: ",", with: ".")) { onCommit(value) }
        }
    }
}

struct LastTimeView: View {
    let last: Performance?
    let suggestion: Progression?

    var body: some View {
        if let last {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Dernière fois")
                        .font(.subheadline.weight(.semibold))
                    Text(last.day.formatted(.relative(presentation: .named)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let suggestion {
                        Label(suggestion.label, systemImage: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .foregroundStyle(.green)
                            .background(.green.opacity(0.14), in: .capsule)
                    }
                }
                FlowLayout(spacing: 6) {
                    ForEach(Array(last.sets.enumerated()), id: \.offset) { _, set in
                        Text(set.label)
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.quaternary, in: .rect(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        } else {
            Label("Première fois sur cet exo : trouve ta charge de travail.", systemImage: "sparkles")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

extension SetValue {
    /// « 60×10 », « 10 reps » au poids du corps.
    var label: String { weight > 0 ? "\(Format.number(weight))×\(reps)" : "\(reps) reps" }
}

/// Une série : charge, reps, validation. Les flèches indiquent l'écart avec la même série la fois précédente.
private struct SetEditorRow: View {
    let number: Int
    let set: SportSet
    let isBodyweight: Bool
    let reference: SetValue?
    let isRecord: Bool
    let onEdit: (EditedValue) -> Void
    let onChange: () -> Void
    let onToggle: () -> Void

    private var trend: Double? {
        guard let reference, set.reps > 0 else { return nil }
        let now = StrengthStats.oneRepMax(SetValue(weight: set.weightKg, reps: set.reps))
        let then = StrengthStats.oneRepMax(reference)
        if set.weightKg == 0 && reference.weight == 0 { return Double(set.reps - reference.reps) }
        return now - then
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            if !isBodyweight || set.weightKg > 0 {
                CompactStepper(
                    text: Format.number(set.weightKg), unit: "kg",
                    decrement: { set.weightKg = max(0, set.weightKg - Progression.step); onChange() },
                    increment: { set.weightKg += Progression.step; onChange() },
                    edit: { onEdit(EditedValue(setID: set.id, field: .weight, value: set.weightKg)) }
                )
            }
            CompactStepper(
                text: "\(set.reps)", unit: "reps",
                decrement: { set.reps = max(0, set.reps - 1); onChange() },
                increment: { set.reps += 1; onChange() },
                edit: { onEdit(EditedValue(setID: set.id, field: .reps, value: Double(set.reps))) }
            )
            Spacer(minLength: 0)
            ZStack {
                if isRecord {
                    Text("PR")
                        .font(.caption2.weight(.heavy).width(.expanded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.orange, in: .capsule)
                        .transition(.scale.combined(with: .opacity))
                } else if let trend, abs(trend) > 0.01 {
                    Image(systemName: trend > 0 ? "arrow.up" : "arrow.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(trend > 0 ? .green : .secondary)
                        .accessibilityLabel(trend > 0 ? "Mieux que la dernière fois" : "Moins que la dernière fois")
                }
            }
            .frame(width: 28)
            Button(action: onToggle) {
                Image(systemName: set.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 30))
                    .foregroundStyle(set.isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.isDone ? "Série \(number) validée" : "Valider la série \(number)")
        }
        .opacity(set.isDone ? 0.75 : 1)
        .animation(.snappy, value: isRecord)
    }
}

/// [−] 60 kg [+] ; toucher la valeur ouvre le clavier.
private struct CompactStepper: View {
    let text: String
    let unit: String
    let decrement: () -> Void
    let increment: () -> Void
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", label: "Moins", action: decrement)
            Button(action: edit) {
                VStack(spacing: -2) {
                    Text(text)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 46, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(text) \(unit)")
            .accessibilityHint("Touche pour saisir au clavier")
            stepButton("plus", label: "Plus", action: increment)
        }
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 12, style: .continuous))
        .animation(.snappy(duration: 0.2), value: text)
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .frame(width: 30, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .accessibilityLabel("\(label) \(unit)")
        .buttonRepeatBehavior(.enabled)
    }
}

/// Ressenti facultatif du profil sur l'exo.
private struct FeedbackSection: View {
    let entryID: UUID
    let profileID: UUID
    let feedback: [SportFeedback]
    @Environment(SportSync.self) private var sync
    @State private var note = ""

    private var current: SportFeedback? {
        feedback.first { $0.entryID == entryID && $0.profileID == profileID && $0.deletedAt == nil }
    }

    var body: some View {
        Section("Ressenti") {
            HStack(spacing: 8) {
                ForEach(Effort.allCases) { effort in
                    ChipToggle(title: effort.label, symbol: effort.symbol, isOn: current?.effort == effort) {
                        let target = current ?? SportFeedback(entryID: entryID, profileID: profileID)
                        target.effort = target.effort == effort ? nil : effort
                        sync.save(target)
                    }
                }
            }
            .padding(.vertical, 2)
            TextField("Une note pour la prochaine fois (réglage du siège…)", text: $note, axis: .vertical)
                .onSubmit(saveNote)
                .onChange(of: note) { saveNoteLater() }
        }
        .task(id: profileID) { note = current?.note ?? "" }
    }

    @State private var pending: Task<Void, Never>?

    private func saveNoteLater() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            saveNote()
        }
    }

    private func saveNote() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (current?.note ?? "") else { return }
        let target = current ?? SportFeedback(entryID: entryID, profileID: profileID)
        target.note = trimmed.isEmpty ? nil : trimmed
        sync.save(target)
    }
}
