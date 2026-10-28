import SwiftData
import SwiftUI

struct SessionHomeView: View {
    @Environment(SportSync.self) private var sync
    @Environment(LiveSessionPresenter.self) private var presenter
    @Query(sort: \SportSession.startedAt, order: .reverse) private var sessions: [SportSession]
    @Query private var entries: [SportEntry]
    @Query private var sets: [SportSet]
    @Query private var profiles: [SportProfile]
    @Query private var overrides: [SportExercise]
    @Query private var templates: [SportTemplate]
    @AppStorage(myProfileKey) private var myProfileID = ""
    @State private var starting = false
    @State private var templateSource: SportSession?
    @State private var templateName = ""

    private var liveSessions: [SportSession] { sessions.filter { $0.deletedAt == nil } }

    /// Séances ouvertes depuis moins de 12 h : celles qu'on peut reprendre, y compris d'un autre téléphone.
    private var ongoing: [SportSession] {
        liveSessions.filter { $0.endedAt == nil && $0.startedAt > .now.addingTimeInterval(-12 * 3600) }
    }

    private var finished: [SportSession] {
        liveSessions.filter { !ongoing.contains($0) }
    }

    var body: some View {
        NavigationStack {
            let exercises = ExerciseCatalog.merged(overrides).byID
            let history = SportHistory(sessions: sessions, entries: entries, sets: sets)
            List {
                ForEach(ongoing) { session in
                    Section {
                        OngoingSessionCard(session: session, profiles: profiles.live) {
                            presenter.sessionID = session.id
                        }
                    }
                }

                Section {
                    Button {
                        starting = true
                    } label: {
                        Label("Démarrer une séance", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if let me = UUID(uuidString: myProfileID) {
                    let groups = exercises.mapValues(\.group)
                    let neglected = NeglectedGroups.compute(lastTrained: history.lastTrained(profile: me, groups: groups))
                    if !neglected.isEmpty {
                        Section {
                            ForEach(neglected, id: \.group) { item in
                                LabeledContent {
                                    Text("\(item.days) j").monospacedDigit()
                                } label: {
                                    Label(item.group.label, systemImage: item.group.symbol)
                                        .foregroundStyle(.primary)
                                }
                            }
                        } header: {
                            Text("Pas travaillé depuis un moment")
                        }
                    }
                }

                if !finished.isEmpty {
                    Section("Historique") {
                        ForEach(finished.prefix(60)) { session in
                            NavigationLink(value: session.id) {
                                SessionRowLabel(session: session, entries: entries, sets: sets, profiles: profiles, exercises: exercises)
                            }
                            .swipeActions(edge: .leading) {
                                Button("Modèle", systemImage: "list.bullet.rectangle") { templateSource = session }
                                    .tint(.orange)
                            }
                            .contextMenu {
                                Button("Enregistrer comme modèle", systemImage: "list.bullet.rectangle") { templateSource = session }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Séance")
            .navigationSubtitle(sync.statusText)
            .navigationDestination(for: UUID.self) { SessionRecapView(sessionID: $0, isFinishing: false) }
            .refreshable { await sync.refresh() }
            .sheet(isPresented: $starting) { StartSessionSheet() }
            .alert("Nom du modèle", isPresented: Binding(get: { templateSource != nil }, set: { if !$0 { templateSource = nil } })) {
                TextField("Push, Dos-Biceps…", text: $templateName)
                Button("Annuler", role: .cancel) { templateName = "" }
                Button("Enregistrer") {
                    if let templateSource {
                        sync.saveAsTemplate(templateSource, name: templateName, entries: entries, sets: sets, templates: templates)
                    }
                    templateName = ""
                }
            } message: {
                Text("Mêmes exos, même ordre, même nombre de séries. À retrouver dans Exos › Modèles.")
            }
        }
    }
}

struct OngoingSessionCard: View {
    let session: SportSession
    let profiles: [SportProfile]
    let resume: () -> Void

    var body: some View {
        Button(action: resume) {
            HStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, options: .repeating)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Séance en cours").font(.headline)
                    HStack(spacing: 4) {
                        Text(names)
                        Text("·")
                        Text(session.startedAt, style: .timer).monospacedDigit()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Reprendre")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .tint(.primary)
    }

    private var names: String {
        profiles.filter { session.profileIDs.contains($0.id) }.map(\.name).formatted(.list(type: .and))
    }
}

struct SessionRowLabel: View {
    let session: SportSession
    let entries: [SportEntry]
    let sets: [SportSet]
    let profiles: [SportProfile]
    let exercises: [String: ExerciseInfo]

    var body: some View {
        let mine = entries.filter { $0.sessionID == session.id && $0.deletedAt == nil }
        let groups = Array(Set(mine.compactMap { exercises[$0.exerciseRef]?.group })).sorted { $0.sortIndex < $1.sortIndex }
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(session.day.formatted(.dateTime.day()))
                    .font(.display(.title3))
                Text(session.day.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(groups.isEmpty ? "Séance" : groups.map(\.label).joined(separator: " · "))
                    .lineLimit(2)
                HStack(spacing: -6) {
                    ForEach(profiles.filter { session.profileIDs.contains($0.id) }) { profile in
                        ProfileAvatar(profile: profile, size: 20)
                            .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                    }
                    Text("\(mine.count) exo\(mine.count > 1 ? "s" : "")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                }
            }
        }
    }
}

// MARK: Démarrage

struct StartSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SportSync.self) private var sync
    @Environment(LiveSessionPresenter.self) private var presenter
    @Query private var profiles: [SportProfile]
    @Query(sort: \SportTemplate.sortOrder) private var templates: [SportTemplate]
    @Query private var templateItems: [SportTemplateItem]
    @Query(sort: \SportSession.startedAt, order: .reverse) private var sessions: [SportSession]
    @AppStorage(myProfileKey) private var myProfileID = ""
    @State private var present: Set<UUID> = []
    @State private var day = Date.now
    @State private var templateID: UUID?

    private var liveTemplates: [SportTemplate] { templates.filter { $0.deletedAt == nil } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Qui est là ?") {
                    FlowLayout {
                        ForEach(profiles.live) { profile in
                            ChipToggle(title: profile.name, isOn: present.contains(profile.id)) {
                                if present.contains(profile.id) { present.remove(profile.id) } else { present.insert(profile.id) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if !liveTemplates.isEmpty {
                    Section("Partir d'un modèle") {
                        Picker("Modèle", selection: $templateID) {
                            Text("Séance libre").tag(UUID?.none)
                            ForEach(liveTemplates) { Text($0.name.isEmpty ? "Sans nom" : $0.name).tag(Optional($0.id)) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }

                Section {
                    DatePicker("Jour", selection: $day, in: ...Date.now, displayedComponents: .date)
                } footer: {
                    Text("Change le jour pour rattraper une séance oubliée.")
                }
            }
            .navigationTitle("Nouvelle séance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("C'est parti") { start() }
                        .disabled(present.isEmpty)
                }
            }
            .onAppear(perform: preselect)
        }
        .presentationDetents([.medium, .large])
    }

    /// Mon profil, plus ceux de la dernière séance faite ensemble.
    private func preselect() {
        if let me = UUID(uuidString: myProfileID) { present.insert(me) }
        if let last = sessions.first(where: { $0.deletedAt == nil }), last.profileIDs.contains(where: { present.contains($0) }) {
            present.formUnion(last.profileIDs.filter { id in profiles.live.contains { $0.id == id } })
        }
    }

    private func start() {
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(day)
        let session = SportSession(
            day: calendar.startOfDay(for: day),
            startedAt: isToday ? .now : calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? day,
            profileIDs: profiles.live.map(\.id).filter(present.contains),
            templateID: templateID
        )
        sync.save(session)
        if let templateID {
            let items = templateItems.filter { $0.templateID == templateID && $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }
            for (index, item) in items.enumerated() {
                sync.save(SportEntry(sessionID: session.id, exerciseRef: item.exerciseRef, sortOrder: index))
            }
        }
        dismiss()
        presenter.sessionID = session.id
    }
}
