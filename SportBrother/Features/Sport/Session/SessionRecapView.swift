import SwiftData
import SwiftUI

/// Bilan d'une séance : durée, volume, records battus, comparaison avec la fois précédente du même modèle.
/// En fin de séance, il sert aussi à la clore et à l'enregistrer comme modèle.
struct SessionRecapView: View {
    let sessionID: UUID
    let isFinishing: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(SportSync.self) private var sync
    @Environment(LiveSessionPresenter.self) private var presenter
    @Environment(RestTimer.self) private var rest
    @Query private var sessions: [SportSession]
    @Query private var entries: [SportEntry]
    @Query private var sets: [SportSet]
    @Query private var profiles: [SportProfile]
    @Query private var overrides: [SportExercise]
    @Query private var templates: [SportTemplate]
    @State private var confirmEmpty = false
    @State private var confirmDelete = false
    @State private var namingTemplate = false
    @State private var templateName = ""
    @State private var editingDuration = false
    /// Durée saisie à la main en fin de séance, appliquée au moment de terminer.
    @State private var customDuration: TimeInterval?

    private var session: SportSession? { sessions.first { $0.id == sessionID } }

    private var sessionEntries: [SportEntry] {
        entries.filter { $0.sessionID == sessionID && $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func doneSets(_ entry: SportEntry, _ profile: UUID) -> [SportSet] {
        sets.filter { $0.entryID == entry.id && $0.profileID == profile && $0.deletedAt == nil && $0.isDone }.sorted { $0.index < $1.index }
    }

    var body: some View {
        if let session {
            content(session)
        } else {
            ContentUnavailableView("Séance introuvable", systemImage: "calendar")
        }
    }

    private func content(_ session: SportSession) -> some View {
        let exercises = ExerciseCatalog.merged(overrides).byID
        let present = profiles.live.filter { session.profileIDs.contains($0.id) }
        let history = SportHistory(sessions: sessions, entries: entries, sets: sets)
        let previousSameTemplate = session.templateID.flatMap { templateID in
            sessions.filter { $0.templateID == templateID && $0.id != sessionID && $0.deletedAt == nil && $0.startedAt < session.startedAt }
                .max { $0.startedAt < $1.startedAt }
        }
        let duration = customDuration ?? (session.endedAt ?? .now).timeIntervalSince(session.startedAt)
        return List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Button { editingDuration = true } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(Format.duration(duration))
                                    .font(.display(.largeTitle))
                                    .monospacedDigit()
                                Image(systemName: "pencil")
                                    .font(.subheadline)
                                    .foregroundStyle(.tint)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Durée \(Format.duration(duration))")
                        .accessibilityHint("Modifier la durée")
                        Text(session.day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(sessionEntries.count) exo\(sessionEntries.count > 1 ? "s" : "")")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            ForEach(recaps(present: present, history: history, exercises: exercises, previous: previousSameTemplate), id: \.profile.id) { recap in
                ProfileRecapSection(recap: recap)
            }

            Section("Détail") {
                ForEach(sessionEntries) { entry in
                    if let exercise = exercises[entry.exerciseRef] {
                        EntryRecapRow(
                            name: exercise.name,
                            lines: present.map { ($0, doneSets(entry, $0.id).map { SetValue(weight: $0.weightKg, reps: $0.reps) }) }
                        )
                    }
                }
            }

            if isFinishing {
                Section {
                    if session.templateID == nil, !sessionEntries.isEmpty {
                        Button("Enregistrer comme modèle", systemImage: "list.bullet.rectangle") { namingTemplate = true }
                    }
                }
            } else {
                Section {
                    if !sessionEntries.isEmpty {
                        Button("Enregistrer comme modèle", systemImage: "list.bullet.rectangle") { namingTemplate = true }
                    }
                    Button("Modifier la séance", systemImage: "pencil") { presenter.sessionID = sessionID }
                    Button("Supprimer la séance", systemImage: "trash", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle(isFinishing ? "Fin de séance" : "Séance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isFinishing {
                ToolbarItem(placement: .cancellationAction) { Button("Continuer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminer") { finish(session) }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .confirmationDialog("Aucune série validée", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("Supprimer la séance", role: .destructive) { remove(session) }
            Button("Continuer la séance", role: .cancel) {}
        } message: {
            Text("Une séance compte quand au moins une série est validée.")
        }
        .confirmationDialog("Supprimer cette séance ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { remove(session) }
        } message: {
            Text("Elle disparaîtra de tous les téléphones et des statistiques.")
        }
        .sheet(isPresented: $editingDuration) {
            DurationEditor(initial: duration) { setDuration($0, of: session) }
                .presentationDetents([.medium])
        }
        .alert("Nom du modèle", isPresented: $namingTemplate) {
            TextField("Push, Dos-Biceps…", text: $templateName)
            Button("Annuler", role: .cancel) {}
            Button("Enregistrer") { saveTemplate(session) }
        }
    }

    private func recaps(present: [SportProfile], history: SportHistory, exercises: [String: ExerciseInfo], previous: SportSession?) -> [ProfileRecap] {
        present.map { profile in
            let done = sessionEntries.flatMap { doneSets($0, profile.id) }
            let total = done.reduce(0) { $0 + $1.weightKg * Double($1.reps) }
            let before = previous.map { volume(of: $0, profile: profile.id) } ?? 0
            return ProfileRecap(
                profile: profile,
                setCount: done.count,
                volume: total,
                change: before > 0 ? (total - before) / before * 100 : nil,
                records: records(for: profile.id, history: history, exercises: exercises)
            )
        }
    }

    /// Records battus pendant cette séance : un par exo, le meilleur.
    private func records(for profile: UUID, history: SportHistory, exercises: [String: ExerciseInfo]) -> [String] {
        let day = session?.day ?? .now
        return sessionEntries.compactMap { entry in
            // Seulement ce qui précède la séance : rouvrir une vieille séance ne compare pas au futur.
            let previous = history.previous(profile: profile, exercise: entry.exerciseRef, excluding: sessionID).filter { $0.day <= day }
            var earlier: [SetValue] = []
            var best: SetValue?
            for set in doneSets(entry, profile) {
                let value = SetValue(weight: set.weightKg, reps: set.reps)
                if StrengthStats.isRecord(value, previous: previous + [Performance(sessionID: sessionID, day: .now, sets: earlier)]),
                   StrengthStats.oneRepMax(value) >= StrengthStats.oneRepMax(best ?? SetValue(weight: 0, reps: 0)) {
                    best = value
                }
                earlier.append(value)
            }
            guard let best, let name = exercises[entry.exerciseRef]?.name else { return nil }
            return "Record · \(name) · \(best.label)"
        }
    }

    private func volume(of session: SportSession, profile: UUID) -> Double {
        let ids = Set(entries.filter { $0.sessionID == session.id && $0.deletedAt == nil }.map(\.id))
        return sets.filter { ids.contains($0.entryID) && $0.profileID == profile && $0.isDone && $0.deletedAt == nil }
            .reduce(0) { $0 + $1.weightKg * Double($1.reps) }
    }

    private func finish(_ session: SportSession) {
        let entryIDs = Set(sessionEntries.map(\.id))
        let mine = sets.filter { entryIDs.contains($0.entryID) && $0.deletedAt == nil }
        guard mine.contains(where: \.isDone) else {
            confirmEmpty = true
            return
        }
        // Les séries préparées mais jamais faites n'encombrent pas l'historique.
        for set in mine where !set.isDone { sync.delete(set) }
        session.endedAt = customDuration.map { session.startedAt.addingTimeInterval($0) } ?? .now
        sync.save(session)
        rest.skip()
        close()
    }

    private func setDuration(_ duration: TimeInterval, of session: SportSession) {
        if isFinishing {
            customDuration = duration
        } else {
            session.endedAt = session.startedAt.addingTimeInterval(duration)
            sync.save(session)
        }
    }

    private func remove(_ session: SportSession) {
        sync.delete(session)
        rest.skip()
        close()
    }

    private func close() {
        dismiss()
        if presenter.sessionID == sessionID { presenter.sessionID = nil }
    }

    private func saveTemplate(_ session: SportSession) {
        sync.saveAsTemplate(session, name: templateName, entries: entries, sets: sets, templates: templates)
    }

    private func present(_ session: SportSession) -> [SportProfile] {
        profiles.live.filter { session.profileIDs.contains($0.id) }
    }
}

/// Saisie manuelle de la durée d'une séance, en heures et minutes.
private struct DurationEditor: View {
    let onSave: (TimeInterval) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hours: Int
    @State private var minutes: Int

    init(initial: TimeInterval, onSave: @escaping (TimeInterval) -> Void) {
        self.onSave = onSave
        let total = max(1, Int((initial / 60).rounded()))
        _hours = State(initialValue: min(total / 60, 5))
        _minutes = State(initialValue: total % 60)
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("Heures", selection: $hours) {
                    ForEach(0...5, id: \.self) { Text("\($0) h").tag($0) }
                }
                Picker("Minutes", selection: $minutes) {
                    ForEach(0..<60, id: \.self) { Text("\($0) min").tag($0) }
                }
            }
            .pickerStyle(.wheel)
            .monospacedDigit()
            .padding(.horizontal)
            .navigationTitle("Durée")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        onSave(TimeInterval((hours * 60 + minutes) * 60))
                        dismiss()
                    }
                    .disabled(hours == 0 && minutes == 0)
                }
            }
        }
    }
}

struct ProfileRecap {
    let profile: SportProfile
    let setCount: Int
    let volume: Double
    /// Écart de volume en % avec la séance précédente du même modèle.
    let change: Double?
    let records: [String]
}

private struct ProfileRecapSection: View {
    let recap: ProfileRecap

    var body: some View {
        Section {
            LabeledContent("Séries validées", value: "\(recap.setCount)")
            LabeledContent("Volume soulevé", value: Format.kg(recap.volume))
            if let change = recap.change {
                LabeledContent("Par rapport à la fois d'avant") {
                    Text("\(change >= 0 ? "+" : "−")\(Int(abs(change).rounded())) %")
                        .foregroundStyle(change >= 0 ? .green : .secondary)
                }
            }
            ForEach(recap.records, id: \.self) { record in
                Label {
                    Text(record)
                } icon: {
                    Image(systemName: "trophy.fill").foregroundStyle(.orange)
                }
            }
        } header: {
            HStack(spacing: 8) {
                ProfileAvatar(profile: recap.profile, size: 22)
                Text(recap.profile.name)
            }
            .textCase(nil)
            .font(.headline)
            .foregroundStyle(.primary)
        }
        .monospacedDigit()
    }
}

private struct EntryRecapRow: View {
    let name: String
    let lines: [(SportProfile, [SetValue])]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.body.weight(.medium))
            ForEach(lines.filter { !$0.1.isEmpty }, id: \.0.id) { profile, sets in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle().fill(profile.color).frame(width: 7, height: 7)
                    Text(sets.map(\.label).joined(separator: "  "))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

extension SportSync {
    /// Modèle reprenant les exos de la séance, dans le même ordre, avec autant de séries que le profil qui en a fait le plus.
    func saveAsTemplate(_ session: SportSession, name: String, entries: [SportEntry], sets: [SportSet], templates: [SportTemplate]) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let template = SportTemplate(
            name: trimmed.isEmpty ? "Séance du \(session.day.formatted(.dateTime.day().month()))" : trimmed,
            sortOrder: (templates.filter { $0.deletedAt == nil }.map(\.sortOrder).max() ?? -1) + 1
        )
        save(template)
        let sessionEntries = entries.filter { $0.sessionID == session.id && $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }
        for (index, entry) in sessionEntries.enumerated() {
            let done = sets.filter { $0.entryID == entry.id && $0.deletedAt == nil && $0.isDone }
            let count = Dictionary(grouping: done, by: \.profileID).values.map(\.count).max() ?? 3
            save(SportTemplateItem(templateID: template.id, exerciseRef: entry.exerciseRef, sortOrder: index, setCount: max(1, count)))
        }
        session.templateID = template.id
        save(session)
    }
}
