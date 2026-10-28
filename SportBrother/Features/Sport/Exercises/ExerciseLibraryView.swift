import SwiftData
import SwiftUI

extension SportSync {
    /// Réglages partagés d'un exo : la ligne existante, ou une nouvelle pour un exo du catalogue.
    func settings(for id: String, in overrides: [SportExercise]) -> SportExercise {
        if let existing = overrides.first(where: { $0.id == id }) {
            existing.deletedAt = nil
            return existing
        }
        return SportExercise(id: id)
    }
}

struct ExerciseLibraryView: View {
    @Environment(SportSync.self) private var sync
    @Query private var overrides: [SportExercise]
    @Query(sort: \SportTemplate.sortOrder) private var templates: [SportTemplate]

    @State private var mode = Mode.favorites
    @State private var search = ""
    @State private var group: MuscleGroup?
    @State private var creatingExercise = false
    @State private var editingTemplate: SportTemplate?

    enum Mode: String, CaseIterable, Identifiable {
        case favorites = "Favoris", all = "Tous", templates = "Modèles"
        var id: String { rawValue }
    }

    private var exercises: [ExerciseInfo] { ExerciseCatalog.merged(overrides).filter { !$0.isHidden } }

    private var filtered: [ExerciseInfo] {
        exercises
            .filter { mode != .favorites || $0.isFavorite }
            .filter { group == nil || $0.group == group }
            .filter { search.isEmpty || $0.name.localizedStandardContains(search) }
            .sorted { ($0.group.sortIndex, $0.order, $0.name) < ($1.group.sortIndex, $1.order, $1.name) }
    }

    private var liveTemplates: [SportTemplate] { templates.filter { $0.deletedAt == nil } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if mode == .templates {
                        ForEach(liveTemplates) { template in
                            Button { editingTemplate = template } label: { TemplateRowLabel(template: template) }
                                .tint(.primary)
                                .swipeActions {
                                    Button("Supprimer", systemImage: "trash", role: .destructive) { sync.delete(template) }
                                }
                        }
                    } else {
                        ForEach(filtered) { exercise in
                            NavigationLink(value: exercise.id) { ExerciseRowLabel(exercise: exercise) }
                                .swipeActions(edge: .leading) {
                                    Button(exercise.isFavorite ? "Retirer" : "Favori", systemImage: exercise.isFavorite ? "star.slash" : "star") {
                                        toggleFavorite(exercise)
                                    }
                                    .tint(.yellow)
                                }
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Affichage", selection: $mode) {
                            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        if mode != .templates { GroupFilter(selection: $group) }
                    }
                    .textCase(nil)
                    .padding(.bottom, 8)
                }
            }
            .listSectionSpacing(.compact)
            .animation(.snappy, value: filtered.map(\.id))
            .animation(.snappy, value: mode)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Exo")
            .overlay { emptyState }
            .navigationTitle("Exos")
            .navigationDestination(for: String.self) { ExerciseDetailView(exerciseID: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Ajouter", systemImage: "plus") {
                        Button("Nouvel exo", systemImage: "dumbbell") { creatingExercise = true }
                        Button("Nouveau modèle de séance", systemImage: "list.bullet.rectangle") {
                            editingTemplate = SportTemplate(name: "", sortOrder: (liveTemplates.map(\.sortOrder).max() ?? -1) + 1)
                        }
                    }
                }
            }
            .sheet(isPresented: $creatingExercise) { CustomExerciseSheet(group: group ?? .pecs) }
            .sheet(item: $editingTemplate) { TemplateEditorView(template: $0) }
        }
    }

    private func toggleFavorite(_ exercise: ExerciseInfo) {
        let settings = sync.settings(for: exercise.id, in: overrides)
        settings.isFavorite.toggle()
        sync.save(settings)
    }

    @ViewBuilder
    private var emptyState: some View {
        if mode == .templates, liveTemplates.isEmpty {
            ContentUnavailableView {
                Label("Aucun modèle", systemImage: "list.bullet.rectangle")
            } description: {
                Text("Enregistre une séance type (mêmes exos, même ordre) pour la relancer en un geste.")
            } actions: {
                Button("Créer un modèle") {
                    editingTemplate = SportTemplate(name: "", sortOrder: 0)
                }
                .buttonStyle(.glassProminent)
            }
        } else if mode == .favorites, filtered.isEmpty, search.isEmpty {
            ContentUnavailableView {
                Label("Pas encore de favoris", systemImage: "star")
            } description: {
                Text("Balaye un exo vers la droite dans « Tous » pour l'ajouter. Les favoris passent en premier quand tu ajoutes un exo à une séance.")
            } actions: {
                Button("Voir tous les exos") { mode = .all }.buttonStyle(.glass)
            }
        } else if mode != .templates, filtered.isEmpty {
            ContentUnavailableView.search(text: search)
        }
    }
}

