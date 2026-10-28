import SwiftData
import SwiftUI

struct RecipeLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.title) private var recipes: [Recipe]

    @State private var search = ""
    @State private var category: RecipeCategory?
    @State private var favoritesOnly = false
    @State private var sheet: Sheet?
    @State private var pendingDeletion: Recipe?

    private enum Sheet: String, Identifiable {
        case quickEntry, generate, blank
        var id: String { rawValue }
    }

    private var filtered: [Recipe] {
        recipes.filter { recipe in
            (!favoritesOnly || recipe.isFavorite)
                && (category == nil || recipe.category == category)
                && (search.isEmpty
                    || recipe.title.localizedStandardContains(search)
                    || recipe.ingredients.contains { $0.name.localizedStandardContains(search) })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                ForEach(filtered) { recipe in
                    NavigationLink(value: recipe) { RecipeRow(recipe: recipe) }
                        .swipeActions(edge: .leading) {
                            Button(recipe.isFavorite ? "Retirer" : "Favori", systemImage: recipe.isFavorite ? "heart.slash" : "heart") {
                                recipe.isFavorite.toggle()
                            }
                            .tint(.pink)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Supprimer", systemImage: "trash", role: .destructive) { pendingDeletion = recipe }
                        }
                }
                } header: {
                    if !recipes.isEmpty { filters }
                }
            }
            .listSectionSpacing(.compact)
            .animation(.snappy, value: filtered.map(\.id))
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Recette ou ingrédient")
            .overlay { emptyState }
            .navigationTitle("Recettes")
            .navigationSubtitle(recipes.isEmpty ? "" : "\(recipes.count) recette\(recipes.count > 1 ? "s" : "")")
            .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { addMenu }
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .quickEntry: QuickEntryView()
                case .generate: GenerateRecipeView()
                case .blank: NavigationStack { RecipeEditorView(form: RecipeForm(), recipe: nil) }
                }
            }
            .confirmationDialog("Supprimer « \(pendingDeletion?.title ?? "") » ?",
                                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                                titleVisibility: .visible) {
                Button("Supprimer la recette", role: .destructive) {
                    if let pendingDeletion { context.delete(pendingDeletion) }
                }
            } message: {
                Text("Ses statistiques de cuisson seront aussi supprimées.")
            }
        }
    }

    private var addMenu: some View {
        Menu("Ajouter", systemImage: "plus") {
            Button("Saisie rapide", systemImage: "square.and.pencil") { sheet = .quickEntry }
            Button("Importer une photo ou un lien", systemImage: "square.and.arrow.down") { sheet = .quickEntry }
            Button("Créer avec l'IA", systemImage: "sparkles") { sheet = .generate }
            Button("Recette vide", systemImage: "doc") { sheet = .blank }
        }
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ChipToggle(title: "Favoris", symbol: "heart.fill", isOn: favoritesOnly) { favoritesOnly.toggle() }
                ForEach(RecipeCategory.allCases.filter { cat in recipes.contains { $0.category == cat } }) { item in
                    ChipToggle(title: item.label, isOn: category == item) {
                        category = category == item ? nil : item
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollIndicators(.hidden)
        .padding(.horizontal, -32)
        .padding(.bottom, 8)
        .textCase(nil)
    }

    @ViewBuilder
    private var emptyState: some View {
        if recipes.isEmpty {
            ContentUnavailableView {
                Label("Aucune recette", systemImage: "book.closed")
            } description: {
                Text("Écris une recette en vrac, Claude la met au propre. Ou fais-en créer une à partir de ce que tu as.")
            } actions: {
                Button("Saisie rapide") { sheet = .quickEntry }.buttonStyle(.glassProminent)
                Button("Créer avec l'IA") { sheet = .generate }.buttonStyle(.glass)
            }
        } else if filtered.isEmpty {
            ContentUnavailableView.search(text: search)
        }
    }
}

struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 14) {
            RecipeThumbnail(recipe: recipe)
            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text("\(recipe.category.label) · \(Format.minutes(recipe.estimatedMinutes))")
                    if let rating = recipe.rating {
                        Label("\(rating)", systemImage: "star.fill")
                            .labelStyle(.titleAndIcon)
                            .imageScale(.small)
                    }
                    if recipe.isFavorite {
                        Image(systemName: "heart.fill").imageScale(.small).foregroundStyle(.pink)
                            .accessibilityLabel("Favori")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }
}
