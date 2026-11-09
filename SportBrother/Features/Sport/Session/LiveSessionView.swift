import SwiftData
import SwiftUI

/// Séance en cours, en plein écran : liste des exos, ajout, réordonnancement, repos.
struct LiveSessionView: View {
    let sessionID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(SportSync.self) private var sync
    @Environment(RestTimer.self) private var rest
    @Query private var sessions: [SportSession]
    @Query private var entries: [SportEntry]
    @Query private var sets: [SportSet]
    @Query private var profiles: [SportProfile]
    @Query private var overrides: [SportExercise]
    @State private var picking = false
    @State private var finishing = false
    @State private var path: [UUID] = []

    private var session: SportSession? { sessions.first { $0.id == sessionID } }

    private var sessionEntries: [SportEntry] {
        entries.filter { $0.sessionID == sessionID && $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack(path: $path) {
            if let session, session.deletedAt == nil {
                content(session)
            } else {
                ContentUnavailableView("Séance supprimée", systemImage: "trash")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if rest.isRunning { RestBanner(showNames: (session?.profileIDs.count ?? 0) > 1).padding(.horizontal, 16).padding(.bottom, 8) }
        }
        .animation(.snappy, value: rest.isRunning)
        .sensoryFeedback(.success, trigger: rest.finishedCount)
        #if DEBUG
        .task {
            if UserDefaults.standard.bool(forKey: "debugSportEntry"), path.isEmpty, let first = sessionEntries.first { path = [first.id] }
            if UserDefaults.standard.bool(forKey: "debugRestTimers"), !rest.isRunning, let session {
                for (offset, id) in session.profileIDs.enumerated() {
                    rest.start(seconds: 90 + offset * 40, profile: id, exercise: "Développé couché", detail: "Série 2/4")
                }
            }
        }
        #endif
    }

    private func content(_ session: SportSession) -> some View {
        let exercises = ExerciseCatalog.merged(overrides).byID
        let present = profiles.live.filter { session.profileIDs.contains($0.id) }
        return List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                            Text(Format.clock(context.date.timeIntervalSince(session.startedAt)))
                                .font(.display(.largeTitle))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                        Text(Calendar.current.isDateInToday(session.day) ? "Aujourd'hui" : session.day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: -8) {
                        ForEach(present) { profile in
                            ProfileAvatar(profile: profile, size: 34)
                                .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel(present.map(\.name).formatted(.list(type: .and)))
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(sessionEntries) { entry in
                    if let exercise = exercises[entry.exerciseRef] {
                        NavigationLink(value: entry.id) {
                            HStack(spacing: 12) {
                                ExerciseThumbnail(exercise: exercise, size: 48)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(exercise.name).lineLimit(2)
                                    EntryProgress(entry: entry, sets: sets, profiles: present.filter(\.isVisible))
                                }
                            }
                        }
                    }
                }
                .onMove { move(from: $0, to: $1) }
                .onDelete { offsets in offsets.map { sessionEntries[$0] }.forEach(sync.delete) }

                Button("Ajouter des exos", systemImage: "plus") { picking = true }
            } header: {
                if !sessionEntries.isEmpty { Text("Exos") }
            }
        }
        .navigationTitle("Séance")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: UUID.self) { EntryView(entryID: $0, sessionID: sessionID) }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Réduire", systemImage: "chevron.down") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Terminer") { finishing = true }
            }
        }
        .overlay {
            if sessionEntries.isEmpty {
                ContentUnavailableView {
                    Label("Séance vide", systemImage: "dumbbell")
                } description: {
                    Text("Ajoute les exos au fur et à mesure, tes favoris passent en premier.")
                } actions: {
                    Button("Ajouter des exos") { picking = true }.buttonStyle(.glassProminent)
                }
            }
        }
        .sheet(isPresented: $picking) {
            ExercisePicker(title: "Ajouter à la séance") { picked in
                let start = (sessionEntries.map(\.sortOrder).max() ?? -1) + 1
                var added: [SportEntry] = []
                for (offset, exercise) in picked.enumerated() {
                    let entry = SportEntry(sessionID: sessionID, exerciseRef: exercise.id, sortOrder: start + offset)
                    sync.save(entry)
                    added.append(entry)
                }
                // Un seul exo ajouté : on y va directement.
                if added.count == 1, let entry = added.first { path.append(entry.id) }
            }
        }
        .sheet(isPresented: $finishing) {
            NavigationStack { SessionRecapView(sessionID: sessionID, isFinishing: true) }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = sessionEntries
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, entry) in ordered.enumerated() where entry.sortOrder != index {
            entry.sortOrder = index
            sync.save(entry)
        }
    }
}

/// « Lucas 3/4 · Tom 2/4 » : séries validées par profil.
struct EntryProgress: View {
    let entry: SportEntry
    let sets: [SportSet]
    let profiles: [SportProfile]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(profiles) { profile in
                let mine = sets.filter { $0.entryID == entry.id && $0.profileID == profile.id && $0.deletedAt == nil }
                if !mine.isEmpty {
                    let done = mine.filter(\.isDone).count
                    HStack(spacing: 4) {
                        Circle().fill(profile.color).frame(width: 7, height: 7)
                        Text(profiles.count > 1 ? "\(profile.name) \(done)/\(mine.count)" : "\(done)/\(mine.count) séries")
                    }
                    .font(.subheadline)
                    .foregroundStyle(done == mine.count ? .primary : .secondary)
                    .monospacedDigit()
                }
            }
        }
    }
}

/// Comptes à rebours du repos, empilés quand on est plusieurs : un par personne, chacun ajustable.
struct RestBanner: View {
    /// Séance à plusieurs : chaque ligne porte le prénom et la couleur de la personne.
    var showNames = false
    @Environment(RestTimer.self) private var rest
    @Query private var profiles: [SportProfile]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rest.timers.enumerated()), id: \.element.id) { index, timer in
                if index > 0 { Divider().padding(.leading, 16) }
                RestRow(timer: timer, profile: showNames ? profiles.first { $0.id == timer.id } : nil, compact: rest.timers.count > 1)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.snappy, value: rest.timers.map(\.id))
        .glassEffect(in: .rect(cornerRadius: 22, style: .continuous))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct RestRow: View {
    let timer: RestTimer.Rest
    let profile: SportProfile?
    let compact: Bool
    @Environment(RestTimer.self) private var rest

    var body: some View {
        HStack(spacing: 12) {
            if let profile {
                Circle().fill(profile.color).frame(width: 10, height: 10)
            } else {
                Image(systemName: "timer").font(.title3).foregroundStyle(.tint)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(profile.map { "Repos \($0.name)" } ?? "Repos")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(timerInterval: Date.now...max(timer.endsAt, .now), countsDown: true)
                    .font(.display(compact ? .title3 : .title2))
            }
            Spacer(minLength: 0)
            // Le compte à rebours réclame toute la largeur : les boutons gardent leur taille, sur une ligne.
            Group {
                Button("−15\u{00A0}s") { rest.add(-15, to: timer.id) }
                Button("+15\u{00A0}s") { rest.add(15, to: timer.id) }
                Button(profile.map { "Arrêter le repos de \($0.name)" } ?? "Arrêter le repos", systemImage: "xmark") { rest.skip(timer.id) }
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.glass)
            .controlSize(compact ? .small : .regular)
            .lineLimit(1)
            .fixedSize()
        }
        .monospacedDigit()
        .padding(.horizontal, 16)
        .padding(.vertical, compact ? 7 : 10)
        .accessibilityElement(children: .contain)
    }
}
