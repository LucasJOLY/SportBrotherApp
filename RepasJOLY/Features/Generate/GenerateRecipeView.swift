import SwiftData
import SwiftUI

/// Création guidée : aliments et envie → questions rapides → 3 idées → recette détaillée.
struct GenerateRecipeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var ingredients: [String] = []
    @State private var ingredientField = ""
    @State private var request = ""
    @State private var questions: [TasteQuestion] = []
    @State private var answers: [String: String] = [:]
    @State private var ideas: [RecipeIdea] = []
    @State private var shownIdeas: [String] = []
    @State private var loading: Step?
    @State private var error: String?
    @State private var route: DraftRoute?

    private enum Step { case questions, ideas, detail }

    @Query(sort: \StockItem.addedAt, order: .reverse) private var stock: [StockItem]

    private let defaultSuggestions = ["Poulet", "Dinde", "Bœuf haché", "Saumon", "Thon", "Œufs", "Skyr"]

    /// Ce qu'il y a au frigo d'abord, puis les classiques.
    private var suggestions: [String] {
        var seen: Set<String> = []
        return (stock.map(\.name) + defaultSuggestions).filter { seen.insert(ShoppingListBuilder.normalizedKey($0)).inserted }
    }

    private var service: AIService { AIService(context: context) }

    var body: some View {
        NavigationStack {
            Form {
                ingredientsSection
                Section {
                    TextField("Ex. un plat rapide, au four, un peu épicé", text: $request, axis: .vertical)
                } header: {
                    Text("Une envie ?")
                } footer: {
                    Text("Toujours riche en protéines et équilibré, adapté à ton matériel et sans tes aliments exclus.")
                }

                if questions.isEmpty {
                    actionRow("Continuer", step: .questions) { await loadQuestions() }
                        .disabled(ingredients.isEmpty && request.trimmingCharacters(in: .whitespaces).isEmpty)
                } else {
                    ForEach(questions, id: \.question) { question in
                        questionSection(question)
                    }
                    if ideas.isEmpty {
                        actionRow("Voir 3 idées", step: .ideas) { await loadIdeas() }
                    }
                }

                if !ideas.isEmpty { ideasSection }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                }
            }
            .animation(.snappy, value: questions)
            .animation(.snappy, value: ideas)
            .navigationTitle("Créer avec l'IA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                }
            }
            .navigationDestination(item: $route) { route in
                RecipeEditorView(form: route.form, recipe: nil, onSaved: { dismiss() })
            }
            .overlay {
                if ClaudeClient.configured == nil {
                    ContentUnavailableView("Clé API manquante", systemImage: "key",
                                           description: Text("Renseigne CLAUDE_API_KEY dans Config/Secrets.xcconfig puis réinstalle l'app."))
                        .background(.background)
                }
            }
        }
    }

    // MARK: Sections

    private var ingredientsSection: some View {
        Section("Avec quoi ?") {
            if !ingredients.isEmpty {
                FlowLayout {
                    ForEach(ingredients, id: \.self) { item in
                        ChipToggle(title: item, symbol: "xmark", isOn: true) {
                            withAnimation(.snappy) { ingredients.removeAll { $0 == item } }
                        }
                        .accessibilityHint("Retirer")
                    }
                }
                .padding(.vertical, 4)
            }
            TextField("Ajouter un aliment", text: $ingredientField)
                .submitLabel(.done)
                .onSubmit { add(ingredientField) }
            let remaining = suggestions.filter { !ingredients.contains($0) }
            if !remaining.isEmpty {
                FlowLayout {
                    ForEach(remaining, id: \.self) { item in
                        ChipToggle(title: item, symbol: "plus", isOn: false) { add(item) }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func questionSection(_ question: TasteQuestion) -> some View {
        Section(question.question) {
            FlowLayout {
                ForEach(question.options, id: \.self) { option in
                    ChipToggle(title: option, isOn: answers[question.question] == option) {
                        answers[question.question] = answers[question.question] == option ? nil : option
                        if !ideas.isEmpty { ideas = [] }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var ideasSection: some View {
        Section {
            ForEach(ideas, id: \.title) { idea in
                Button {
                    Task { await loadDetail(idea) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(idea.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                            Text(idea.pitch).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if loading == .detail {
                            ProgressView()
                        } else {
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                }
                .disabled(loading != nil)
            }
            actionRow("Autres idées", step: .ideas, prominent: false) { await loadIdeas() }
        } header: {
            Text("Idées")
        } footer: {
            Text("Touche une idée pour obtenir la recette complète, avec les grammages.")
        }
    }

    private func actionRow(_ title: String, step: Step, prominent: Bool = true, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack {
                Text(title).font(.headline)
                if loading == step { ProgressView().padding(.leading, 4) }
            }
            .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(prominent ? AnyPrimitiveButtonStyle(.glassProminent) : AnyPrimitiveButtonStyle(.glass))
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .disabled(loading != nil)
    }

    // MARK: Actions

    private func add(_ raw: String) {
        let item = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.isEmpty, !ingredients.contains(item) else { return }
        withAnimation(.snappy) { ingredients.append(item) }
        ingredientField = ""
    }

    private func run(_ step: Step, _ work: () async throws -> Void) async {
        loading = step
        error = nil
        do { try await work() } catch { self.error = error.localizedDescription }
        loading = nil
    }

    private func loadQuestions() async {
        await run(.questions) {
            questions = try await service.questions(ingredients: ingredients, request: request)
        }
    }

    private func loadIdeas() async {
        rememberTastes()
        await run(.ideas) {
            ideas = try await service.ideas(ingredients: ingredients, request: request, answers: answers, avoiding: shownIdeas)
            shownIdeas += ideas.map(\.title)
        }
    }

    private func loadDetail(_ idea: RecipeIdea) async {
        await run(.detail) {
            let draft = try await service.detail(of: idea, ingredients: ingredients, request: request, answers: answers)
            route = DraftRoute(form: RecipeForm(draft: draft, source: .ai, rawInput: request))
        }
    }

    /// Les réponses enrichissent le profil de goûts, localement, sans appel IA.
    private func rememberTastes() {
        let profile = context.profile()
        for answer in answers.values where !profile.tasteLikes.contains(answer) {
            profile.tasteLikes.append(answer)
        }
        if profile.tasteLikes.count > 30 { profile.tasteLikes.removeFirst(profile.tasteLikes.count - 30) }
    }
}

/// Permet de choisir le style de bouton à l'exécution.
struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: PrimitiveButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
