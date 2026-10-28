import Charts
import SwiftData
import SwiftUI

struct StatsView: View {
    @Query(sort: \WeekPlan.weekStart, order: .reverse) private var weeks: [WeekPlan]
    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    @Query(filter: #Predicate<CookingSession> { $0.endedAt != nil }) private var sessions: [CookingSession]

    private var scores: [CookingStats.WeekScore] {
        weeks.map { week in
            let meals = week.slots.filter { !$0.isAbsent }
            return .init(weekStart: week.weekStart, done: meals.filter { $0.status == .done }.count, planned: meals.count)
        }
    }

    private var streak: Int {
        CookingStats.streak(scores, currentWeekStart: WeekCalendar.monday(of: .now))
    }

    /// Recettes cuisinées : repas faits (hors restes) par recette.
    private var mostCooked: [(recipe: Recipe, count: Int)] {
        recipes
            .map { recipe in (recipe, recipe.slots.filter { $0.status == .done && $0.needsCooking }.count) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .map { $0 }
    }

    private var faster: [(recipe: Recipe, first: TimeInterval, last: TimeInterval)] {
        recipes.compactMap { recipe in
            CookingStats.progression(recipe.finishedSessions.map { ($0.startedAt, $0.activeSeconds) })
                .map { (recipe, $0.first, $0.last) }
        }
        .filter { $0.last < $0.first }
        .sorted { ($0.first - $0.last) > ($1.first - $1.last) }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(streak == 0 ? "Pas encore de série" : "\(streak) semaine\(streak > 1 ? "s" : "") d'affilée")
                        .font(.display(.title2))
                        .monospacedDigit()
                    Text("Une semaine compte quand au moins 80 % des repas prévus sont faits.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)

                let recent = Array(scores.filter { $0.planned > 0 }.prefix(8).reversed())
                if recent.count > 1 {
                    Chart(recent, id: \.weekStart) { week in
                        BarMark(
                            x: .value("Semaine", "S\(WeekCalendar.weekNumber(of: week.weekStart))"),
                            y: .value("Repas faits", week.ratio * 100)
                        )
                        .foregroundStyle(week.ratio >= CookingStats.threshold ? Color.orange : Color.secondary.opacity(0.4))
                        RuleMark(y: .value("Objectif", CookingStats.threshold * 100))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(.secondary)
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(values: [0, 50, 100]) { value in
                            AxisGridLine()
                            AxisValueLabel { Text("\(value.as(Int.self) ?? 0) %") }
                        }
                    }
                    .frame(height: 160)
                    .padding(.vertical, 8)
                    .accessibilityLabel("Repas faits par semaine")
                }
            }

            Section("Les plus cuisinées") {
                if mostCooked.isEmpty {
                    Text("Coche tes repas faits pour voir apparaître tes classiques.")
                        .foregroundStyle(.secondary)
                }
                ForEach(mostCooked, id: \.recipe.id) { item in
                    NavigationLink(value: item.recipe) {
                        HStack(spacing: 12) {
                            RecipeThumbnail(recipe: item.recipe, size: 36)
                            Text(item.recipe.title).lineLimit(2)
                            Spacer()
                            Text("×\(item.count)")
                                .font(.headline)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !faster.isEmpty {
                Section {
                    ForEach(faster, id: \.recipe.id) { item in
                        LabeledContent {
                            HStack(spacing: 4) {
                                Text(Format.duration(item.first)).foregroundStyle(.secondary)
                                Image(systemName: "arrow.right").imageScale(.small).foregroundStyle(.tertiary)
                                Text(Format.duration(item.last)).fontWeight(.semibold)
                            }
                            .monospacedDigit()
                        } label: {
                            Text(item.recipe.title).lineLimit(2)
                        }
                    }
                } header: {
                    Text("Tu vas plus vite")
                } footer: {
                    Text("Première fois et dernière fois, d'après le chrono du mode cuisson.")
                }
            }

            Section("Au total") {
                let doneMeals = weeks.flatMap(\.slots).filter { $0.status == .done && !$0.isAbsent }
                LabeledContent("Repas faits", value: "\(doneMeals.count)")
                LabeledContent("Recettes différentes", value: "\(Set(doneMeals.compactMap { $0.recipe?.id }).count)")
                LabeledContent("Temps en cuisine", value: sessions.isEmpty ? "—" : Format.duration(sessions.map(\.activeSeconds).reduce(0, +)))
                LabeledContent("Recettes dans la bibliothèque", value: "\(recipes.count)")
            }
            .monospacedDigit()
        }
        .navigationTitle("Statistiques")
        .navigationBarTitleDisplayMode(.inline)
    }
}
