import Foundation
import SwiftData

@Model
final class WeekPlan {
    /// Lundi 00:00 de la semaine.
    @Attribute(.unique) var weekStart: Date
    var usedAI: Bool
    var excludedRecipeIDs: [UUID]
    var excludedCategories: [RecipeCategory]

    @Relationship(deleteRule: .cascade, inverse: \MealSlot.week)
    var slots: [MealSlot] = []

    init(weekStart: Date, usedAI: Bool = true) {
        self.weekStart = weekStart
        self.usedAI = usedAI
        self.excludedRecipeIDs = []
        self.excludedCategories = []
    }

    var orderedSlots: [MealSlot] { slots.sorted { $0.order < $1.order } }

    func slot(day: Int, meal: Meal) -> MealSlot? {
        slots.first { $0.day == day && $0.meal == meal }
    }

    func date(forDay day: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: day, to: weekStart) ?? weekStart
    }
}

@Model
final class MealSlot {
    @Attribute(.unique) var id: UUID
    /// 0 = lundi … 6 = dimanche.
    var day: Int
    var meal: Meal
    /// 0 = absent, 1 = seul (on cuisine pour 2), 2 = à deux.
    var diners: Int
    var recipe: Recipe?
    var isLocked: Bool
    /// Créneau dont ce repas mange le reste.
    var leftoverSourceID: UUID?
    var status: SlotStatus
    var week: WeekPlan?

    init(day: Int, meal: Meal, diners: Int) {
        self.id = UUID()
        self.day = day
        self.meal = meal
        self.diners = diners
        self.isLocked = false
        self.status = .planned
    }

    var order: Int { day * 2 + (meal == .lunch ? 0 : 1) }
    var isLeftover: Bool { leftoverSourceID != nil }
    var isAbsent: Bool { diners == 0 }
    /// Repas à cuisiner (ni absent, ni reste).
    var needsCooking: Bool { !isAbsent && !isLeftover }
}

@Model
final class CookingSession {
    @Attribute(.unique) var id: UUID
    var recipe: Recipe?
    var slotID: UUID?
    var startedAt: Date
    var endedAt: Date?
    var pausedSeconds: TimeInterval

    init(recipe: Recipe, slotID: UUID?, startedAt: Date = .now) {
        self.id = UUID()
        self.recipe = recipe
        self.slotID = slotID
        self.startedAt = startedAt
        self.pausedSeconds = 0
    }

    var activeSeconds: TimeInterval {
        max(0, (endedAt ?? .now).timeIntervalSince(startedAt) - pausedSeconds)
    }
}
