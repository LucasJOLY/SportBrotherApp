import SwiftData
import SwiftUI

/// Base locale unique, partagée par l'app et les raccourcis Siri.
enum AppStore {
    static let schema = Schema([
        Recipe.self, WeekPlan.self, MealSlot.self, CookingSession.self,
        ShoppingMark.self, ManualShoppingItem.self, UserProfile.self, StockItem.self, ShoppingPlan.self,
    ])

    /// `-sampleData` : base en mémoire remplie de données de démonstration.
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
}

@main
struct RepasJOLYApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(AppStore.container)
    }
}
