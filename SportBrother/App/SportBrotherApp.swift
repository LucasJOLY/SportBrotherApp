import SwiftData
import SwiftUI

/// Base locale unique, partagée par l'app et les raccourcis Siri.
/// La Nourriture vit uniquement ici ; le Sport y garde son cache, synchronisé avec Supabase.
enum AppStore {
    static let schema = Schema([
        Recipe.self, WeekPlan.self, MealSlot.self, CookingSession.self,
        ShoppingMark.self, ManualShoppingItem.self, UserProfile.self, StockItem.self, ShoppingPlan.self,
        SportProfile.self, SportBodyWeight.self, SportExercise.self, SportTemplate.self, SportTemplateItem.self,
        SportSession.self, SportEntry.self, SportSet.self, SportFeedback.self, SportCoachReview.self, SportOutboxItem.self,
    ])

    /// `-sampleData` : base en mémoire remplie de données de démonstration, synchro coupée.
    static let isSampleMode = ProcessInfo.processInfo.arguments.contains("-sampleData")

    static let container: ModelContainer = {
        do {
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: isSampleMode))
            if isSampleMode { SampleData.insert(into: container.mainContext) }
            return container
        } catch {
            fatalError("Impossible d'ouvrir la base locale : \(error)")
        }
    }()

    static let sportSync = SportSync(context: container.mainContext, enabled: !isSampleMode)
}

@main
struct SportBrotherApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(AppStore.sportSync)
        }
        .modelContainer(AppStore.container)
        .onChange(of: scenePhase, initial: true) {
            guard scenePhase == .active else { return }
            AppStore.sportSync.start()
            Task { await AppStore.sportSync.refresh() }
            Task { await CreatineReminder.schedule() }
        }
    }
}
