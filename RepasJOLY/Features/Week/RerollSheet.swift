import SwiftData
import SwiftUI

/// Recalcule toute la semaine avec d'autres règles. Les repas verrouillés sont gardés.
struct RerollSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    let week: WeekPlan

    @State private var exclusions = PlanExclusions()
    @State private var useAI = true
    @State private var isPlanning = false
    @State private var warning: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ExclusionsLink(exclusions: $exclusions, recipes: recipes)
                    Toggle(isOn: $useAI) { Label("Planification IA", systemImage: "sparkles") }
                        .disabled(ClaudeClient.configured == nil)
                } footer: {
                    let locked = week.slots.filter { $0.isLocked && $0.needsCooking }.count
                    Text(locked == 0
                         ? "Tous les repas à cuisiner seront redistribués. Verrouille un repas depuis son menu pour le garder."
                         : "\(locked) repas verrouillé\(locked > 1 ? "s" : "") ser\(locked > 1 ? "ont" : "a") gardé\(locked > 1 ? "s" : "").")
                }
            }
            .navigationTitle("Relancer la semaine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isPlanning {
                        ProgressView()
                    } else {
                        Button("Relancer", systemImage: "shuffle") { Task { await reroll() } }
                    }
                }
            }
            .alert("Planification", isPresented: Binding(get: { warning != nil }, set: { if !$0 { warning = nil; dismiss() } })) {
                Button("OK") {}
            } message: {
                Text(warning ?? "")
            }
            .onAppear {
                exclusions = PlanExclusions(categories: Set(week.excludedCategories), recipeIDs: Set(week.excludedRecipeIDs))
                useAI = week.usedAI && ClaudeClient.configured != nil
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func reroll() async {
        isPlanning = true
        week.excludedCategories = Array(exclusions.categories)
        week.excludedRecipeIDs = Array(exclusions.recipeIDs)
        warning = await WeekPlanner(context: context).fill(week, recipes: recipes, useAI: useAI)
        isPlanning = false
        if warning == nil { dismiss() }
    }
}

struct RecipePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    let title: String
    let onPick: (Recipe) -> Void
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List(filtered) { recipe in
                Button {
                    onPick(recipe)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        RecipeThumbnail(recipe: recipe, size: 40)
                        VStack(alignment: .leading) {
                            Text(recipe.title).foregroundStyle(.primary)
                            Text("\(recipe.category.label) · \(Format.minutes(recipe.estimatedMinutes))")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Rechercher")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    private var filtered: [Recipe] {
        search.isEmpty ? recipes : recipes.filter { $0.title.localizedStandardContains(search) }
    }
}
