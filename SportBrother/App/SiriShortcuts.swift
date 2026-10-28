import AppIntents
import SwiftData

/// Phrase lue par Siri pour les repas du jour.
nonisolated enum MealAnnouncer {
    struct Meal: Sendable {
        let isLunch: Bool
        let title: String?
        let status: SlotStatus
        let isLeftover: Bool
    }

    static func sentence(for meals: [Meal]) -> String {
        guard !meals.isEmpty else { return "Rien n'est prévu aujourd'hui." }
        return meals.map { meal in
            let moment = meal.isLunch ? "Ce midi" : "Ce soir"
            switch meal.status {
            case .eatenOut: return "\(moment), tu manges dehors."
            case .skipped: return "\(moment), le repas est sauté."
            case .done: return "\(moment), c'est déjà fait."
            case .planned:
                guard let title = meal.title else { return "\(moment), aucune recette n'est prévue." }
                return meal.isLeftover ? "\(moment), tu finis le reste de \(title)." : "\(moment) : \(title)."
            }
        }
        .joined(separator: " ")
    }
}

struct TodayMealsIntent: AppIntent {
    static let title: LocalizedStringResource = "Repas du jour"
    static let description = IntentDescription("Dit ce qui est prévu aujourd'hui, midi et soir.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = AppStore.container.mainContext
        guard let week = WeekPlanner(context: context).week() else {
            return .result(dialog: "Ta semaine n'est pas encore planifiée.")
        }
        let today = WeekCalendar.dayIndex(of: .now)
        let afternoon = Calendar.current.component(.hour, from: .now) >= 15
        let meals = [SportBrother.Meal.lunch, .dinner]
            .filter { !afternoon || $0 == .dinner }
            .compactMap { week.slot(day: today, meal: $0) }
            .filter { !$0.isAbsent }
            .map { MealAnnouncer.Meal(isLunch: $0.meal == .lunch, title: $0.recipe?.title, status: $0.status, isLeftover: $0.isLeftover) }
        return .result(dialog: "\(MealAnnouncer.sentence(for: meals))")
    }
}

struct AddShoppingItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Ajouter aux courses"
    static let description = IntentDescription("Ajoute un article à la liste de courses de la semaine.")

    @Parameter(title: "Article", requestValueDialog: "Quel article ?")
    var item: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let name = ShoppingListBuilder.displayName(item)
        guard !name.isEmpty else { return .result(dialog: "Je n'ai pas compris l'article.") }
        let context = AppStore.container.mainContext
        context.insert(ManualShoppingItem(name: name, weekStart: WeekCalendar.monday(of: .now)))
        try context.save()
        return .result(dialog: "\(name) est ajouté aux courses.")
    }
}

struct SportBrotherShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TodayMealsIntent(),
            phrases: [
                "Qu'est-ce qu'on mange avec \(.applicationName)",
                "Qu'est-ce qu'on mange ce soir avec \(.applicationName)",
                "Repas du jour dans \(.applicationName)",
            ],
            shortTitle: "Repas du jour",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: AddShoppingItemIntent(),
            phrases: [
                "Ajoute aux courses dans \(.applicationName)",
                "Ajouter un article dans \(.applicationName)",
            ],
            shortTitle: "Ajouter aux courses",
            systemImageName: "cart.badge.plus"
        )
    }
}
