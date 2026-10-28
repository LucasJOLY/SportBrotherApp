import Foundation
import SwiftData
import SwiftUI

/// Les 7 grandes catégories d'une séance. `rawValue` = valeur stockée côté Supabase.
nonisolated enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case dos, biceps, triceps, epaules, pecs, jambes, abdos

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dos: "Dos"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .epaules: "Épaules"
        case .pecs: "Pecs"
        case .jambes: "Jambes"
        case .abdos: "Abdos"
        }
    }

    var symbol: String {
        switch self {
        case .dos: "figure.rower"
        case .biceps: "figure.strengthtraining.traditional"
        case .triceps: "figure.strengthtraining.functional"
        case .epaules: "figure.arms.open"
        case .pecs: "figure.mixed.cardio"
        case .jambes: "figure.step.training"
        case .abdos: "figure.core.training"
        }
    }

    var color: Color {
        switch self {
        case .dos: .blue
        case .biceps: .purple
        case .triceps: .indigo
        case .epaules: .teal
        case .pecs: .red
        case .jambes: .green
        case .abdos: .yellow
        }
    }
}

nonisolated enum Effort: String, Codable, CaseIterable, Identifiable, Sendable {
    case facile, bien, dur

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .facile: "gauge.with.dots.needle.0percent"
        case .bien: "gauge.with.dots.needle.50percent"
        case .dur: "gauge.with.dots.needle.100percent"
        }
    }
}

nonisolated enum ProfilePalette {
    static let colors: [Color] = [.orange, .blue, .green, .purple]
    static func color(_ index: Int) -> Color { colors[((index % colors.count) + colors.count) % colors.count] }
}

// MARK: Miroirs locaux des tables Supabase
//
// Les liens sont de simples identifiants (pas de relations SwiftData) : une ligne peut arriver du serveur
// avant son parent sans rien casser, et chaque écriture se synchronise ligne par ligne.
// `modifiedAt` = horloge du téléphone qui a écrit (arbitrage), `deletedAt` = suppression douce.

@Model
final class SportProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorIndex: Int
    var sortOrder: Int
    var modifiedAt: Date
    var deletedAt: Date?

    init(id: UUID = UUID(), name: String, colorIndex: Int, sortOrder: Int) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.sortOrder = sortOrder
        self.modifiedAt = .now
    }

    var color: Color { ProfilePalette.color(colorIndex) }
}

@Model
final class SportBodyWeight {
    @Attribute(.unique) var id: UUID
    var profileID: UUID
    var day: Date
    var kg: Double
    var modifiedAt: Date
    var deletedAt: Date?

    init(id: UUID = UUID(), profileID: UUID, day: Date, kg: Double) {
        self.id = id
        self.profileID = profileID
        self.day = day
        self.kg = kg
        self.modifiedAt = .now
    }
}

/// Réglages partagés d'un exo du catalogue (favori, photo, repos…) ou exo perso complet.
@Model
final class SportExercise {
    @Attribute(.unique) var id: String
    var name: String?
    var groupRaw: String?
    var photoPath: String?
    var isFavorite: Bool
    var restSeconds: Int?
    var repRangeHigh: Int?
    var isBodyweight: Bool?
    var isHidden: Bool
    var modifiedAt: Date
    var deletedAt: Date?

    init(id: String, name: String? = nil, group: MuscleGroup? = nil) {
        self.id = id
        self.name = name
        self.groupRaw = group?.rawValue
        self.isFavorite = false
        self.isHidden = false
        self.modifiedAt = .now
    }
}

@Model
final class SportTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var sortOrder: Int
    var modifiedAt: Date
    var deletedAt: Date?

    init(id: UUID = UUID(), name: String, sortOrder: Int) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.modifiedAt = .now
    }
}

@Model
final class SportTemplateItem {
    @Attribute(.unique) var id: UUID
    var templateID: UUID
    var exerciseRef: String
    var sortOrder: Int
    var setCount: Int
    var modifiedAt: Date
    var deletedAt: Date?

    init(id: UUID = UUID(), templateID: UUID, exerciseRef: String, sortOrder: Int, setCount: Int) {
        self.id = id
        self.templateID = templateID
        self.exerciseRef = exerciseRef
        self.sortOrder = sortOrder
        self.setCount = setCount
        self.modifiedAt = .now
    }
}

@Model
final class SportSession {
    @Attribute(.unique) var id: UUID
    var day: Date
    var startedAt: Date
    var endedAt: Date?
    var profileIDs: [UUID]
    var templateID: UUID?
    var modifiedAt: Date
    var deletedAt: Date?

    init(id: UUID = UUID(), day: Date, startedAt: Date = .now, profileIDs: [UUID], templateID: UUID? = nil) {
        self.id = id
        self.day = day
        self.startedAt = startedAt
        self.profileIDs = profileIDs
        self.templateID = templateID
        self.modifiedAt = .now
    }

    var isLive: Bool { endedAt == nil && deletedAt == nil }
}

@Model
final class SportEntry {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var exerciseRef: String
    var sortOrder: Int
    var modifiedAt: Date
    var deletedAt: Date?

    init(id: UUID = UUID(), sessionID: UUID, exerciseRef: String, sortOrder: Int) {
        self.id = id
        self.sessionID = sessionID
        self.exerciseRef = exerciseRef
        self.sortOrder = sortOrder
        self.modifiedAt = .now
    }
}

@Model
final class SportSet {
    @Attribute(.unique) var id: UUID
    var entryID: UUID
    var profileID: UUID
    var index: Int
    var weightKg: Double
    var reps: Int
    var doneAt: Date?
    var modifiedAt: Date
    var deletedAt: Date?

    init(id: UUID = UUID(), entryID: UUID, profileID: UUID, index: Int, weightKg: Double, reps: Int) {
        self.id = id
        self.entryID = entryID
        self.profileID = profileID
        self.index = index
        self.weightKg = weightKg
        self.reps = reps
        self.modifiedAt = .now
    }

    var isDone: Bool { doneAt != nil }
}

@Model
final class SportFeedback {
    @Attribute(.unique) var id: UUID
    var entryID: UUID
    var profileID: UUID
    var effortRaw: String?
    var note: String?
    var modifiedAt: Date
    var deletedAt: Date?

    init(id: UUID = UUID(), entryID: UUID, profileID: UUID) {
        self.id = id
        self.entryID = entryID
        self.profileID = profileID
        self.modifiedAt = .now
    }

    var effort: Effort? {
        get { effortRaw.flatMap(Effort.init(rawValue:)) }
        set { effortRaw = newValue?.rawValue }
    }
}

@Model
final class SportCoachReview {
    @Attribute(.unique) var id: UUID
    var profileID: UUID
    var month: Date
    var payload: Data
    var modifiedAt: Date
    var deletedAt: Date?

    init(id: UUID = UUID(), profileID: UUID, month: Date, payload: Data) {
        self.id = id
        self.profileID = profileID
        self.month = month
        self.payload = payload
        self.modifiedAt = .now
    }
}

/// Écriture locale pas encore confirmée par le serveur. Une seule entrée par ligne : la plus récente.
@Model
final class SportOutboxItem {
    @Attribute(.unique) var key: String
    var table: String
    var payload: Data
    var queuedAt: Date

    init(table: String, rowID: String, payload: Data) {
        self.key = "\(table)/\(rowID)"
        self.table = table
        self.payload = payload
        self.queuedAt = .now
    }
}
