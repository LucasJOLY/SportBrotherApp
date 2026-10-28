import SwiftData
import SwiftUI

/// « Même chose mais… » : Claude décline une recette existante en une nouvelle.
struct VariantSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe

    @State private var request = ""
    @State private var isWorking = false
    @State private var error: String?
    @State private var route: DraftRoute?

    private let shortcuts = ["Version airfryer", "Avec du bœuf", "Avec du poisson", "Plus épicée", "Plus rapide", "Autre sauce"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FlowLayout {
                        ForEach(shortcuts, id: \.self) { shortcut in
                            ChipToggle(title: shortcut, isOn: request == shortcut) {
                                request = request == shortcut ? "" : shortcut
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    TextField("Ou décris ta variante", text: $request, axis: .vertical)
                } header: {
                    Text("Que veux-tu changer ?")
                } footer: {
                    Text("La variante est enregistrée comme une nouvelle recette ; l'originale ne change pas.")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Variante")
            .navigationSubtitle(recipe.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button("Créer", systemImage: "sparkles") { Task { await create() } }
                            .disabled(request.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationDestination(item: $route) { route in
                RecipeEditorView(form: route.form, recipe: nil, onSaved: { dismiss() })
            }
            .interactiveDismissDisabled(isWorking)
        }
    }

    private func create() async {
        isWorking = true
        error = nil
        do {
            let draft = try await AIService(context: context).variant(of: recipe, request: request)
            route = DraftRoute(form: RecipeForm(draft: draft, source: .ai, rawInput: "Variante de \(recipe.title) : \(request)"))
        } catch {
            self.error = error.localizedDescription
        }
        isWorking = false
    }
}
