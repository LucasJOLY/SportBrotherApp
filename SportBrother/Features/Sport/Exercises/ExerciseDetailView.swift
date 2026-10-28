import PhotosUI
import SwiftData
import SwiftUI

/// Fiche d'un exo : image, photo de la machine, favori, repos, fourchette de reps.
struct ExerciseDetailView: View {
    let exerciseID: String
    @Environment(SportSync.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @Query private var overrides: [SportExercise]
    @AppStorage(myProfileKey) private var myProfileID = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var renaming = false
    @State private var newName = ""

    private var exercise: ExerciseInfo? { ExerciseCatalog.merged(overrides).byID[exerciseID] }

    var body: some View {
        if let exercise {
            List {
                Section {
                    ExerciseHero(exercise: exercise)
                        .listRowInsets(EdgeInsets())
                }

                Section {
                    Toggle(isOn: binding(\.isFavorite, exercise.isFavorite)) {
                        Label("Favori", systemImage: "star")
                    }
                    Stepper(value: binding(\.restSeconds, exercise.restSeconds, default: ExerciseInfo.defaultRest), in: 0...600, step: 15) {
                        LabeledContent("Repos", value: exercise.restSeconds == 0 ? "Aucun" : Format.clock(TimeInterval(exercise.restSeconds)))
                            .monospacedDigit()
                    }
                    Stepper(value: binding(\.repRangeHigh, exercise.repRangeHigh, default: ExerciseInfo.defaultRepRangeHigh), in: 1...50) {
                        LabeledContent("Objectif de reps", value: "\(exercise.repRangeHigh)")
                            .monospacedDigit()
                    }
                } footer: {
                    Text("Quand toutes tes séries atteignent l'objectif de reps, l'app te propose de monter la charge la fois suivante.")
                }

                Section("Photo de la machine") {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Prendre une photo", systemImage: "camera") { showCamera = true }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choisir dans la photothèque", systemImage: "photo.on.rectangle")
                    }
                    if exercise.photoPath != nil {
                        Button("Revenir à l'image d'origine", systemImage: "arrow.uturn.backward", role: .destructive) {
                            let settings = sync.settings(for: exercise.id, in: overrides)
                            settings.photoPath = nil
                            sync.save(settings)
                        }
                    }
                }

                Section {
                    Button("Renommer", systemImage: "pencil") {
                        newName = exercise.name
                        renaming = true
                    }
                    Button(exercise.isCustom ? "Supprimer l'exo" : "Masquer de la liste", systemImage: exercise.isCustom ? "trash" : "eye.slash", role: .destructive) {
                        let settings = sync.settings(for: exercise.id, in: overrides)
                        if exercise.isCustom { sync.delete(settings) } else {
                            settings.isHidden = true
                            sync.save(settings)
                        }
                        dismiss()
                    }
                }
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: photoItem) {
                Task {
                    if let data = try? await photoItem?.loadTransferable(type: Data.self), let jpeg = SportPhoto.jpeg(from: data) {
                        sync.storePhoto(jpeg, for: sync.settings(for: exercise.id, in: overrides))
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    if let jpeg = SportPhoto.jpeg(from: image) {
                        sync.storePhoto(jpeg, for: sync.settings(for: exercise.id, in: overrides))
                    }
                }
                .ignoresSafeArea()
            }
            .alert("Renommer", isPresented: $renaming) {
                TextField("Nom", text: $newName)
                Button("Annuler", role: .cancel) {}
                Button("OK") {
                    let settings = sync.settings(for: exercise.id, in: overrides)
                    let trimmed = newName.trimmingCharacters(in: .whitespaces)
                    settings.name = trimmed.isEmpty ? nil : trimmed
                    sync.save(settings)
                }
            }
        } else {
            ContentUnavailableView("Exo introuvable", systemImage: "dumbbell")
        }
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<SportExercise, Bool>, _ current: Bool) -> Binding<Bool> {
        Binding {
            current
        } set: { value in
            let settings = sync.settings(for: exerciseID, in: overrides)
            settings[keyPath: keyPath] = value
            sync.save(settings)
        }
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<SportExercise, Int?>, _ current: Int, default: Int) -> Binding<Int> {
        Binding {
            current
        } set: { value in
            let settings = sync.settings(for: exerciseID, in: overrides)
            settings[keyPath: keyPath] = value
            sync.save(settings)
        }
    }
}

/// En-tête d'un exo : la photo de la machine si elle existe (plein cadre),
/// sinon l'illustration 3D animée du catalogue sur fond blanc, à sa taille d'origine pour rester nette.
struct ExerciseHero: View {
    let exercise: ExerciseInfo
    var height: CGFloat = 220
    @Environment(SportSync.self) private var sync
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var photo: UIImage?

