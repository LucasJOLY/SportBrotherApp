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
    @Query private var templateItems: [SportTemplateItem]
    @State private var starting = false
    @State private var templateSource: SportSession?
    @State private var templateName = ""
    /// Filtres de l'historique : séances où tous ces profils étaient là, d'un modèle, d'un groupe musculaire.
    @State private var filterProfiles: Set<UUID> = []
    @State private var filterTemplate = TemplateFilter.all
    @State private var filterGroup: MuscleGroup?

    enum TemplateFilter: Hashable {
        case all, free
        case template(UUID)
    }

    private var isFiltering: Bool { !filterProfiles.isEmpty || filterTemplate != .all || filterGroup != nil }

    private var liveTemplates: [SportTemplate] {
        templates.filter { $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func matches(_ session: SportSession, exercises: [String: ExerciseInfo]) -> Bool {
        guard filterProfiles.isSubset(of: session.profileIDs) else { return false }
        switch filterTemplate {
        case .all: break
        case .free: if session.templateID != nil { return false }
        case .template(let id): if session.templateID != id { return false }
        }
        if let filterGroup {
            return entries.contains { $0.sessionID == session.id && $0.deletedAt == nil && exercises[$0.exerciseRef]?.group == filterGroup }
        }
        return true
    }

    private var liveSessions: [SportSession] { sessions.filter { $0.deletedAt == nil } }

    /// Séances ouvertes depuis moins de 12 h : celles qu'on peut reprendre, y compris d'un autre téléphone.
    private var ongoing: [SportSession] {
        liveSessions.filter { $0.endedAt == nil && $0.startedAt > .now.addingTimeInterval(-12 * 3600) }
    }

    /// Une séance faite uniquement par des profils privés n'apparaît pas dans l'historique de ce téléphone.
    private var finished: [SportSession] {
        let hidden = Set(profiles.live.filter { !$0.isVisible }.map(\.id))
        return liveSessions.filter { session in
            !ongoing.contains(session) && !(session.profileIDs.allSatisfy(hidden.contains) && !session.profileIDs.isEmpty)
        }
    }

    var body: some View {
        NavigationStack {
            let exercises = ExerciseCatalog.merged(overrides).byID
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

                let shown = isFiltering ? finished.filter { matches($0, exercises: exercises) } : finished
                if !finished.isEmpty {
                    Section {
                        if shown.isEmpty {
                            ContentUnavailableView {
                                Label("Aucune séance", systemImage: "line.3.horizontal.decrease.circle")
                            } description: {
                                Text("Aucune séance ne correspond à ces filtres.")
                            } actions: {
                                Button("Effacer les filtres") { clearFilters() }
                            }
                        }
                        ForEach(shown.prefix(60)) { session in
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
                    } header: {
                        HStack {
                            Text(isFiltering ? "Historique · \(shown.count)" : "Historique")
                            Spacer()
                            if isFiltering {
                                Button("Effacer") { clearFilters() }
                                    .font(.subheadline)
                                    .textCase(nil)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Séance")
            .navigationSubtitle(sync.statusText)
            .toolbar {
                if !finished.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) { filterMenu }
                }
            }
            .navigationDestination(for: UUID.self) { SessionRecapView(sessionID: $0, isFinishing: false) }
            .refreshable { await sync.refresh() }
            .task(id: entries.count + templateItems.count) {
                // Démonstrations des exos qu'on pratique, gardées sur le téléphone pour la salle sans réseau.
                let used = Set(entries.filter { $0.deletedAt == nil }.map(\.exerciseRef))
                    .union(templateItems.filter { $0.deletedAt == nil }.map(\.exerciseRef))
                await ExerciseMedia.prefetch(used.compactMap { exercises[$0] })
            }
            .sheet(isPresented: $starting) { StartSessionSheet() }
            #if DEBUG
            .task { if UserDefaults.standard.bool(forKey: "debugStartSheet") { starting = true } }
            #endif
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

extension SessionHomeView {
    private var filterMenu: some View {
        Menu {
            let visible = profiles.live.filter(\.isVisible)
            if visible.count > 1 {
                Section("Qui était là") {
                    ForEach(visible) { profile in
                        Toggle(profile.name, isOn: Binding(
                            get: { filterProfiles.contains(profile.id) },
                            set: { if $0 { filterProfiles.insert(profile.id) } else { filterProfiles.remove(profile.id) } }
                        ))
                    }
                }
            }
            Section("Type de séance") {
                Picker("Modèle", systemImage: "list.bullet.rectangle", selection: $filterTemplate) {
                    Text("Tous les modèles").tag(TemplateFilter.all)
                    ForEach(liveTemplates) { Text($0.name.isEmpty ? "Sans nom" : $0.name).tag(TemplateFilter.template($0.id)) }
                    Text("Séance libre").tag(TemplateFilter.free)
                }
                .pickerStyle(.menu)
                Picker("Groupe", systemImage: "figure.strengthtraining.traditional", selection: $filterGroup) {
                    Text("Tous les groupes").tag(MuscleGroup?.none)
                    ForEach(MuscleGroup.allCases) { Label($0.label, systemImage: $0.symbol).tag(Optional($0)) }
                }
                .pickerStyle(.menu)
            }
            if isFiltering {
                Button("Effacer les filtres", systemImage: "xmark.circle", role: .destructive) { clearFilters() }
            }
        } label: {
            Label("Filtrer", systemImage: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .menuActionDismissBehavior(.disabled)
    }

    private func clearFilters() {
        withAnimation {
            filterProfiles = []
            filterTemplate = .all
            filterGroup = nil
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
    @Query private var entries: [SportEntry]
    @Query private var sets: [SportSet]
    @Query private var overrides: [SportExercise]
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

                let reproaches = reproaches
                if !reproaches.isEmpty {
                    Section("Inadmissible") {
                        ForEach(reproaches) { reproach in
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    if let name = reproach.name {
                                        Text(name).font(.subheadline.weight(.semibold))
                                    }
                                    Text(reproach.message)
                                }
                            } icon: {
                                Image(systemName: reproach.symbol).foregroundStyle(.red)
                            }
                        }
                    }
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

    struct Reproach: Identifiable {
        let id: String
        let name: String?
        let symbol: String
        let message: String
    }

    /// Pour chaque personne présente, les grands groupes pas travaillés depuis une semaine.
    private var reproaches: [Reproach] {
        let chosen = profiles.live.filter { present.contains($0.id) && $0.isVisible }
        guard !chosen.isEmpty else { return [] }
        let history = SportHistory(sessions: sessions, entries: entries, sets: sets)
        let groups = ExerciseCatalog.merged(overrides).byID.mapValues(\.group)
        return chosen.flatMap { profile -> [Reproach] in
            let skips = SkippedGroups.skipped(profile: profile.id, history: history, groups: groups, today: day)
            let name = chosen.count > 1 ? profile.name : nil
            // Tout est à la traîne : un seul savon plutôt que sept.
            if skips.count == MuscleGroup.allCases.count, let freshest = skips.map(\.days).min() {
                return [Reproach(id: "\(profile.id)-all", name: name, symbol: "exclamationmark.triangle.fill",
                                 message: "Pas une seule série depuis \(freshest) jours. T'as tout skip, c'est inadmissible. Bouge-toi.")]
            }
            return skips.map {
                Reproach(id: "\(profile.id)-\($0.group.rawValue)", name: name, symbol: $0.group.symbol, message: SkippedGroups.message($0))
            }
        }
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
