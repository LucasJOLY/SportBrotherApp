import SwiftData
import SwiftUI

/// Préparation de la semaine : qui mange quand, où vont les restes, puis répartition.
struct WeekSetupView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Recipe.title) private var recipes: [Recipe]

    @State private var diners: [Int] = Array(repeating: 2, count: 14)
    /// Créneau source → créneau qui reçoit le reste.
    @State private var leftovers: [Int: Int] = [:]
    @State private var useAI = true
    @State private var exclusions = PlanExclusions()
    @State private var isPlanning = false
    @State private var warning: String?

    private let weekStart = WeekCalendar.monday(of: .now)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DinersGrid(diners: $diners)
                } header: {
                    Text("Qui mange quand ?")
                } footer: {
                    Text("Touche une case : à deux, seul, absent. Seul, tu cuisines pour 2 et le reste sert à un autre repas.")
                }

                if !leftoverSources.isEmpty {
                    Section("Restes") {
                        ForEach(leftoverSources, id: \.self) { source in
                            leftoverPicker(for: source)
                        }
                    }
                }

                Section {
                    Toggle(isOn: $useAI) {
                        Label("Planification IA", systemImage: "sparkles")
                    }
                    .disabled(ClaudeClient.configured == nil)
                    ExclusionsLink(exclusions: $exclusions, recipes: recipes)
                } footer: {
                    Text(useAI
                         ? "Claude choisit les recettes pour équilibrer la semaine. Un seul appel, quelques centimes au plus."
                         : "Répartition locale au hasard, en variant les protéines et en favorisant tes recettes préférées.")
                }
            }
            .navigationTitle("Préparer la semaine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isPlanning {
                        ProgressView()
                    } else {
                        Button("Répartir", systemImage: "checkmark") { Task { await plan() } }
                            .disabled(recipes.isEmpty || diners.allSatisfy { $0 == 0 })
                    }
                }
            }
            .alert("Planification", isPresented: Binding(get: { warning != nil }, set: { if !$0 { warning = nil; dismiss() } })) {
                Button("OK") {}
            } message: {
                Text(warning ?? "")
            }
            .interactiveDismissDisabled(isPlanning)
            .onAppear(perform: load)
            .onChange(of: diners) { suggestLeftovers() }
        }
    }

    private var slotsInfo: [LeftoverSlot] {
        diners.indices.map { order in
            LeftoverSlot(order: order, diners: diners[order],
                         isLeftover: leftovers.values.contains(order),
                         sendsLeftover: leftovers[order] != nil)
        }
    }

    private var leftoverSources: [Int] {
        diners.indices.filter { diners[$0] == 1 && !leftovers.values.contains($0) }
    }

    private func leftoverPicker(for source: Int) -> some View {
        let info = slotsInfo
        let free = info.map { LeftoverSlot(order: $0.order, diners: $0.diners,
                                           isLeftover: $0.isLeftover && $0.order != leftovers[source],
                                           sendsLeftover: $0.sendsLeftover) }
        let candidates = LeftoverRules.candidates(for: LeftoverSlot(order: source, diners: 1, isLeftover: false, sendsLeftover: false), in: free)
        return Picker(selection: Binding(
            get: { leftovers[source] },
            set: { leftovers[source] = $0 }
        )) {
            Text("Aucun").tag(Int?.none)
            ForEach(candidates, id: \.self) { Text(label(for: $0)).tag(Optional($0)) }
        } label: {
            Text(label(for: source))
        }
    }

    private func label(for order: Int) -> String {
        "\(WeekCalendar.dayName(order / 2)) \(order.isMultiple(of: 2) ? "midi" : "soir")"
    }

    private func load() {
        let profile = context.profile()
        if profile.lastDinersTemplate.count == 14 { diners = profile.lastDinersTemplate }
        useAI = profile.aiPlanningByDefault && ClaudeClient.configured != nil
        suggestLeftovers()
    }

    private func suggestLeftovers() {
        let info = diners.indices.map { LeftoverSlot(order: $0, diners: diners[$0], isLeftover: false, sendsLeftover: false) }
        leftovers = Dictionary(uniqueKeysWithValues: LeftoverRules.suggestedPairs(in: info).map { ($0.source, $0.target) })
    }

    private func plan() async {
        isPlanning = true
        let planner = WeekPlanner(context: context)
        let week = planner.createWeek(start: weekStart, diners: diners,
                                      leftovers: leftovers.map { (source: $0.key, target: $0.value) })
        week.excludedCategories = Array(exclusions.categories)
        week.excludedRecipeIDs = Array(exclusions.recipeIDs)
        warning = await planner.fill(week, recipes: recipes, useAI: useAI)
        isPlanning = false
        if warning == nil { dismiss() }
    }
}

/// Grille 7 jours × midi/soir. Un toucher fait défiler 2 → 1 → absent.
private struct DinersGrid: View {
    @Binding var diners: [Int]

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Text("Midi").gridColumnAlignment(.center)
                Text("Soir")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(0..<7, id: \.self) { day in
                GridRow {
                    Text(WeekCalendar.dayName(day))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    cell(day * 2)
                    cell(day * 2 + 1)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func cell(_ order: Int) -> some View {
        let value = diners[order]
        return Button {
            withAnimation(.snappy(duration: 0.2)) { diners[order] = value == 2 ? 1 : value == 1 ? 0 : 2 }
        } label: {
            Label(value == 0 ? "Absent" : value == 1 ? "Seul" : "À deux",
                  systemImage: value == 0 ? "minus" : value == 1 ? "person.fill" : "person.2.fill")
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 76, height: 40)
                .foregroundStyle(value == 0 ? AnyShapeStyle(.tertiary) : value == 2 ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                .background(value == 2 ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityLabel("\(WeekCalendar.dayName(order / 2)) \(order.isMultiple(of: 2) ? "midi" : "soir")")
        .accessibilityValue(value == 0 ? "absent" : value == 1 ? "seul" : "à deux")
    }
}

struct PlanExclusions: Equatable {
    var categories: Set<RecipeCategory> = []
    var recipeIDs: Set<UUID> = []

    var count: Int { categories.count + recipeIDs.count }
}

struct ExclusionsLink: View {
    @Binding var exclusions: PlanExclusions
    let recipes: [Recipe]

    var body: some View {
        NavigationLink {
            ExclusionsView(exclusions: $exclusions, recipes: recipes)
        } label: {
            LabeledContent {
                Text(exclusions.count == 0 ? "Aucune" : "\(exclusions.count)")
            } label: {
                Label("Exclure cette semaine", systemImage: "nosign")
            }
        }
    }
}

private struct ExclusionsView: View {
    @Binding var exclusions: PlanExclusions
    let recipes: [Recipe]

    var body: some View {
        List {
            Section("Catégories") {
                FlowLayout {
                    ForEach(RecipeCategory.allCases) { category in
                        ChipToggle(title: category.label, symbol: category.symbol,
                                   isOn: exclusions.categories.contains(category)) {
                            exclusions.categories.formSymmetricDifference([category])
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            Section("Recettes") {
                ForEach(recipes) { recipe in
                    Button {
                        exclusions.recipeIDs.formSymmetricDifference([recipe.id])
                    } label: {
                        HStack {
                            Text(recipe.title).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: exclusions.recipeIDs.contains(recipe.id) ? "nosign" : "circle")
                                .foregroundStyle(exclusions.recipeIDs.contains(recipe.id) ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                }
            }
        }
        .navigationTitle("Exclure")
        .navigationBarTitleDisplayMode(.inline)
    }
}
