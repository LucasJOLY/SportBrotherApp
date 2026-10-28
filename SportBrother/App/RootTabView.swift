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

/// Les deux grandes parties de l'app.
enum AppSection: String {
    case food, sport

    mutating func toggle() { self = self == .food ? .sport : .food }
}

/// Valeur réservée à l'onglet qui bascule de section : il n'est jamais sélectionné.
let sectionSwitchTab = 99

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("section") private var section: AppSection = .food
    @State private var launcher = CookingLauncher()
    @State private var foodTab = UserDefaults.standard.integer(forKey: "debugTab")
    @State private var sportTab = UserDefaults.standard.integer(forKey: "debugSportTab")

    var body: some View {
        ZStack {
            switch section {
            case .food:
                foodTabs
                    .onChange(of: foodTab) { old, new in switchIfNeeded($foodTab, from: old, to: new) }
                    .transition(sectionTransition)
            case .sport:
                SportTabView(tab: $sportTab)
                    .onChange(of: sportTab) { old, new in switchIfNeeded($sportTab, from: old, to: new) }
                    .transition(sectionTransition)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35), value: section)
        .sensoryFeedback(.selection, trigger: section)
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

    private var foodTabs: some View {
        TabView(selection: $foodTab) {
            Tab("Semaine", systemImage: "calendar", value: 0) { WeekView() }
            Tab("Recettes", systemImage: "book.closed", value: 1) { RecipeLibraryView() }
            Tab("Courses", systemImage: "cart", value: 2) { ShoppingListView() }
            Tab("Réglages", systemImage: "gearshape", value: 3) { SettingsView() }
            Tab("Sport", systemImage: "dumbbell", value: sectionSwitchTab, role: .search) { Color.clear }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    private var sectionTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
    }

    /// Toucher l'onglet de bascule change de section. La barre native l'a déjà sélectionné :
    /// on accepte la valeur puis on revient à l'onglet précédent, pour que barre et état restent d'accord
    /// (refuser la valeur laissait la barre bloquée sur un onglet vide). Chaque section garde son dernier onglet.
    private func switchIfNeeded(_ tab: Binding<Int>, from old: Int, to new: Int) {
        guard new == sectionSwitchTab else { return }
        tab.wrappedValue = old == sectionSwitchTab ? 0 : old
        section.toggle()
    }
}
