import Charts
import SwiftData
import SwiftUI

/// Premier passage dans Sport sur ce téléphone : choisir son profil, ou le créer.
struct WhoAreYouView: View {
    @Environment(SportSync.self) private var sync
    @Query private var profiles: [SportProfile]
    @AppStorage(myProfileKey) private var myProfileID = ""
    @State private var creating = false

    var body: some View {
        NavigationStack {
            Group {
                if sync.isFirstLoad && profiles.live.isEmpty {
                    ProgressView("Récupération des profils…")
                } else {
                    List {
                        Section {
                            ForEach(profiles.live) { profile in
                                Button {
                                    myProfileID = profile.id.uuidString
                                } label: {
                                    ProfileLabel(profile: profile)
                                }
                                .tint(.primary)
                            }
                            if profiles.live.count < 4 {
                                Button("Créer mon profil", systemImage: "plus") { creating = true }
                            }
                        } footer: {
                            Text("Ce téléphone saisira pour ce profil par défaut. Tu peux toujours noter les séries d'un autre.")
                        }
                    }
                }
            }
            .navigationTitle("Qui es-tu ?")
            .sheet(isPresented: $creating) {
                ProfileEditorSheet(profile: nil) { myProfileID = $0.id.uuidString }
            }
        }
    }
}

struct ProfileLabel: View {
    let profile: SportProfile
    var isMe = false

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatar(profile: profile, size: 36)
            Text(profile.name).font(.body.weight(.medium))
            if isMe {
                Text("Ce téléphone")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ProfileAvatar: View {
    let profile: SportProfile
    var size: CGFloat = 28

    var body: some View {
        Text(profile.name.prefix(1).uppercased())
            .font(.system(size: size * 0.46, weight: .bold).width(.expanded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(profile.color.gradient, in: .circle)
            .accessibilityHidden(true)
    }
}

struct ProfilesView: View {
    @Environment(SportSync.self) private var sync
    @Query private var profiles: [SportProfile]
    @AppStorage(myProfileKey) private var myProfileID = ""
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(profiles.live) { profile in
                        NavigationLink(value: profile) {
                            ProfileLabel(profile: profile, isMe: profile.id.uuidString == myProfileID)
                        }
                    }
                } footer: {
                    Text("Jusqu'à 4 profils, partagés avec tous les téléphones.")
                }
            }
            .navigationTitle("Profils")
            .navigationSubtitle(sync.statusText)
            .navigationDestination(for: SportProfile.self) { ProfileDetailView(profile: $0) }
            .toolbar {
                if profiles.live.count < 4 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Ajouter un profil", systemImage: "plus") { creating = true }
                    }
                }
            }
            .sheet(isPresented: $creating) { ProfileEditorSheet(profile: nil) { _ in } }
            .refreshable { await sync.refresh() }
        }
    }
}

struct ProfileEditorSheet: View {
    let profile: SportProfile?
    let onSave: (SportProfile) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(SportSync.self) private var sync
    @Query private var profiles: [SportProfile]
    @State private var name = ""
    @State private var colorIndex = 0