    var body: some View {
        Group {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .clipped()
            } else if let still = ExerciseCatalog.image(for: exercise.id) {
                Group {
                    if !reduceMotion, let animation = ExerciseCatalog.animation(for: exercise.id) {
                        AnimatedImage(image: animation)
                    } else {
                        Image(uiImage: still).resizable().interpolation(.high)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(height: height - 16)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(Color.white)
            } else {
                Image(systemName: exercise.group.symbol)
                    .font(.system(size: 64, weight: .medium))
                    .foregroundStyle(exercise.group.color)
                    .frame(height: height * 0.8)
                    .frame(maxWidth: .infinity)
                    .background(exercise.group.color.opacity(0.12))
            }
        }
        .overlay(alignment: .bottomLeading) {
            Text(exercise.group.label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect()
                .padding(12)
        }
        .accessibilityHidden(true)
        .task(id: exercise.photoPath) {
            guard let path = exercise.photoPath else { photo = nil; return }
            photo = await sync.photo(path)
        }
    }
}

/// GIF animé du catalogue (SwiftUI n'anime pas les GIF nativement).
private struct AnimatedImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        if view.image !== image { view.image = image }
    }
}

/// Photos de machine : 1024 px suffisent à reconnaître l'appareil, ~150 Ko à envoyer.
enum SportPhoto {
    static func jpeg(from data: Data) -> Data? { UIImage(data: data).flatMap(jpeg(from:)) }

    static func jpeg(from image: UIImage) -> Data? {
        let maxSide: CGFloat = 1024
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.7)
    }
}

// MARK: Modèles de séance

struct TemplateEditorView: View {
    let template: SportTemplate
    @Environment(\.dismiss) private var dismiss
    @Environment(SportSync.self) private var sync
    @Query private var allItems: [SportTemplateItem]
    @Query private var overrides: [SportExercise]
    @State private var name = ""
    @State private var picking = false

    private var items: [SportTemplateItem] {
        allItems.filter { $0.templateID == template.id && $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            let exercises = ExerciseCatalog.merged(overrides).byID
            List {
                TextField("Nom (ex. Push, Dos-Biceps)", text: $name)
                    .font(.title3)
                Section {
                    ForEach(items) { item in
                        if let exercise = exercises[item.exerciseRef] {
                            TemplateItemEditorRow(exercise: exercise, setCount: Binding(get: { item.setCount }, set: { item.setCount = $0; save(item) }))
                        }
                    }
                    .onMove(perform: move)
                    .onDelete { offsets in offsets.map { items[$0] }.forEach(sync.delete) }
                    Button("Ajouter des exos", systemImage: "plus") { picking = true }
                } header: {
                    Text("Exos, dans l'ordre")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(template.name.isEmpty ? "Nouveau modèle" : template.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        template.name = name.trimmingCharacters(in: .whitespaces)
                        if !template.name.isEmpty || !items.isEmpty { sync.save(template) }
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $picking) {
                ExercisePicker(title: "Ajouter au modèle") { picked in
                    if template.modelContext == nil {
                        template.name = name.trimmingCharacters(in: .whitespaces)
                        sync.save(template)
                    }
                    let start = (items.map(\.sortOrder).max() ?? -1) + 1
                    for (offset, exercise) in picked.enumerated() {
                        sync.save(SportTemplateItem(templateID: template.id, exerciseRef: exercise.id, sortOrder: start + offset, setCount: 3))
                    }
                }
            }
            .onAppear { name = template.name }
        }
    }

    private func save(_ item: SportTemplateItem) { sync.save(item) }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = items
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, item) in ordered.enumerated() where item.sortOrder != index {
            item.sortOrder = index
            sync.save(item)
        }
    }
}

/// Ligne de l'éditeur de modèle : le nom garde toute la largeur, le nombre de séries se règle juste en dessous.
private struct TemplateItemEditorRow: View {
    let exercise: ExerciseInfo
    @Binding var setCount: Int

    var body: some View {
        HStack(spacing: 12) {
            ExerciseThumbnail(exercise: exercise, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text("\(setCount) série\(setCount > 1 ? "s" : "")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Spacer(minLength: 0)
                    stepButton("minus", label: "Une série de moins") { setCount = max(1, setCount - 1) }
                        .disabled(setCount <= 1)
                    stepButton("plus", label: "Une série de plus") { setCount = min(10, setCount + 1) }
                        .disabled(setCount >= 10)
                }
            }
        }
        .padding(.vertical, 2)
        .animation(.snappy(duration: 0.2), value: setCount)
        .sensoryFeedback(.selection, trigger: setCount)
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .frame(width: 34, height: 30)
                .background(.quaternary, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .accessibilityLabel(label)
    }
}
