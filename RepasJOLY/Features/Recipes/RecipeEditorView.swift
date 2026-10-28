import PhotosUI
import SwiftData
import SwiftUI

/// Copie éditable d'une recette : rien n'est écrit avant « Enregistrer ».
struct RecipeForm {
    var title = ""
    var summary = ""
    var category: RecipeCategory = .autre
    var estimatedMinutes = 30
    var ovenTemperature = 0
    var ingredients: [Ingredient] = []
    var steps: [RecipeStep] = []
    var tip = ""
    var kcal = 0
    var protein = 0
    var carbs = 0
    var fat = 0
    var photo: Data?
    var source: RecipeSource = .manual
    var rawInput = ""

    init() {}

    init(recipe: Recipe) {
        title = recipe.title
        summary = recipe.summary
        category = recipe.category
        estimatedMinutes = recipe.estimatedMinutes
        ovenTemperature = recipe.ovenTemperature
        ingredients = recipe.ingredients
        steps = recipe.steps
        tip = recipe.tip
        (kcal, protein, carbs, fat) = (recipe.kcal, recipe.protein, recipe.carbs, recipe.fat)
        photo = recipe.photo
        source = recipe.source
        rawInput = recipe.rawInput
    }

    init(draft: RecipeDraft, source: RecipeSource, rawInput: String) {
        self.init(recipe: draft.makeRecipe(source: source, rawInput: rawInput))
    }

    var isValid: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    func apply(to recipe: Recipe) {
        recipe.title = title.trimmingCharacters(in: .whitespaces)
        recipe.summary = summary
        recipe.category = category
        recipe.estimatedMinutes = estimatedMinutes
        recipe.ovenTemperature = ovenTemperature
        recipe.ingredients = ingredients.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        recipe.steps = steps.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        recipe.tip = tip.trimmingCharacters(in: .whitespacesAndNewlines)
        (recipe.kcal, recipe.protein, recipe.carbs, recipe.fat) = (kcal, protein, carbs, fat)
        recipe.photo = photo
    }
}

