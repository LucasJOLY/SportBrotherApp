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
            if rest.isRunning { RestBanner().padding(.horizontal, 16).padding(.bottom, 8) }
        }
        .animation(.snappy, value: rest.isRunning)
        .sensoryFeedback(.success, trigger: rest.finishedCount)
        #if DEBUG
        .task {
            if UserDefaults.standard.bool(forKey: "debugSportEntry"), path.isEmpty, let first = sessionEntries.first { path = [first.id] }
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
                                    EntryProgress(entry: entry, sets: sets, profiles: present)
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

/// Compte à rebours du repos, avec ajustement rapide.
struct RestBanner: View {
    @Environment(RestTimer.self) private var rest

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 0) {
                Text("Repos").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let end = rest.endsAt {
                    Text(timerInterval: Date.now...max(end, .now), countsDown: true)
                        .font(.display(.title2))
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
            // Le compte à rebours réclame toute la largeur : les boutons gardent leur taille, sur une ligne.
            Group {
                Button("−15\u{00A0}s") { rest.add(-15) }
                Button("+15\u{00A0}s") { rest.add(15) }
                Button("Arrêter le repos", systemImage: "xmark") { rest.skip() }
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.glass)
            .lineLimit(1)
            .fixedSize()
        }
        .monospacedDigit()
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(in: .rect(cornerRadius: 22, style: .continuous))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
