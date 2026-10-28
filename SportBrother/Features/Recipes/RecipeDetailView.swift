import SwiftData
import SwiftUI

struct RecipeDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(CookingLauncher.self) private var launcher
    @Bindable var recipe: Recipe

    @State private var isEditing = false
    @State private var confirmDelete = false
    @State private var showVariant = false
    @State private var servings = QuantityScaler.baseServings

    var body: some View {
        List {
            header
            ingredients
            steps
            if !recipe.tip.isEmpty {
                Section("Astuce du chef") {
                    Label(recipe.tip, systemImage: "lightbulb")
                }
            }
            Section("Ton avis") {
                RatingControl(rating: $recipe.rating)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !recipe.finishedSessions.isEmpty {
                    LabeledContent("Cuisinée", value: "\(recipe.finishedSessions.count) fois")
                    if let average = recipe.averageCookingSeconds {
                        LabeledContent("Temps réel moyen", value: Format.duration(average))
                    }
                }
            }
            .monospacedDigit()
        }
        .animation(.snappy, value: servings)
        .listSectionSpacing(.compact)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                launcher.start(recipe, slot: todaySlot, servings: servings, context: context)
            } label: {
                Label("Cuisiner", systemImage: "flame.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .disabled(recipe.steps.isEmpty)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(recipe.isFavorite ? "Retirer des favoris" : "Ajouter aux favoris",
                       systemImage: recipe.isFavorite ? "heart.fill" : "heart") {
                    recipe.isFavorite.toggle()
                }
                .symbolEffect(.bounce, value: recipe.isFavorite)
                .sensoryFeedback(.impact(weight: .light), trigger: recipe.isFavorite)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Plus", systemImage: "ellipsis") {
                    Button("Faire une variante", systemImage: "sparkles") { showVariant = true }
                    Button("Modifier", systemImage: "pencil") { isEditing = true }
                    Button("Supprimer", systemImage: "trash", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack { RecipeEditorView(form: RecipeForm(recipe: recipe), recipe: recipe) }
        }
        .sheet(isPresented: $showVariant) { VariantSheet(recipe: recipe) }
        .confirmationDialog("Supprimer cette recette ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                context.delete(recipe)
                dismiss()
            }
        }
    }

    /// Durée, four et catégorie sur une ligne de texte : les symboles intégrés au texte restent sur la ligne de base.
    private var metaLine: Text {
        var items: [(symbol: String, text: String)] = [("clock", Format.minutes(recipe.estimatedMinutes))]
        if let average = recipe.averageCookingSeconds {
            items.append(("stopwatch", "réel \(Format.duration(average))"))
        }
        if recipe.ovenTemperature > 0 {
            items.append(("oven", "\(recipe.ovenTemperature) °C"))
        }
        items.append((recipe.category.symbol, recipe.category.label))
        return items.enumerated().reduce(Text("")) { line, item in
            let separator = item.offset == 0 ? Text("") : Text("    ")
            return Text("\(line)\(separator)\(Image(systemName: item.element.symbol))\u{00A0}\(item.element.text.replacingOccurrences(of: " ", with: "\u{00A0}"))")
        }
    }

    /// Si la recette est prévue aujourd'hui, la cuisson cochera ce repas.
    private var todaySlot: MealSlot? {
        let today = WeekCalendar.dayIndex(of: .now)
        let monday = WeekCalendar.monday(of: .now)
        return recipe.slots.first {
            $0.week?.weekStart == monday && $0.day == today && $0.needsCooking && $0.status == .planned
        }
    }

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                if let data = recipe.photo, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: 22, style: .continuous))
                        .accessibilityHidden(true)
                }
                Text(recipe.title)
                    .font(.display(.title2))
                    .fixedSize(horizontal: false, vertical: true)
                if !recipe.summary.isEmpty {
                    Text(recipe.summary)
                        .foregroundStyle(.secondary)
                }
                metaLine
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var ingredients: some View {
        Section {
            Picker("Portions", selection: $servings) {
                Text("1 personne").tag(1)
                Text("2 personnes").tag(2)
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .sensoryFeedback(.selection, trigger: servings)
        }
        if recipe.hasMacros {
            Section("Par personne") {
                HStack {
                    macro("\(recipe.kcal)", "kcal")
                    macro("\(recipe.protein) g", "protéines")
                    macro("\(recipe.carbs) g", "glucides")
                    macro("\(recipe.fat) g", "lipides")
                }
                .padding(.vertical, 4)
            }
        }
        ForEach(recipe.ingredientGroups, id: \.name) { group in
            Section(group.name.isEmpty ? "Ingrédients" : group.name) {
                ForEach(group.items.map { $0.scaled(forServings: servings) }) { ingredient in
                    LabeledContent {
                        Text(quantity(ingredient))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    } label: {
                        Text(ingredient.name)
                        if ingredient.isPantry {
                            Text("Placard")
                        }
                    }
                }
            }
        }
    }

    private func macro(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func quantity(_ ingredient: Ingredient) -> String {
        [ingredient.grams > 0 ? "\(Int(ingredient.grams)) g" : nil, ingredient.detail.isEmpty ? nil : ingredient.detail]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var steps: some View {
        Section("Étapes") {
            ForEach(Array(recipe.steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                        .frame(minWidth: 20, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        if !step.title.isEmpty {
                            Text(step.title).font(.headline)
                        }
                        Text(step.text)
                        if step.durationMinutes > 0 {
                            Label(step.isPassive ? "\(Format.minutes(step.durationMinutes)), tourne tout seul" : Format.minutes(step.durationMinutes),
                                  systemImage: "timer")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        if !step.parallelHint.isEmpty {
                            Label(step.parallelHint, systemImage: "arrow.triangle.branch")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

