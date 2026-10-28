import SwiftData
import SwiftUI

/// Séance en cours affichée en plein écran ; partagée pour survivre aux changements d'onglet.
@Observable
final class LiveSessionPresenter {
    var sessionID: UUID?
}

/// État Sport qui doit survivre à la bascule de section.
enum SportRuntime {
    static let presenter = LiveSessionPresenter()
    static let rest = RestTimer()
}

/// Clé du profil de ce téléphone (choisi une fois, modifiable dans Profils).
let myProfileKey = "sportMyProfile"

extension Array where Element == SportProfile {
    /// Profils non supprimés, dans l'ordre choisi.
    var live: [SportProfile] {
        filter { $0.deletedAt == nil }.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }
}

struct SportTabView: View {
    @Binding var tab: Int
    @Environment(SportSync.self) private var sync
    @Environment(\.modelContext) private var context
    @Query private var profiles: [SportProfile]
    @AppStorage(myProfileKey) private var myProfileID = ""
    @Bindable private var presenter = SportRuntime.presenter

    private var me: SportProfile? { profiles.live.first { $0.id.uuidString == myProfileID } }

    var body: some View {
        Group {
            if me == nil {
                WhoAreYouView()
            } else {
                TabView(selection: $tab) {
                    Tab("Séance", systemImage: "figure.strengthtraining.traditional", value: 0) { SessionHomeView() }
                    Tab("Exos", systemImage: "dumbbell", value: 1) { ExerciseLibraryView() }
                    Tab("Stats", systemImage: "chart.xyaxis.line", value: 2) { SportStatsView() }
                    Tab("Profils", systemImage: "person.2", value: 3) { ProfilesView() }
                    Tab("Repas", systemImage: "fork.knife", value: sectionSwitchTab, role: .search) { Color.clear }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
            }
        }
        .environment(SportRuntime.rest)
        .environment(presenter)
        #if DEBUG
        .task {
            // Captures d'écran : `-debugSportSession YES` ouvre une séance depuis le premier modèle.
            guard UserDefaults.standard.bool(forKey: "debugSportSession"), presenter.sessionID == nil,
                  let template = try? context.fetch(FetchDescriptor<SportTemplate>(sortBy: [SortDescriptor(\.sortOrder)])).first else { return }
            let session = SportSession(day: Calendar.current.startOfDay(for: .now), startedAt: .now.addingTimeInterval(-1260), profileIDs: profiles.live.map(\.id), templateID: template.id)
            sync.save(session)
            let items = ((try? context.fetch(FetchDescriptor<SportTemplateItem>())) ?? []).filter { $0.templateID == template.id }.sorted { $0.sortOrder < $1.sortOrder }
            for (index, item) in items.enumerated() { sync.save(SportEntry(sessionID: session.id, exerciseRef: item.exerciseRef, sortOrder: index)) }
            presenter.sessionID = session.id
        }
        #endif
        .fullScreenCover(item: Binding(
            get: { presenter.sessionID.map(IdentifiedID.init) },
            set: { presenter.sessionID = $0?.id }
        )) { item in
            LiveSessionView(sessionID: item.id)
                .environment(sync)
                .environment(SportRuntime.rest)
                .environment(presenter)
                .tint(.orange)
        }
    }
}

struct IdentifiedID: Identifiable {
    let id: UUID
}

extension SportSync {
    /// Statut de synchro, vide quand tout est à jour.
    var statusText: String {
        if !isConfigured { return "Mode local" }
        if !isOnline { return pendingCount > 0 ? "Hors ligne · \(pendingCount) en attente" : "Hors ligne" }
        if pendingCount > 0 { return "Envoi…" }
        return ""
    }
}
