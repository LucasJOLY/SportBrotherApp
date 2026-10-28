import SwiftData
import SwiftUI

struct WeekView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WeekPlan.weekStart, order: .reverse) private var weeks: [WeekPlan]
    @Query(sort: \Recipe.title) private var recipes: [Recipe]

    @State private var showSetup = false
    @State private var showReroll = false
    @State private var showHistory = false
    @State private var showStats = false
    @State private var pickingRecipeFor: MealSlot?
    @State private var showPastDays = false

    private var week: WeekPlan? {
        let start = WeekCalendar.monday(of: .now)
        return weeks.first { $0.weekStart == start }
    }

    private var today: Int { WeekCalendar.dayIndex(of: .now) }
    private var planner: WeekPlanner { WeekPlanner(context: context) }

    var body: some View {
        NavigationStack {
            Group {
                if let week {
                    plan(week)
                } else {
                    emptyState
                }
            }
            .navigationTitle("Semaine \(WeekCalendar.weekNumber(of: .now))")
            .navigationSubtitle(subtitle)
            .toolbar { toolbar }
            .sheet(isPresented: $showSetup) { WeekSetupView() }
            .sheet(isPresented: $showReroll) {
                if let week { RerollSheet(week: week) }
            }
            .sheet(item: $pickingRecipeFor) { slot in
                RecipePickerSheet(title: "\(WeekCalendar.dayName(slot.day)) \(slot.meal.label.lowercased())") { recipe in
                    planner.assign(recipe, to: slot)
                }
            }
            .navigationDestination(isPresented: $showHistory) { WeekHistoryView() }
            .navigationDestination(isPresented: $showStats) { StatsView() }
            .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
            .navigationDestination(for: WeekPlan.self) { WeekRecapView(week: $0) }
        }
    }

    private var subtitle: String {
        let range = WeekCalendar.rangeLabel(weekStart: WeekCalendar.monday(of: .now))
        guard let week else { return range }
        let cooking = week.slots.filter { !$0.isAbsent }
        let done = cooking.filter { $0.status == .done }.count
        return "\(range) · \(done) sur \(cooking.count) repas faits"
    }

    // MARK: Planning

    private func plan(_ week: WeekPlan) -> some View {
        List {
            if today > 0 {
                Section {
                    DisclosureGroup(isExpanded: $showPastDays) {
                        ForEach(0..<today, id: \.self) { day in
                            Text(WeekCalendar.dayName(day))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            mealRows(day: day, week: week)
                        }
                    } label: {
                        LabeledContent("Jours passés", value: pastSummary(week))
                            .monospacedDigit()
                    }
                }
            }
            ForEach(today..<7, id: \.self) { day in
                Section {
                    mealRows(day: day, week: week)
                } header: {
                    DayHeader(day: day, isToday: day == today, week: week)
                }
            }
        }
        .animation(.snappy, value: showPastDays)
    }

    @ViewBuilder
    private func mealRows(day: Int, week: WeekPlan) -> some View {
        let slots = Meal.allCases.compactMap { week.slot(day: day, meal: $0) }
        if slots.allSatisfy(\.isAbsent) {
            Text("Personne à table")
                .foregroundStyle(.secondary)
        } else {
            ForEach(slots.filter { !$0.isAbsent }) { slot in
                MealRow(slot: slot, week: week, recipes: recipes, pickRecipe: { pickingRecipeFor = $0 })
            }
        }
    }

    private func pastSummary(_ week: WeekPlan) -> String {
        let past = week.slots.filter { $0.day < today && !$0.isAbsent }
        return "\(past.filter { $0.status == .done }.count) sur \(past.count) faits"
    }

    // MARK: Vide

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Pas encore de planning", systemImage: "calendar.badge.plus")
        } description: {
            Text(recipes.isEmpty
                 ? "Ajoute d'abord quelques recettes dans l'onglet Recettes."
                 : "Indique qui mange à chaque repas, l'app répartit tes \(recipes.count) recettes sur la semaine.")
        } actions: {
            Button("Préparer la semaine") { showSetup = true }
                .buttonStyle(.glassProminent)
                .disabled(recipes.isEmpty)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let week {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Relancer", systemImage: "shuffle") { showReroll = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Plus", systemImage: "ellipsis") {
                    NavigationLink(value: week) { Label("Bilan de la semaine", systemImage: "chart.bar") }
                    Button("Statistiques", systemImage: "chart.line.uptrend.xyaxis") { showStats = true }
                    Button("Historique", systemImage: "clock.arrow.circlepath") { showHistory = true }
                    Divider()
                    Button("Refaire la grille", systemImage: "square.grid.2x2") { showSetup = true }
                }
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Plus", systemImage: "ellipsis") {
                    Button("Statistiques", systemImage: "chart.line.uptrend.xyaxis") { showStats = true }
                    Button("Historique", systemImage: "clock.arrow.circlepath") { showHistory = true }
                }
            }
        }
    }
}

/// En-tête de jour : un toucher ouvre les actions rapides (sauter un repas, manger dehors).
private struct DayHeader: View {
    @Environment(\.modelContext) private var context
    let day: Int
    let isToday: Bool
    let week: WeekPlan

    var body: some View {
        let slots = Meal.allCases.compactMap { week.slot(day: day, meal: $0) }.filter { !$0.isAbsent }
        HStack {
            Text(isToday ? "Aujourd'hui" : WeekCalendar.dayName(day))
                .foregroundStyle(isToday ? .primary : .secondary)
            Text(week.date(forDay: day), format: .dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR")))
                .foregroundStyle(.tertiary)
            Spacer()
            if !slots.isEmpty {
                Menu {
                    ForEach(slots) { slot in
                        Section(slot.meal.label) {
                            Button("Sauter", systemImage: "minus.circle") { set(.skipped, slot) }
                            Button("Mangé dehors", systemImage: "fork.knife") { set(.eatenOut, slot) }
                            if slot.status != .planned {
                                Button("Remettre prévu", systemImage: "arrow.uturn.backward") { set(.planned, slot) }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(minWidth: 44, minHeight: 32)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Actions pour \(WeekCalendar.dayName(day))")
            }
        }
        .font(.subheadline.weight(.semibold))
        .textCase(nil)
    }

    private func set(_ status: SlotStatus, _ slot: MealSlot) {
        withAnimation(.snappy) { WeekPlanner(context: context).setStatus(status, for: slot) }
    }
}
