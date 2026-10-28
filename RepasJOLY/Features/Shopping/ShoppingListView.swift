import SwiftData
import SwiftUI

struct ShoppingListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WeekPlan.weekStart, order: .reverse) private var weeks: [WeekPlan]
    @Query private var marks: [ShoppingMark]
    @Query private var plans: [ShoppingPlan]
    @Query(sort: \ManualShoppingItem.createdAt) private var manualItems: [ManualShoppingItem]
    @Query private var stock: [StockItem]

    @State private var newItem = ""
    @State private var showStock = false
    @State private var isConsolidating = false
    @State private var aiError: String?
    @State private var selected: ShoppingNeed?
    @AppStorage("shoppingByMeal") private var byMeal = false
    @FocusState private var addFocused: Bool

    private let weekStart = WeekCalendar.monday(of: .now)

    private var week: WeekPlan? { weeks.first { $0.weekStart == weekStart } }
    private var sources: [ShoppingSource] { week?.shoppingSources ?? [] }
    private var fingerprint: String { ShoppingPlanner.fingerprint(sources) }
    private var plan: ShoppingPlan? { plans.first { $0.weekStart == weekStart } }

    /// Liste regroupée par l'IA si elle correspond aux repas actuels, sinon regroupement local.
    private var items: [ConsolidatedItem] {
        if let plan, plan.fingerprint == fingerprint { return plan.items }
        return ShoppingPlanner.localItems(sources)
    }

    private var needs: [ShoppingNeed] {
        let have = Dictionary(items.map { ($0.key, haveAmount(for: $0)) }, uniquingKeysWith: { first, _ in first })
        return ShoppingPlanner.needs(items, sources: sources, have: have)
    }

    private var extras: [ManualShoppingItem] { manualItems.filter { $0.weekStart == weekStart } }

    var body: some View {
        let needs = needs
        let toBuy = needs.filter { !isChecked($0) }
        let inCart = needs.filter { isChecked($0) }
        let openExtras = extras.filter { !$0.isChecked }
        let doneExtras = extras.filter(\.isChecked)

        NavigationStack {
            Group {
                if byMeal {
                    MealIngredientsList(week: week, stock: stock)
                } else {
                    shoppingList(needs: needs, toBuy: toBuy, inCart: inCart, openExtras: openExtras, doneExtras: doneExtras)
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Affichage", selection: $byMeal) {
                    Text("Par rayon").tag(false)
                    Text("Par repas").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
            .navigationTitle("Courses")
            .navigationSubtitle(subtitle(toBuy: toBuy.count + openExtras.count))
            .sheet(isPresented: $showStock) { StockView() }
            .sheet(item: $selected) { need in
                ShoppingItemSheet(need: need, isChecked: isChecked(need), setHave: { setHave($0, for: need) }, toggle: { toggle(need) })
            }
            .toolbar { toolbar }
            .task(id: fingerprint) { await consolidate(force: false) }
        }
    }

    private func shoppingList(needs: [ShoppingNeed], toBuy: [ShoppingNeed], inCart: [ShoppingNeed],
                              openExtras: [ManualShoppingItem], doneExtras: [ManualShoppingItem]) -> some View {
            List {
                Section {
                    TextField("Ajouter un article", text: $newItem)
                        .focused($addFocused)
                        .submitLabel(.done)
                        .onSubmit(addItem)
                    ForEach(openExtras) { item in
                        ExtraRow(item: item)
                    }
                    .onDelete { offsets in offsets.map { openExtras[$0] }.forEach(context.delete) }
                } footer: {
                    if isConsolidating {
                        Label("Claude regroupe ta liste…", systemImage: "sparkles")
                    } else if let aiError {
                        Text("Regroupement IA indisponible, liste simple affichée. \(aiError)")
                    }
                }

                ForEach(Aisle.allCases) { aisle in
                    let lines = toBuy.filter { $0.item.aisle == aisle }
                    if !lines.isEmpty {
                        Section(aisle.label) {
                            ForEach(lines) { need in row(need) }
                        }
                    }
                }

                if !inCart.isEmpty || !doneExtras.isEmpty {
                    Section("J'ai") {
                        ForEach(inCart) { need in row(need) }
                        ForEach(doneExtras) { item in ExtraRow(item: item) }
                    }
                }
            }
            .animation(.snappy, value: marks.map(\.isChecked))
            .animation(.snappy, value: extras.map(\.isChecked))
            .animation(.snappy, value: isConsolidating)
            .overlay { emptyState(isEmpty: needs.isEmpty && extras.isEmpty) }
    }

    private func row(_ need: ShoppingNeed) -> some View {
        NeedRow(need: need, isChecked: isChecked(need), atHomeLabel: atHomeLabel(need)) {
            toggle(need)
        } open: {
            selected = need
        }
    }

    @ViewBuilder
    private func emptyState(isEmpty: Bool) -> some View {
        if week == nil {
            ContentUnavailableView("Pas de planning", systemImage: "cart",
                                   description: Text("Prépare ta semaine dans l'onglet Semaine pour obtenir la liste."))
        } else if isEmpty && !addFocused {
            ContentUnavailableView("Rien à acheter", systemImage: "cart",
                                   description: Text("Tous les repas de la semaine sont faits ou sautés."))
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Frigo", systemImage: "refrigerator") { showStock = true }
                .badge(stock.count)
        }
        ToolbarItem(placement: .topBarTrailing) {
            ShareLink(item: shareText) { Label("Partager", systemImage: "square.and.arrow.up") }
                .disabled(needs.isEmpty && extras.isEmpty)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu("Plus", systemImage: "ellipsis") {
                Button("Regrouper à nouveau avec l'IA", systemImage: "sparkles") { Task { await consolidate(force: true) } }
                    .disabled(ClaudeClient.configured == nil || sources.isEmpty || isConsolidating)
                Button("Tout décocher", systemImage: "circle") { resetChecks() }
                Button("Retirer les ajouts cochés", systemImage: "trash") {
                    extras.filter(\.isChecked).forEach(context.delete)
                }
            }
        }
    }

    private func subtitle(toBuy: Int) -> String {
        guard let week else { return "" }
        let meals = week.slots.filter { $0.needsCooking && $0.status == .planned && $0.recipe != nil }.count
        return "\(toBuy) à acheter · \(meals) repas restants"
    }

    // MARK: État des lignes

    private func mark(for key: String) -> ShoppingMark? {
        marks.first { $0.key == key && $0.weekStart == weekStart }
    }

    private func stockMatch(for item: ConsolidatedItem) -> StockItem? {
        stock.first { StockMatcher.matches(item.name, stock: StockMatcher.keys([$0.name])) }
    }

    /// Ce qui est déjà à la maison : saisi sur la ligne, sinon la quantité du frigo si l'unité correspond.
    private func haveAmount(for item: ConsolidatedItem) -> Double {
        if let have = mark(for: item.key)?.have, have > 0 { return have }
        guard let match = stockMatch(for: item), match.amount > 0, match.unit == item.unit || (match.unit == "pièce" && item.unit.isEmpty)
        else { return 0 }
        return match.amount
    }

    /// J'ai ou je n'ai pas : coché à la main, couvert par « J'en ai déjà », ou présent au frigo sans quantité.
    private func isChecked(_ need: ShoppingNeed) -> Bool {
        if let mark = mark(for: need.id) { return mark.isChecked }
        if need.isCoveredAtHome { return true }
        if let match = stockMatch(for: need.item), match.amount == 0 { return true }
        return false
    }

    private func atHomeLabel(_ need: ShoppingNeed) -> String? {
        if need.isCoveredAtHome { return "Déjà à la maison" }
        if need.have > 0 {
            return "\(ShoppingPlanner.format(need.needed, unit: need.item.unit)) au total, \(ShoppingPlanner.format(need.have, unit: need.item.unit)) à la maison"
        }
        if let match = stockMatch(for: need.item), match.amount == 0 { return "Au frigo" }
        return nil
    }

    private func editMark(_ key: String, _ change: (ShoppingMark) -> Void, defaultChecked: Bool) {
        if let mark = mark(for: key) {
            change(mark)
        } else {
            let mark = ShoppingMark(key: key, weekStart: weekStart, isChecked: defaultChecked)
            context.insert(mark)
            change(mark)
        }
    }

    private func toggle(_ need: ShoppingNeed) {
        let current = isChecked(need)
        editMark(need.id, { $0.isChecked = !current }, defaultChecked: current)
    }

    private func setHave(_ value: Double, for need: ShoppingNeed) {
        let current = isChecked(need)
        editMark(need.id, { mark in
            mark.have = max(0, value)
            mark.isChecked = need.needed > 0 && value >= need.needed
        }, defaultChecked: current)
    }

    private func resetChecks() {
        marks.filter { $0.weekStart == weekStart }.forEach { $0.isChecked = false; $0.have = 0 }
        extras.forEach { $0.isChecked = false }
    }

    private func addItem() {
        let name = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        withAnimation(.snappy) { context.insert(ManualShoppingItem(name: ShoppingListBuilder.displayName(name), weekStart: weekStart)) }
        newItem = ""
        addFocused = true
    }

    // MARK: IA

    /// Regroupe la liste avec Claude une fois par planning ; rien n'est relancé tant que les repas ne changent pas.
    private func consolidate(force: Bool) async {
        guard ClaudeClient.configured != nil, !sources.isEmpty, !isConsolidating else { return }
        let current = sources
        let currentFingerprint = ShoppingPlanner.fingerprint(current)
        guard force || plan?.fingerprint != currentFingerprint else { return }
        isConsolidating = true
        aiError = nil
        do {
            let items = try await AIService(context: context).consolidateShopping(current)
            plans.filter { $0.weekStart == weekStart }.forEach(context.delete)
            context.insert(ShoppingPlan(weekStart: weekStart, fingerprint: currentFingerprint, items: items, usedAI: true))
            try? context.save()
        } catch {
            aiError = error.localizedDescription
        }
        isConsolidating = false
    }

    // MARK: Partage

    private var shareText: String {
        var lines = ["Courses · semaine \(WeekCalendar.weekNumber(of: weekStart))"]
        let open = needs.filter { !isChecked($0) }
        for aisle in Aisle.allCases {
            let items = open.filter { $0.item.aisle == aisle }
            guard !items.isEmpty else { continue }
            lines.append("\n\(aisle.label)")
            lines += items.map { need in "– \(need.item.name)\(need.quantityText.map { " : \($0)" } ?? "")" }
        }
        let others = extras.filter { !$0.isChecked }
        if !others.isEmpty {
            lines.append("\nAutres")
            lines += others.map { "– \($0.name)" }
        }
        return lines.joined(separator: "\n")
    }
}

extension WeekPlan {
    /// Chaque ingrédient de chaque repas à cuisiner de la semaine (les restes ne demandent rien).
    var shoppingSources: [ShoppingSource] {
        orderedSlots.filter(\.needsCooking).flatMap { slot -> [ShoppingSource] in
            guard let recipe = slot.recipe else { return [] }
            let meal = "\(WeekCalendar.dayName(slot.day)) \(slot.meal.label.lowercased())"
            return recipe.ingredients.enumerated().map { index, ingredient in
                ShoppingSource(ref: "\(slot.id.uuidString)-\(index)", recipeTitle: recipe.title, mealLabel: meal,
                               ingredient: ingredient, isRemaining: slot.status == .planned)
            }
        }
    }
}

private struct NeedRow: View {
    let need: ShoppingNeed
    let isChecked: Bool
    let atHomeLabel: String?
    let toggle: () -> Void
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isChecked ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 32, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: isChecked)
            .accessibilityLabel(isChecked ? "Décocher \(need.item.name)" : "Cocher \(need.item.name)")

            Button(action: open) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(need.item.name)
                            .foregroundStyle(isChecked ? .secondary : .primary)
                            .strikethrough(isChecked, color: .secondary)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    if let quantity = need.quantityText {
                        Text(quantity)
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(isChecked ? .secondary : .primary)
                            .contentTransition(.numericText())
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Voir le détail")
        }
    }

    private var subtitle: String {
        [atHomeLabel, need.recipes.joined(separator: " · ")].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
    }
}