extension MuscleGroup {
    var sortIndex: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

struct GroupFilter: View {
    @Binding var selection: MuscleGroup?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(MuscleGroup.allCases) { item in
                    ChipToggle(title: item.label, isOn: selection == item) {
                        selection = selection == item ? nil : item
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollIndicators(.hidden)
        .padding(.horizontal, -32)
    }
}

struct ExerciseRowLabel: View {
    let exercise: ExerciseInfo
    var detail: String?

    var body: some View {
        HStack(spacing: 12) {
            ExerciseThumbnail(exercise: exercise, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).lineLimit(2)
                Text(detail ?? exercise.group.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            if exercise.isFavorite {
                Image(systemName: "star.fill")
                    .imageScale(.small)
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Favori")
            }
        }
    }
}

struct TemplateRowLabel: View {
    let template: SportTemplate
    @Query private var items: [SportTemplateItem]
    @Query private var overrides: [SportExercise]

    var body: some View {
        let mine = items.filter { $0.templateID == template.id && $0.deletedAt == nil }
        let names = ExerciseCatalog.merged(overrides).byID
        let groups = Array(Set(mine.compactMap { names[$0.exerciseRef]?.group })).sorted { $0.sortIndex < $1.sortIndex }
        VStack(alignment: .leading, spacing: 2) {
            Text(template.name.isEmpty ? "Sans nom" : template.name).font(.body.weight(.medium))
            Text("\(mine.count) exo\(mine.count > 1 ? "s" : "")\(groups.isEmpty ? "" : " · " + groups.map(\.label).joined(separator: ", "))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

// MARK: Sélection d'exos

/// Choix d'un ou plusieurs exos : favoris d'abord, puis par groupe.
struct ExercisePicker: View {
    let title: String
    let onPick: ([ExerciseInfo]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query private var overrides: [SportExercise]
    @State private var search = ""
    @State private var group: MuscleGroup?
    @State private var picked: [String] = []
    @State private var creating = false

    private var exercises: [ExerciseInfo] {
        ExerciseCatalog.merged(overrides)
            .filter { !$0.isHidden }
            .filter { group == nil || $0.group == group }
            .filter { search.isEmpty || $0.name.localizedStandardContains(search) }
            .sorted { ($0.order, $0.name) < ($1.order, $1.name) }
    }

    var body: some View {
        NavigationStack {
            List {
                let favorites = exercises.filter(\.isFavorite)
                if !favorites.isEmpty {
                    Section("Favoris") { ForEach(favorites) { row($0) } }
                }
                ForEach(MuscleGroup.allCases.filter { g in exercises.contains { $0.group == g } }) { g in
                    Section(g.label) {
                        ForEach(exercises.filter { $0.group == g && !$0.isFavorite }) { row($0) }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                GroupFilter(selection: $group)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Exo")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(picked.isEmpty ? "Ajouter" : "Ajouter (\(picked.count))") {
                        let all = ExerciseCatalog.merged(overrides).byID
                        onPick(picked.compactMap { all[$0] })
                        dismiss()
                    }
                    .disabled(picked.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Créer un exo", systemImage: "plus") { creating = true }
                }
            }
            .sheet(isPresented: $creating) {
                CustomExerciseSheet(group: group ?? .pecs) { picked.append($0.id) }
            }
        }
    }

    private func row(_ exercise: ExerciseInfo) -> some View {
        let isPicked = picked.contains(exercise.id)
        return Button {
            if isPicked { picked.removeAll { $0 == exercise.id } } else { picked.append(exercise.id) }
        } label: {
            HStack {
                ExerciseRowLabel(exercise: exercise)
                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isPicked ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .tint(.primary)
        .sensoryFeedback(.selection, trigger: isPicked)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }
}

// MARK: Exo perso

struct CustomExerciseSheet: View {
    @State var group: MuscleGroup
    var onCreate: (SportExercise) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @Environment(SportSync.self) private var sync
    @State private var name = ""
    @State private var isBodyweight = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom de l'exo", text: $name).font(.title3)
                Picker("Groupe", selection: $group) {
                    ForEach(MuscleGroup.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Au poids du corps", isOn: $isBodyweight)
                Section {
                } footer: {
                    Text("Tu pourras photographier la machine depuis la fiche de l'exo.")
                }
            }
            .navigationTitle("Nouvel exo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") {
                        let exercise = SportExercise(id: UUID().uuidString.lowercased(), name: name.trimmingCharacters(in: .whitespaces), group: group)
                        exercise.isBodyweight = isBodyweight
                        sync.save(exercise)
                        onCreate(exercise)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
