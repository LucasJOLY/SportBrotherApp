import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    var body: some View {
        NavigationStack {
            Group {
                if let profile = profiles.first {
                    SettingsForm(profile: profile)
                } else {
                    ProgressView().onAppear { _ = context.profile() }
                }
            }
            .navigationTitle("Réglages")
        }
    }
}

private struct SettingsForm: View {
    @Environment(\.modelContext) private var context
    @Bindable var profile: UserProfile

    @State private var exportDocument: BackupDocument?
    @State private var showImporter = false
    @State private var pendingImport: Data?
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    EquipmentView(profile: profile)
                } label: {
                    LabeledContent("Matériel") {
                        Text("\(profile.equipment.count) appareils · \(profile.burners) feux").monospacedDigit()
                    }
                }
            } footer: {
                Text("Les recettes générées n'utilisent que ce que tu as.")
            }

            Section {
                EditableTagList(items: $profile.excludedFoods, placeholder: "Ajouter un aliment", tint: .red)
            } header: {
                Text("Aliments exclus")
            } footer: {
                Text("Allergies ou aliments que tu ne veux jamais voir dans une recette générée.")
            }

            Section {
                LabeledNumberField(title: "Poids", value: $profile.weightKg, unit: "kg")
                LabeledNumberField(title: "Protéines par repas", value: intBinding($profile.proteinTargetPerMeal), unit: "g")
                LabeledNumberField(title: "Calories par repas", value: intBinding($profile.kcalTargetPerMeal), unit: "kcal")
            } header: {
                Text("Objectifs")
            } footer: {
                Text("Facultatif. Sert à calibrer les recettes de prise de masse.")
            }

            Section("J'aime") {
                EditableTagList(items: $profile.tasteLikes, placeholder: "Ajouter un goût", tint: .orange)
            }
            Section {
                EditableTagList(items: $profile.tasteDislikes, placeholder: "Ajouter", tint: .gray)
            } header: {
                Text("Je n'aime pas")
            } footer: {
                Text("Tes réponses aux questions de l'IA s'ajoutent ici automatiquement.")
            }

            Section {
                Toggle("Planification IA par défaut", isOn: $profile.aiPlanningByDefault)
                LabeledContent("Clé API", value: ClaudeClient.configured == nil ? "Absente" : "Configurée")
                LabeledContent("Modèle", value: "Claude Haiku")
                LabeledContent("Tokens utilisés") {
                    Text("\(profile.aiInputTokens.formatted()) entrée · \(profile.aiOutputTokens.formatted()) sortie")
                        .monospacedDigit()
                }
            } header: {
                Text("IA")
            } footer: {
                Text("Coût estimé : \(estimatedCost). Chaque action IA fait un seul petit appel.")
            }

            Section {
                Button("Exporter les données", systemImage: "square.and.arrow.up") { export() }
                Button("Importer une sauvegarde", systemImage: "square.and.arrow.down") { showImporter = true }
            } header: {
                Text("Données")
            } footer: {
                Text("Tout est stocké sur ce téléphone. Exporte de temps en temps vers Fichiers ou iCloud Drive.")
            }
        }
        .fileExporter(
            isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
            document: exportDocument,
            contentType: .json,
            defaultFilename: "SportBrother-\(Date.now.formatted(.iso8601.year().month().day()))"
        ) { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                pendingImport = try Data(contentsOf: url)
            } catch {
                message = error.localizedDescription
            }
        }
        .confirmationDialog("Remplacer toutes les données ?",
                            isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
                            titleVisibility: .visible) {
            Button("Remplacer", role: .destructive) { restore() }
        } message: {
            Text("Recettes, semaines et statistiques actuelles seront remplacées par la sauvegarde.")
        }
        .alert("Données", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        } message: {
            Text(message ?? "")
        }
    }

    /// Tarif Haiku : 0,10 $ / M tokens en entrée, 0,50 $ / M en sortie.
    private var estimatedCost: String {
        let dollars = Double(profile.aiInputTokens) * 0.10 / 1_000_000 + Double(profile.aiOutputTokens) * 0.50 / 1_000_000
        return dollars.formatted(.currency(code: "USD").precision(.fractionLength(dollars < 1 ? 3 : 2)))
    }

    private func intBinding(_ binding: Binding<Int>) -> Binding<Double> {
        Binding(get: { Double(binding.wrappedValue) }, set: { binding.wrappedValue = Int($0) })
    }

    private func export() {
        do {
            exportDocument = BackupDocument(data: try BackupService.export(from: context))
        } catch {
            message = error.localizedDescription
        }
    }

    private func restore() {
        guard let pendingImport else { return }
        do {
            try BackupService.restore(pendingImport, into: context)
            message = "Sauvegarde importée."
        } catch {
            message = "Import impossible : \(error.localizedDescription)"
        }
    }
}

private struct EquipmentView: View {
    @Bindable var profile: UserProfile

    var body: some View {
        Form {
            Section {
                ForEach(Equipment.allCases) { item in
                    Toggle(item.label, isOn: Binding(
                        get: { profile.equipment.contains(item) },
                        set: { isOn in
                            profile.equipment.removeAll { $0 == item }
                            if isOn { profile.equipment.append(item) }
                        }
                    ))
                }
            }
            Section {
                Stepper(value: $profile.burners, in: 1...6) {
                    LabeledContent("Feux de cuisson", value: "\(profile.burners)")
                }
                TextField("Casseroles, poêles, tailles…", text: $profile.cookwareNotes, axis: .vertical)
            } footer: {
                Text("Ex. une casserole de 20 cm, une grande poêle, un plat à four.")
            }
        }
        .navigationTitle("Matériel")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LabeledNumberField: View {
    let title: String
    @Binding var value: Double
    let unit: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField("Non défini", value: Binding<Double?>(
                    get: { value == 0 ? nil : value },
                    set: { value = $0 ?? 0 }
                ), format: .number.precision(.fractionLength(0)))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 110)
                if value > 0 { Text(unit).foregroundStyle(.secondary) }
            }
            .monospacedDigit()
        }
    }
}

/// Liste d'étiquettes modifiable : un champ pour ajouter, un toucher sur une puce pour retirer.
private struct EditableTagList: View {
    @Binding var items: [String]
    let placeholder: String
    let tint: Color
    @State private var field = ""

    var body: some View {
        if !items.isEmpty {
            FlowLayout {
                ForEach(items, id: \.self) { item in
                    ChipToggle(title: item, symbol: "xmark", isOn: true) {
                        withAnimation(.snappy) { items.removeAll { $0 == item } }
                    }
                    .tint(tint)
                    .accessibilityHint("Retirer")
                }
            }
            .padding(.vertical, 4)
        }
        TextField(placeholder, text: $field)
            .submitLabel(.done)
            .onSubmit {
                let value = field.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty, !items.contains(value) else { return }
                withAnimation(.snappy) { items.append(value) }
                field = ""
            }
    }
}