private struct ExtraRow: View {
    @Bindable var item: ManualShoppingItem

    var body: some View {
        Button {
            item.isChecked.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 32, height: 44)
                Text(item.name)
                    .foregroundStyle(item.isChecked ? .secondary : .primary)
                    .strikethrough(item.isChecked, color: .secondary)
                Spacer()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: item.isChecked)
    }
}

/// Tous les repas restants de la semaine avec leurs ingrédients, pour vérifier d'un coup d'œil qu'on a tout.
private struct MealIngredientsList: View {
    let week: WeekPlan?
    let stock: [StockItem]

    private var meals: [MealSlot] {
        week?.orderedSlots.filter { $0.needsCooking && $0.status == .planned && $0.recipe != nil } ?? []
    }

    var body: some View {
        let stockKeys = StockMatcher.keys(stock.map(\.name))
        List {
            ForEach(meals) { slot in
                if let recipe = slot.recipe {
                    Section {
                        ForEach(recipe.ingredients) { ingredient in
                            LabeledContent {
                                Text([ingredient.grams > 0 ? "\(Int(ingredient.grams)) g" : nil,
                                      ingredient.detail.isEmpty ? nil : ingredient.detail].compactMap { $0 }.joined(separator: " · "))
                                    .monospacedDigit()
                            } label: {
                                Text(ingredient.name)
                                if StockMatcher.matches(ingredient.name, stock: stockKeys) {
                                    Text("Au frigo")
                                }
                            }
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(WeekCalendar.dayName(slot.day)) \(slot.meal.label.lowercased())")
                            Text(recipe.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                        .textCase(nil)
                    }
                }
            }
        }
        .overlay {
            if meals.isEmpty {
                ContentUnavailableView("Aucun repas restant", systemImage: "fork.knife",
                                       description: Text("Les repas faits, sautés ou mangés dehors n'apparaissent pas."))
            }
        }
    }
}