    var body: some View {
        NavigationStack {
            Form {
                TextField("Prénom", text: $name)
                    .textContentType(.givenName)
                    .font(.title3)
                Section("Couleur") {
                    HStack(spacing: 16) {
                        ForEach(ProfilePalette.colors.indices, id: \.self) { index in
                            Button {
                                colorIndex = index
                            } label: {
                                Circle()
                                    .fill(ProfilePalette.color(index).gradient)
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if colorIndex == index {
                                            Image(systemName: "checkmark").font(.headline).foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Couleur \(index + 1)")
                            .accessibilityAddTraits(colorIndex == index ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                    .sensoryFeedback(.selection, trigger: colorIndex)
                }
            }
            .navigationTitle(profile == nil ? "Nouveau profil" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let profile {
                    name = profile.name
                    colorIndex = profile.colorIndex
                } else {
                    // Première couleur libre.
                    let used = Set(profiles.live.map(\.colorIndex))
                    colorIndex = ProfilePalette.colors.indices.first { !used.contains($0) } ?? 0
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let target = profile ?? SportProfile(name: trimmed, colorIndex: colorIndex, sortOrder: (profiles.live.map(\.sortOrder).max() ?? -1) + 1)
        target.name = trimmed
        target.colorIndex = colorIndex
        sync.save(target)
        onSave(target)
        dismiss()
    }
}

struct ProfileDetailView: View {
    let profile: SportProfile
    @Environment(SportSync.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SportBodyWeight.day) private var allWeights: [SportBodyWeight]
    @AppStorage(myProfileKey) private var myProfileID = ""
    @State private var editing = false
    @State private var addingWeight = false
    @State private var confirmDelete = false

    private var weights: [SportBodyWeight] {
        allWeights.filter { $0.profileID == profile.id && $0.deletedAt == nil }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    if let last = weights.last {
                        Text(Format.kg(last.kg))
                            .font(.display(.largeTitle))
                            .monospacedDigit()
                        Text(trendText ?? "Pesée du \(last.day.formatted(.dateTime.day().month(.wide)))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Pas encore de pesée")
                            .font(.display(.title2))
                        Text("Note ton poids pour suivre ta force par rapport à ton poids de corps.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)

                if weights.count > 1 {
                    Chart(weights) { weight in
                        LineMark(x: .value("Jour", weight.day), y: .value("Poids", weight.kg))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(profile.color)
                        PointMark(x: .value("Jour", weight.day), y: .value("Poids", weight.kg))
                            .symbolSize(24)
                            .foregroundStyle(profile.color)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 180)
                    .padding(.vertical, 8)
                    .accessibilityLabel("Évolution du poids")
                }

                Button("Ajouter une pesée", systemImage: "plus") { addingWeight = true }
            }

            if !weights.isEmpty {
                Section("Pesées") {
                    ForEach(weights.reversed()) { weight in
                        LabeledContent(weight.day.formatted(.dateTime.day().month().year()), value: Format.kg(weight.kg))
                            .monospacedDigit()
                            .swipeActions {
                                Button("Supprimer", systemImage: "trash", role: .destructive) { sync.delete(weight) }
                            }
                    }
                }
            }

            Section {
                if profile.id.uuidString != myProfileID {
                    Button("C'est moi sur ce téléphone", systemImage: "iphone") { myProfileID = profile.id.uuidString }
                }
                Button("Supprimer le profil", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(profile.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Modifier") { editing = true } }
        }
        .sheet(isPresented: $editing) { ProfileEditorSheet(profile: profile) { _ in } }
        .sheet(isPresented: $addingWeight) { WeightEntrySheet(profile: profile, last: weights.last?.kg) }
        .confirmationDialog("Supprimer le profil de \(profile.name) ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                sync.delete(profile)
                if profile.id.uuidString == myProfileID { myProfileID = "" }
                dismiss()
            }
        } message: {
            Text("Il disparaîtra de tous les téléphones. Ses séances restent dans l'historique des autres profils.")
        }
    }

    private var trendText: String? {
        guard weights.count > 1, let last = weights.last, let first = weights.first else { return nil }
        let delta = last.kg - first.kg
        guard abs(delta) >= 0.05 else { return "Stable depuis le \(first.day.formatted(.dateTime.day().month(.wide)))" }
        return "\(delta > 0 ? "+" : "−")\(Format.kg(abs(delta))) depuis le \(first.day.formatted(.dateTime.day().month(.wide)))"
    }
}

struct WeightEntrySheet: View {
    let profile: SportProfile
    let last: Double?
    @Environment(\.dismiss) private var dismiss
    @Environment(SportSync.self) private var sync
    @State private var kg = 75.0
    @State private var day = Date.now
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    TextField("Poids", value: $kg, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .font(.display(.largeTitle))
                        .monospacedDigit()
                        .focused($focused)
                    Text("kg").font(.title2).foregroundStyle(.secondary)
                }
                DatePicker("Jour", selection: $day, in: ...Date.now, displayedComponents: .date)
            }
            .navigationTitle("Pesée")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        sync.save(SportBodyWeight(profileID: profile.id, day: Calendar.current.startOfDay(for: day), kg: kg))
                        dismiss()
                    }
                    .disabled(kg <= 0)
                }
            }
            .onAppear {
                if let last { kg = last }
                focused = true
            }
        }
        .presentationDetents([.medium])
    }
}
