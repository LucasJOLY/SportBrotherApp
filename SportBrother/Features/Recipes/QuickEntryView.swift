import PhotosUI
import SwiftData
import SwiftUI

/// Recette écrite en vrac, photographiée ou importée d'un lien, mise au propre par Claude puis relue avant d'enregistrer.
struct QuickEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var link = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var working: Source?
    @State private var error: String?
    @State private var draft: DraftRoute?
    @FocusState private var focused: Bool

    private nonisolated enum Source { case text, photo, link }

    var body: some View {
        let isImportingPhoto = working == .photo
        NavigationStack {
            Form {
                Section {
                    TextField("Poulet, riz, brocolis. Mariner le poulet au citron et à l'ail, four 200 °C 25 min, riz 12 min…",
                              text: $text, axis: .vertical)
                        .lineLimit(6...)
                        .focused($focused)
                } footer: {
                    Text("Écris comme ça vient. Claude organise ingrédients, étapes, minuteurs et four, et tu relis avant d'enregistrer.")
                }

                Section {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        ImportRow(title: "Photo d'une recette", symbol: "photo.on.rectangle", isWorking: isImportingPhoto)
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showCamera = true } label: {
                            ImportRow(title: "Photographier une recette", symbol: "camera", isWorking: false)
                        }
                    }
                    HStack {
                        TextField("Lien Marmiton, Instagram, blog…", text: $link)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit { Task { await importLink() } }
                        if working == .link {
                            ProgressView()
                        } else if !link.isEmpty {
                            Button("Importer") { Task { await importLink() } }
                                .fontWeight(.semibold)
                        } else if UIPasteboard.general.hasURLs {
                            Button("Coller", systemImage: "doc.on.clipboard") {
                                link = UIPasteboard.general.url?.absoluteString ?? ""
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                } header: {
                    Text("Ou importe")
                } footer: {
                    Text("Livre, capture d'écran ou site de cuisine : la recette est remise au format de l'app.")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .disabled(working != nil)
            .navigationTitle("Ajouter une recette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if working == .text {
                        ProgressView()
                    } else {
                        Button("Mettre en forme", systemImage: "sparkles") {
                            Task { await format(text, images: [], source: .text) }
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).count < 10)
                    }
                }
            }
            .navigationDestination(item: $draft) { route in
                RecipeEditorView(form: route.form, recipe: nil, onSaved: { dismiss() })
            }
            .onChange(of: photoItem) {
                Task {
                    guard let data = try? await photoItem?.loadTransferable(type: Data.self),
                          let jpeg = ImageResizer.jpeg(from: data) else { return }
                    await format(text, images: [jpeg], source: .photo)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    guard let jpeg = ImageResizer.jpeg(from: image) else { return }
                    Task { await format(text, images: [jpeg], source: .photo) }
                }
                .ignoresSafeArea()
            }
            .interactiveDismissDisabled(!text.isEmpty || working != nil)
        }
    }

    private func importLink() async {
        guard !link.isEmpty, working == nil else { return }
        working = .link
        error = nil
        do {
            let page = try await RecipeImporter.fetchText(from: link)
            working = nil
            await format(text.isEmpty ? page : "\(page)\nPrécisions : \(text)", images: [], source: .link, rawInput: link)
        } catch {
            self.error = error.localizedDescription
            working = nil
        }
    }

    private func format(_ input: String, images: [Data], source: Source, rawInput: String? = nil) async {
        working = source
        error = nil
        do {
            let result = try await AIService(context: context).formatRecipe(input, images: images)
            draft = DraftRoute(form: RecipeForm(draft: result, source: .manual, rawInput: rawInput ?? input))
        } catch {
            self.error = error.localizedDescription
        }
        working = nil
    }
}

private struct ImportRow: View {
    let title: String
    let symbol: String
    let isWorking: Bool

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            if isWorking { ProgressView() }
        }
    }
}

/// Brouillon à relire dans l'éditeur, identifié pour la navigation.
struct DraftRoute: Hashable {
    let id = UUID()
    let form: RecipeForm

    static func == (lhs: DraftRoute, rhs: DraftRoute) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