struct RecipeEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State var form: RecipeForm
    /// Recette existante modifiée, ou nil pour une création.
    let recipe: Recipe?
    var onSaved: (() -> Void)?

    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var revisionRequest = ""
    @State private var isRevising = false
    @State private var revisionError: String?
    /// Versions précédentes, pour annuler une retouche.
    @State private var history: [RecipeForm] = []
    @FocusState private var revisionFocused: Bool

    var body: some View {
        Form {
            if ClaudeClient.configured != nil {
                revisionSection
            }

            Section {
                TextField("Nom de la recette", text: $form.title, axis: .vertical)
                    .font(.headline)
                TextField("Résumé (facultatif)", text: $form.summary, axis: .vertical)
                Picker("Catégorie", selection: $form.category) {
                    ForEach(RecipeCategory.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                Stepper(value: $form.estimatedMinutes, in: 5...300, step: 5) {
                    LabeledContent("Temps estimé", value: Format.minutes(form.estimatedMinutes))
                }
                Stepper(value: $form.ovenTemperature, in: 0...280, step: 10) {
                    LabeledContent("Four", value: form.ovenTemperature == 0 ? "Sans four" : "\(form.ovenTemperature) °C")
                }
            }
            .monospacedDigit()

            photoSection
            ingredientsSection
            stepsSection

            Section("Astuce du chef") {
                TextField("Facultatif", text: $form.tip, axis: .vertical)
            }

            Section {
                MacroField(title: "Calories", value: $form.kcal, unit: "kcal")
                MacroField(title: "Protéines", value: $form.protein, unit: "g")
                MacroField(title: "Glucides", value: $form.carbs, unit: "g")
                MacroField(title: "Lipides", value: $form.fat, unit: "g")
            } header: {
                Text("Valeurs par personne")
            } footer: {
                Text("Facultatif. Laisse vide si tu ne les connais pas.")
            }
        }
        .navigationTitle(recipe == nil ? "Nouvelle recette" : "Modifier")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler", systemImage: "xmark") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer", systemImage: "checkmark") { save() }
                    .disabled(!form.isValid)
            }
        }
        .onChange(of: photoItem) {
            Task {
                if let data = try? await photoItem?.loadTransferable(type: Data.self) {
                    form.photo = ImageResizer.jpeg(from: data)
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in form.photo = ImageResizer.jpeg(from: image) }
                .ignoresSafeArea()
        }
    }

    /// Retouche en langage libre : « du skyr au lieu de la crème liquide, sans oignon ».
    private var revisionSection: some View {
        Section {
            TextField("Ex. du skyr au lieu de la crème liquide, sans oignon", text: $revisionRequest, axis: .vertical)
                .focused($revisionFocused)
                .submitLabel(.go)
                .onSubmit { Task { await revise() } }
            HStack {
                Button {
                    Task { await revise() }
                } label: {
                    HStack(spacing: 8) {
                        if isRevising {
                            ProgressView()
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isRevising ? "Retouche en cours…" : "Appliquer")
                    }
                    .font(.headline)
                }
                .disabled(isRevising || revisionRequest.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                if !history.isEmpty && !isRevising {
                    Button("Annuler la retouche", systemImage: "arrow.uturn.backward") {
                        withAnimation { form = history.removeLast() }
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Annuler la retouche")
                }
            }
            .buttonStyle(.borderless)
        } header: {
            Text("Retoucher avec l'IA")
        } footer: {
            if let revisionError {
                Text(revisionError).foregroundStyle(.red)
            } else {
                Text("Remplace, retire ou ajoute ce que tu veux : ingrédients, étapes et valeurs sont adaptés partout.")
            }
        }
    }

    private func revise() async {
        let request = revisionRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !isRevising else { return }
        isRevising = true
        revisionError = nil
        revisionFocused = false
        do {
            let draft = try await AIService(context: context).revise(RecipeDraft(form: form), request: request)
            var revised = RecipeForm(draft: draft, source: form.source, rawInput: form.rawInput)
            revised.photo = form.photo
            history.append(form)
            withAnimation { form = revised }
            revisionRequest = ""
        } catch {
            revisionError = error.localizedDescription
        }
        isRevising = false
    }

    private var photoSection: some View {
        Section("Photo") {
            if let data = form.photo, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 14, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                Button("Retirer la photo", role: .destructive) { form.photo = nil }
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Prendre une photo", systemImage: "camera") { showCamera = true }
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choisir dans la photothèque", systemImage: "photo.on.rectangle")
            }
        }
    }

    private var ingredientsSection: some View {
        Section {
            ForEach($form.ingredients) { $ingredient in
                IngredientEditorRow(ingredient: $ingredient)
            }
            .onDelete { form.ingredients.remove(atOffsets: $0) }
            .onMove { form.ingredients.move(fromOffsets: $0, toOffset: $1) }
            Button("Ajouter un ingrédient", systemImage: "plus") {
                withAnimation { form.ingredients.append(Ingredient(name: "")) }
            }
        } header: {
            Text("Ingrédients")
        } footer: {
            Text("Les quantités sont facultatives : « poulet » suffit. Précise ce qui compte, comme les sauces.")
        }
    }

    /// Une carte par étape : chaque réglage sur sa propre ligne.
    @ViewBuilder
    private var stepsSection: some View {
        ForEach($form.steps) { $step in
            let index = form.steps.firstIndex { $0.id == step.id } ?? 0
            Section {
                StepEditor(step: $step)
            } header: {
                HStack {
                    Text("Étape \(index + 1)")
                    Spacer()
                    Menu {
                        Button("Monter", systemImage: "arrow.up") { moveStep(index, by: -1) }
                            .disabled(index == 0)
                        Button("Descendre", systemImage: "arrow.down") { moveStep(index, by: 1) }
                            .disabled(index == form.steps.count - 1)
                        Button("Supprimer l'étape", systemImage: "trash", role: .destructive) {
                            let id = step.id
                            withAnimation { form.steps.removeAll { $0.id == id } }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(minWidth: 44, minHeight: 32)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("Actions pour l'étape \(index + 1)")
                }
            }
        }
        Section {
            Button("Ajouter une étape", systemImage: "plus") {
                withAnimation { form.steps.append(RecipeStep(text: "")) }
            }
        } header: {
            if form.steps.isEmpty { Text("Étapes") }
        }
    }

    private func moveStep(_ index: Int, by offset: Int) {
        let target = index + offset
        guard form.steps.indices.contains(target) else { return }
        withAnimation { form.steps.swapAt(index, target) }
    }

    private func save() {
        if let recipe {
            form.apply(to: recipe)
        } else {
            let created = Recipe(title: form.title, source: form.source, rawInput: form.rawInput)
            form.apply(to: created)
            context.insert(created)
        }
        onSaved?()
        dismiss()
    }
}

private struct IngredientEditorRow: View {
    @Binding var ingredient: Ingredient

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Ingrédient", text: $ingredient.name)
                Menu {
                    Picker("Bloc", selection: $ingredient.group) {
                        Text("Base").tag("")
                        Text("Sauce").tag("Sauce")
                        Text("Finition").tag("Finition")
                        if !["", "Sauce", "Finition"].contains(ingredient.group) {
                            Text(ingredient.group).tag(ingredient.group)
                        }
                    }
                    Picker("Rayon", selection: $ingredient.aisle) {
                        ForEach(Aisle.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Basique du placard", isOn: $ingredient.isPantry)
                } label: {
                    Text(ingredient.group.isEmpty ? ingredient.aisle.label : "\(ingredient.group) · \(ingredient.aisle.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                }
            }
            HStack {
                TextField("Précision : 2 c. à soupe…", text: $ingredient.detail)
                TextField("g", value: $ingredient.grams, format: .number.precision(.fractionLength(0)))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                Text("g").foregroundStyle(.tertiary)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

private struct StepEditor: View {
    @Binding var step: RecipeStep

    var body: some View {
        TextField("Titre (facultatif)", text: $step.title)
            .font(.headline)
        TextField("Décris l'étape", text: $step.text, axis: .vertical)
            .lineLimit(2...)
        Stepper(value: $step.durationMinutes, in: 0...240) {
            LabeledContent {
                Text(step.durationMinutes == 0 ? "Aucun" : Format.minutes(step.durationMinutes))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            } label: {
                Label("Minuteur", systemImage: "timer")
            }
        }
        Toggle(isOn: $step.isPassive.animation(.snappy)) {
            Label("Tourne tout seul", systemImage: "arrow.triangle.branch")
        }
        if step.isPassive {
            TextField("Pendant ce temps… (facultatif)", text: $step.parallelHint, axis: .vertical)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MacroField: View {
    let title: String
    @Binding var value: Int
    let unit: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField("—", value: Binding<Int?>(get: { value == 0 ? nil : value }, set: { value = $0 ?? 0 }),
                          format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
                if value > 0 { Text(unit).foregroundStyle(.secondary) }
            }
            .monospacedDigit()
        }
    }
}

enum ImageResizer {
    static func jpeg(from data: Data) -> Data? {
        UIImage(data: data).flatMap(jpeg(from:))
    }

    /// Réduit à 1600 px de côté pour garder la base légère.
    static func jpeg(from image: UIImage) -> Data? {
        let maxSide: CGFloat = 1600
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.8)
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPick(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
