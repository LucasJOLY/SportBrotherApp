import SwiftData
import SwiftUI

/// Ouvre le mode cuisson depuis n'importe quel écran.
@Observable
final class CookingLauncher {
    var controller: CookingController?

    func start(_ recipe: Recipe, slot: MealSlot? = nil, servings: Int = QuantityScaler.baseServings, context: ModelContext) {
        controller = CookingController(recipe: recipe, slot: slot, servings: servings, context: context)
    }
}

extension CookingController: Identifiable {
    var id: UUID { session.id }
}

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @State private var launcher = CookingLauncher()
    @State private var tab = UserDefaults.standard.integer(forKey: "debugTab")

    var body: some View {
        TabView(selection: $tab) {
            Tab("Semaine", systemImage: "calendar", value: 0) { WeekView() }
            Tab("Recettes", systemImage: "book.closed", value: 1) { RecipeLibraryView() }
            Tab("Courses", systemImage: "cart", value: 2) { ShoppingListView() }
            Tab("Réglages", systemImage: "gearshape", value: 3) { SettingsView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(.orange)
        #if DEBUG
        .task {
            // Captures d'écran : `-debugCook YES` ouvre le mode cuisson sur la première recette.
            if UserDefaults.standard.bool(forKey: "debugCook"),
               let recipe = try? context.fetch(FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\.title)])).first(where: { $0.steps.count > 2 }) {
                launcher.start(recipe, context: context)
            }
        }
        #endif
        .fullScreenCover(item: $launcher.controller) { controller in
            CookingView(controller: controller)
                .tint(.orange)
        }
        .environment(launcher)
    }
}
