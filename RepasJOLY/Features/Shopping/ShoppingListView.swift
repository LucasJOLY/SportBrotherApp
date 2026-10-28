import SwiftData
import SwiftUI

struct ShoppingListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WeekPlan.weekStart, order: .reverse) private var weeks: [WeekPlan]
    @Query private var marks: [ShoppingMark]
    @Query(sort: \ManualShoppingItem.createdAt) private var manualItems: [ManualShoppingItem]
    @Query private var stock: [StockItem]
    @State private var showStock = false
    @State private var newItem = ""
    @FocusState private var addFocused: Bool

    private let weekStart = WeekCalendar.monday(of: .now)

    private var week: WeekPlan? { weeks.first { $0.weekStart == weekStart } }

    /// Repas encore à cuisiner : les repas faits, sautés ou les restes ne demandent rien à acheter.
    private var remainingMeals: [MealSlot] {
        week?.orderedSlots.filter { $0.needsCooking && $0.status == .planned && $0.recipe != nil } ?? []
    }

    private var sections: [ShoppingSection] {
        ShoppingListBuilder.build(meals: remainingMeals.compactMap { $0.recipe?.ingredients })
    }

    private var extras: [ManualShoppingItem] {
        manualItems.filter { $0.weekStart == weekStart }.sorted { !$0.isChecked && $1.isChecked }
    }

    private func mark(for line: ShoppingLine) -> ShoppingMark? {
        marks.first { $0.key == line.key && $0.weekStart == weekStart }
    }

    private var stockKeys: Set<String> { StockMatcher.keys(stock.map(\.name)) }

    private func isAtHome(_ line: ShoppingLine) -> Bool {
        StockMatcher.matches(line.name, stock: stockKeys)
    }

    /// Par défaut, les basiques du placard et ce qui est au frigo sont cochés « en stock ».
    private func isChecked(_ line: ShoppingLine) -> Bool {
        mark(for: line)?.isChecked ?? (line.isPantry || isAtHome(line))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Ajouter un article", text: $newItem)
                        .focused($addFocused)
                        .submitLabel(.done)
                        .onSubmit(addItem)
                    ForEach(extras) { item in
                        CheckRow(title: item.name, quantity: nil, details: nil, isChecked: item.isChecked) {
                            item.isChecked.toggle()
                        }
                    }
                    .onDelete { offsets in offsets.map { extras[$0] }.forEach(context.delete) }
                }

                ForEach(sections) { section in
                    Section(section.aisle.label) {
                        let lines = section.lines.sorted { !isChecked($0) && isChecked($1) }
                        ForEach(lines) { line in
                            CheckRow(
                                title: line.name,
                                quantity: line.quantityText,
                                details: details(for: line),
                                isChecked: isChecked(line)
                            ) { toggle(line) }
                        }
                    }
                }
            }
            .animation(.snappy, value: marks.map(\.isChecked))
            .animation(.snappy, value: extras.map(\.isChecked))
            .overlay {
                if week == nil || (sections.isEmpty && extras.isEmpty && !addFocused) {
                    ContentUnavailableView(
                        week == nil ? "Pas de planning" : "Rien à acheter",
                        systemImage: "cart",
                        description: Text(week == nil
                                          ? "Prépare ta semaine dans l'onglet Semaine pour obtenir la liste."
                                          : "Tous les repas de la semaine sont faits ou sautés.")
                    )
                }
            }
            .navigationTitle("Courses")
            .navigationSubtitle(subtitle)
            .sheet(isPresented: $showStock) { StockView() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Frigo", systemImage: "refrigerator") { showStock = true }
                        .badge(stock.count)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: shareText) { Label("Partager", systemImage: "square.and.arrow.up") }
                        .disabled(sections.isEmpty && extras.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Plus", systemImage: "ellipsis") {
                        Button("Tout décocher", systemImage: "circle") { resetChecks() }
                        Button("Retirer les ajouts cochés", systemImage: "trash") {
                            extras.filter(\.isChecked).forEach(context.delete)
                        }
                    }
                }
            }
        }
    }

    private var subtitle: String {
        let toBuy = sections.flatMap(\.lines).filter { !isChecked($0) }.count + extras.filter { !$0.isChecked }.count
        guard week != nil else { return "" }
        return "\(remainingMeals.count) repas restants · \(toBuy) à acheter"
    }

    private func details(for line: ShoppingLine) -> String? {
        var parts = line.details
        if isAtHome(line) {
            parts.insert(isChecked(line) ? "Déjà à la maison" : "À la maison, à racheter", at: 0)
        } else if line.isPantry {
            parts.insert(isChecked(line) ? "Placard, en stock" : "Placard, à racheter", at: 0)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func toggle(_ line: ShoppingLine) {
        if let mark = mark(for: line) {
            mark.isChecked.toggle()
        } else {
            context.insert(ShoppingMark(key: line.key, weekStart: weekStart, isChecked: !isChecked(line)))
        }
    }

    private func resetChecks() {
        for line in sections.flatMap(\.lines) {
            if let mark = mark(for: line) { context.delete(mark) }
        }
        extras.forEach { $0.isChecked = false }
    }

    private func addItem() {
        let name = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        withAnimation(.snappy) { context.insert(ManualShoppingItem(name: ShoppingListBuilder.displayName(name), weekStart: weekStart)) }
        newItem = ""
        addFocused = true
    }

    private var shareText: String {
        var lines = ["Courses · semaine \(WeekCalendar.weekNumber(of: weekStart))"]
        for section in sections {
            let items = section.lines.filter { !isChecked($0) }
            guard !items.isEmpty else { continue }
            lines.append("\n\(section.aisle.label)")
            lines += items.map { "– \($0.name)\($0.quantityText.map { " (\($0))" } ?? "")" }
        }
        let open = extras.filter { !$0.isChecked }
        if !open.isEmpty {
            lines.append("\nAutres")
            lines += open.map { "– \($0.name)" }
        }
        return lines.joined(separator: "\n")
    }
}

private struct CheckRow: View {
    let title: String
    let quantity: String?
    let details: String?
    let isChecked: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isChecked ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(isChecked ? .secondary : .primary)
                        .strikethrough(isChecked, color: .secondary)
                    if let details {
                        Text(details).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let quantity {
                    Text(quantity)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isChecked)
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }
}
