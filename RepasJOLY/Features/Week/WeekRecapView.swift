import Charts
import SwiftData
import SwiftUI

struct WeekRecapView: View {
    let week: WeekPlan
    @Query private var sessions: [CookingSession]

    init(week: WeekPlan) {
        self.week = week
        let start = week.weekStart
        let end = start.addingTimeInterval(7 * 86_400)
        _sessions = Query(filter: #Predicate<CookingSession> { $0.startedAt >= start && $0.startedAt < end && $0.endedAt != nil })
    }

    private var meals: [MealSlot] { week.orderedSlots.filter { !$0.isAbsent } }

    private func count(_ status: SlotStatus) -> Int { meals.filter { $0.status == status }.count }

    private var proteinSplit: [(category: RecipeCategory, count: Int)] {
        let cooked = meals.filter(\.needsCooking).compactMap(\.recipe?.category)
        return RecipeCategory.allCases
            .map { category in (category, cooked.filter { $0 == category }.count) }
            .filter { $0.1 > 0 }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(count(.done)) sur \(meals.count) repas faits")
                        .font(.display(.title2))
                        .monospacedDigit()
                    Gauge(value: Double(count(.done)), in: 0...Double(max(meals.count, 1))) {}
                        .gaugeStyle(.linearCapacity)
                        .tint(.orange)
                        .accessibilityLabel("Progression")
                }
                .padding(.vertical, 6)
                LabeledContent("Sautés", value: "\(count(.skipped))")
                LabeledContent("Mangés dehors", value: "\(count(.eatenOut))")
                LabeledContent("Restants", value: "\(count(.planned))")
            }
            .monospacedDigit()

            if !proteinSplit.isEmpty {
                Section("Équilibre des protéines") {
                    Chart(proteinSplit, id: \.category) { item in
                        BarMark(x: .value("Repas", item.count), y: .value("Catégorie", item.category.label))
                            .foregroundStyle(.orange)
                            .annotation(position: .trailing) {
                                Text("\(item.count)").font(.caption).foregroundStyle(.secondary)
                            }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: CGFloat(proteinSplit.count) * 34)
                    .padding(.vertical, 8)
                }
            }

            Section("En cuisine") {
                let total = sessions.map(\.activeSeconds).reduce(0, +)
                LabeledContent("Temps total", value: sessions.isEmpty ? "—" : Format.duration(total))
                LabeledContent("Moyenne par recette", value: sessions.isEmpty ? "—" : Format.duration(total / Double(sessions.count)))
                LabeledContent("Recettes chronométrées", value: "\(sessions.count)")
            }
            .monospacedDigit()
        }
        .navigationTitle("Bilan")
        .navigationSubtitle(WeekCalendar.rangeLabel(weekStart: week.weekStart))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WeekHistoryView: View {
    @Query(sort: \WeekPlan.weekStart, order: .reverse) private var weeks: [WeekPlan]

    var body: some View {
        List(weeks) { week in
            NavigationLink(value: week) {
                let meals = week.slots.filter { !$0.isAbsent }
                let done = meals.filter { $0.status == .done }.count
                LabeledContent {
                    Text("\(done)/\(meals.count)").monospacedDigit()
                } label: {
                    Text("Semaine \(WeekCalendar.weekNumber(of: week.weekStart))")
                    Text(WeekCalendar.rangeLabel(weekStart: week.weekStart))
                }
            }
        }
        .overlay {
            if weeks.isEmpty {
                ContentUnavailableView("Aucune semaine", systemImage: "clock", description: Text("Tes semaines planifiées apparaîtront ici."))
            }
        }
        .navigationTitle("Historique")
    }
}
