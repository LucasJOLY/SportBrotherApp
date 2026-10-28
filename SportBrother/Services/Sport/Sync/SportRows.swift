import Foundation
import SwiftData

/// Ligne d'une table `sport_*`, telle qu'échangée avec Supabase (clés en snake_case).
nonisolated protocol SportRow: Codable, Sendable {
    associatedtype Model: SportSynced where Model.Row == Self
    static var table: String { get }
    var rowID: String { get }
    var modifiedAt: Date { get }
    @MainActor func makeModel() -> Model
    @MainActor func apply(to model: Model)
}

/// Modèle SwiftData miroir d'une table `sport_*`.
protocol SportSynced: PersistentModel {
    associatedtype Row: SportRow where Row.Model == Self
    var rowID: String { get }
    var modifiedAt: Date { get set }
    var deletedAt: Date? { get set }
    var row: Row { get }
    static func matching(rowID: String) -> Predicate<Self>
}

/// Jour calendaire local ⇄ colonne Postgres `date` (« 2026-10-28 »).
nonisolated enum SportDay {
    private static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    static func string(_ date: Date) -> String { formatter().string(from: date) }
    static func date(_ string: String) -> Date { formatter().date(from: string) ?? .now }
}

/// Encodage JSON commun : horodatages ISO 8601 (Postgres renvoie jusqu'aux microsecondes).
nonisolated enum SportJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true)))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = parse(raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Date illisible : \(raw)")
            }
            return date
        }
        return decoder
    }()

    /// « 2026-10-28T20:32:55.398428+00:00 », « …55Z », « 2026-10-28 20:32:55+00 »…
    static func parse(_ raw: String) -> Date? {
        var text = raw.replacingOccurrences(of: " ", with: "T")
        if text.hasSuffix("+00") { text += ":00" }
        // Ramène les fractions de seconde à 3 chiffres, seul format accepté partout.
        if let dot = text.firstIndex(of: ".") {
            let digits = text[text.index(after: dot)...].prefix { $0.isNumber }
            let end = text.index(dot, offsetBy: digits.count + 1)
            text.replaceSubrange(text.index(after: dot)..<end, with: (digits + "000").prefix(3))
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = text.contains(".") ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

// MARK: Lignes

nonisolated struct ProfileRow: SportRow {
    static let table = "sport_profiles"
    var id: UUID
    var name: String
    var colorIndex: Int
    var sortOrder: Int
    var modifiedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, colorIndex = "color_index", sortOrder = "sort_order", modifiedAt = "modified_at", deletedAt = "deleted_at"
    }

    var rowID: String { id.uuidString.lowercased() }
    @MainActor func makeModel() -> SportProfile { SportProfile(id: id, name: name, colorIndex: colorIndex, sortOrder: sortOrder) }
    @MainActor func apply(to model: SportProfile) {
        model.name = name
        model.colorIndex = colorIndex
        model.sortOrder = sortOrder
        model.modifiedAt = modifiedAt
        model.deletedAt = deletedAt
    }
}

nonisolated struct BodyWeightRow: SportRow {
    static let table = "sport_body_weights"
    var id: UUID
    var profileID: UUID
    var measuredOn: String
    var kg: Double
    var modifiedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, kg, profileID = "profile_id", measuredOn = "measured_on", modifiedAt = "modified_at", deletedAt = "deleted_at"
    }

    var rowID: String { id.uuidString.lowercased() }
    @MainActor func makeModel() -> SportBodyWeight { SportBodyWeight(id: id, profileID: profileID, day: SportDay.date(measuredOn), kg: kg) }
    @MainActor func apply(to model: SportBodyWeight) {
        model.profileID = profileID
        model.day = SportDay.date(measuredOn)
        model.kg = kg
        model.modifiedAt = modifiedAt
        model.deletedAt = deletedAt
    }
}

nonisolated struct ExerciseRow: SportRow {
    static let table = "sport_exercises"
    var id: String
    var name: String?
    var muscleGroup: String?
    var photoPath: String?
    var isFavorite: Bool
    var restSeconds: Int?
    var repRangeHigh: Int?
    var isBodyweight: Bool?
    var isHidden: Bool
    var modifiedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, muscleGroup = "muscle_group", photoPath = "photo_path", isFavorite = "is_favorite",
             restSeconds = "rest_seconds", repRangeHigh = "rep_range_high", isBodyweight = "is_bodyweight",
             isHidden = "is_hidden", modifiedAt = "modified_at", deletedAt = "deleted_at"
    }

    var rowID: String { id }
    @MainActor func makeModel() -> SportExercise {
        let model = SportExercise(id: id)
        apply(to: model)
        return model
    }
    @MainActor func apply(to model: SportExercise) {
        model.name = name
        model.groupRaw = muscleGroup
        model.photoPath = photoPath
        model.isFavorite = isFavorite
        model.restSeconds = restSeconds
        model.repRangeHigh = repRangeHigh
        model.isBodyweight = isBodyweight
        model.isHidden = isHidden
        model.modifiedAt = modifiedAt
        model.deletedAt = deletedAt
    }
}

nonisolated struct TemplateRow: SportRow {
    static let table = "sport_templates"
    var id: UUID
    var name: String
    var sortOrder: Int
    var modifiedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, sortOrder = "sort_order", modifiedAt = "modified_at", deletedAt = "deleted_at"
    }

    var rowID: String { id.uuidString.lowercased() }
    @MainActor func makeModel() -> SportTemplate { SportTemplate(id: id, name: name, sortOrder: sortOrder) }
    @MainActor func apply(to model: SportTemplate) {
        model.name = name
        model.sortOrder = sortOrder
        model.modifiedAt = modifiedAt
        model.deletedAt = deletedAt
    }
}

nonisolated struct TemplateItemRow: SportRow {
    static let table = "sport_template_items"
    var id: UUID
    var templateID: UUID
    var exerciseRef: String
    var sortOrder: Int
    var setCount: Int
    var modifiedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, templateID = "template_id", exerciseRef = "exercise_ref", sortOrder = "sort_order",
             setCount = "set_count", modifiedAt = "modified_at", deletedAt = "deleted_at"
    }

    var rowID: String { id.uuidString.lowercased() }
    @MainActor func makeModel() -> SportTemplateItem {
        SportTemplateItem(id: id, templateID: templateID, exerciseRef: exerciseRef, sortOrder: sortOrder, setCount: setCount)
    }
    @MainActor func apply(to model: SportTemplateItem) {
        model.templateID = templateID
        model.exerciseRef = exerciseRef
        model.sortOrder = sortOrder
        model.setCount = setCount
        model.modifiedAt = modifiedAt
        model.deletedAt = deletedAt
    }
}

nonisolated struct SessionRow: SportRow {
    static let table = "sport_sessions"
    var id: UUID
    var performedOn: String
    var startedAt: Date
    var endedAt: Date?
    var profileIDs: [UUID]
    var templateID: UUID?
    var modifiedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, performedOn = "performed_on", startedAt = "started_at", endedAt = "ended_at",
             profileIDs = "profile_ids", templateID = "template_id", modifiedAt = "modified_at", deletedAt = "deleted_at"
    }

    var rowID: String { id.uuidString.lowercased() }
    @MainActor func makeModel() -> SportSession {
        let model = SportSession(id: id, day: SportDay.date(performedOn), startedAt: startedAt, profileIDs: profileIDs, templateID: templateID)
        apply(to: model)
        return model
    }
    @MainActor func apply(to model: SportSession) {
        model.day = SportDay.date(performedOn)
        model.startedAt = startedAt
        model.endedAt = endedAt
        model.profileIDs = profileIDs
        model.templateID = templateID
        model.modifiedAt = modifiedAt
        model.deletedAt = deletedAt
    }
}

nonisolated struct EntryRow: SportRow {
    static let table = "sport_entries"
    var id: UUID
    var sessionID: UUID
    var exerciseRef: String
    var sortOrder: Int
    var modifiedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, sessionID = "session_id", exerciseRef = "exercise_ref", sortOrder = "sort_order",
             modifiedAt = "modified_at", deletedAt = "deleted_at"
    }

    var rowID: String { id.uuidString.lowercased() }
    @MainActor func makeModel() -> SportEntry { SportEntry(id: id, sessionID: sessionID, exerciseRef: exerciseRef, sortOrder: sortOrder) }
    @MainActor func apply(to model: SportEntry) {
        model.sessionID = sessionID
        model.exerciseRef = exerciseRef
        model.sortOrder = sortOrder
        model.modifiedAt = modifiedAt
        model.deletedAt = deletedAt
    }
}

nonisolated struct SetRow: SportRow {
    static let table = "sport_sets"
    var id: UUID
    var entryID: UUID
    var profileID: UUID
    var setIndex: Int
    var weightKg: Double
    var reps: Int
    var doneAt: Date?
    var modifiedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, reps, entryID = "entry_id", profileID = "profile_id", setIndex = "set_index", weightKg = "weight_kg",
             doneAt = "done_at", modifiedAt = "modified_at", deletedAt = "deleted_at"
    }

    var rowID: String { id.uuidString.lowercased() }
    @MainActor func makeModel() -> SportSet {
        let model = SportSet(id: id, entryID: entryID, profileID: profileID, index: setIndex, weightKg: weightKg, reps: reps)
        apply(to: model)
        return model
    }
    @MainActor func apply(to model: SportSet) {
        model.entryID = entryID
        model.profileID = profileID
        model.index = setIndex
        model.weightKg = weightKg
        model.reps = reps
        model.doneAt = doneAt
        model.modifiedAt = modifiedAt
        model.deletedAt = deletedAt
    }
}

nonisolated struct FeedbackRow: SportRow {
    static let table = "sport_feedback"
    var id: UUID
    var entryID: UUID
    var profileID: UUID
    var effort: String?
    var note: String?
    var modifiedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, effort, note, entryID = "entry_id", profileID = "profile_id", modifiedAt = "modified_at", deletedAt = "deleted_at"
    }

    var rowID: String { id.uuidString.lowercased() }
    @MainActor func makeModel() -> SportFeedback {
        let model = SportFeedback(id: id, entryID: entryID, profileID: profileID)
        apply(to: model)
        return model
    }
    @MainActor func apply(to model: SportFeedback) {
        model.entryID = entryID
        model.profileID = profileID
        model.effortRaw = effort
        model.note = note
        model.modifiedAt = modifiedAt
        model.deletedAt = deletedAt
    }
}

nonisolated struct CoachReviewRow: SportRow {
    static let table = "sport_coach_reviews"
    var id: UUID
    var profileID: UUID
    var month: String
    var payload: CoachReview
    var modifiedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, month, payload, profileID = "profile_id", modifiedAt = "modified_at", deletedAt = "deleted_at"
    }

    var rowID: String { id.uuidString.lowercased() }
    @MainActor func makeModel() -> SportCoachReview {
        let model = SportCoachReview(id: id, profileID: profileID, month: SportDay.date(month), payload: Data())
        apply(to: model)
        return model
    }
    @MainActor func apply(to model: SportCoachReview) {
        model.profileID = profileID
        model.month = SportDay.date(month)
        model.payload = (try? JSONEncoder().encode(payload)) ?? Data()
        model.modifiedAt = modifiedAt
        model.deletedAt = deletedAt
    }
}

// MARK: Modèles → lignes

extension SportProfile: SportSynced {
    var rowID: String { id.uuidString.lowercased() }
    static func matching(rowID: String) -> Predicate<SportProfile> {
        let id = UUID(uuidString: rowID) ?? UUID()
        return #Predicate { $0.id == id }
    }
    var row: ProfileRow { .init(id: id, name: name, colorIndex: colorIndex, sortOrder: sortOrder, modifiedAt: modifiedAt, deletedAt: deletedAt) }
}

extension SportBodyWeight: SportSynced {
    var rowID: String { id.uuidString.lowercased() }
    static func matching(rowID: String) -> Predicate<SportBodyWeight> {
        let id = UUID(uuidString: rowID) ?? UUID()
        return #Predicate { $0.id == id }
    }
    var row: BodyWeightRow {
        .init(id: id, profileID: profileID, measuredOn: SportDay.string(day), kg: kg, modifiedAt: modifiedAt, deletedAt: deletedAt)
    }
}

extension SportExercise: SportSynced {
    var rowID: String { id }
    static func matching(rowID: String) -> Predicate<SportExercise> { #Predicate { $0.id == rowID } }
    var row: ExerciseRow {
        .init(id: id, name: name, muscleGroup: groupRaw, photoPath: photoPath, isFavorite: isFavorite, restSeconds: restSeconds,
              repRangeHigh: repRangeHigh, isBodyweight: isBodyweight, isHidden: isHidden, modifiedAt: modifiedAt, deletedAt: deletedAt)
    }
}

extension SportTemplate: SportSynced {
    var rowID: String { id.uuidString.lowercased() }
    static func matching(rowID: String) -> Predicate<SportTemplate> {
        let id = UUID(uuidString: rowID) ?? UUID()
        return #Predicate { $0.id == id }
    }
    var row: TemplateRow { .init(id: id, name: name, sortOrder: sortOrder, modifiedAt: modifiedAt, deletedAt: deletedAt) }
}

extension SportTemplateItem: SportSynced {
    var rowID: String { id.uuidString.lowercased() }
    static func matching(rowID: String) -> Predicate<SportTemplateItem> {
        let id = UUID(uuidString: rowID) ?? UUID()
        return #Predicate { $0.id == id }
    }
    var row: TemplateItemRow {
        .init(id: id, templateID: templateID, exerciseRef: exerciseRef, sortOrder: sortOrder, setCount: setCount,
              modifiedAt: modifiedAt, deletedAt: deletedAt)
    }
}

extension SportSession: SportSynced {
    var rowID: String { id.uuidString.lowercased() }
    static func matching(rowID: String) -> Predicate<SportSession> {
        let id = UUID(uuidString: rowID) ?? UUID()
        return #Predicate { $0.id == id }
    }
    var row: SessionRow {
        .init(id: id, performedOn: SportDay.string(day), startedAt: startedAt, endedAt: endedAt, profileIDs: profileIDs,
              templateID: templateID, modifiedAt: modifiedAt, deletedAt: deletedAt)
    }
}

extension SportEntry: SportSynced {
    var rowID: String { id.uuidString.lowercased() }
    static func matching(rowID: String) -> Predicate<SportEntry> {
        let id = UUID(uuidString: rowID) ?? UUID()
        return #Predicate { $0.id == id }
    }
    var row: EntryRow {
        .init(id: id, sessionID: sessionID, exerciseRef: exerciseRef, sortOrder: sortOrder, modifiedAt: modifiedAt, deletedAt: deletedAt)
    }
}

extension SportSet: SportSynced {
    var rowID: String { id.uuidString.lowercased() }
    static func matching(rowID: String) -> Predicate<SportSet> {
        let id = UUID(uuidString: rowID) ?? UUID()
        return #Predicate { $0.id == id }
    }
    var row: SetRow {
        .init(id: id, entryID: entryID, profileID: profileID, setIndex: index, weightKg: weightKg, reps: reps, doneAt: doneAt,
              modifiedAt: modifiedAt, deletedAt: deletedAt)
    }
}

extension SportFeedback: SportSynced {
    var rowID: String { id.uuidString.lowercased() }
    static func matching(rowID: String) -> Predicate<SportFeedback> {
        let id = UUID(uuidString: rowID) ?? UUID()
        return #Predicate { $0.id == id }
    }
    var row: FeedbackRow {
        .init(id: id, entryID: entryID, profileID: profileID, effort: effortRaw, note: note, modifiedAt: modifiedAt, deletedAt: deletedAt)
    }
}

extension SportCoachReview: SportSynced {
    var rowID: String { id.uuidString.lowercased() }
    static func matching(rowID: String) -> Predicate<SportCoachReview> {
        let id = UUID(uuidString: rowID) ?? UUID()
        return #Predicate { $0.id == id }
    }
    var row: CoachReviewRow {
        .init(id: id, profileID: profileID, month: SportDay.string(month),
              payload: (try? JSONDecoder().decode(CoachReview.self, from: payload)) ?? CoachReview(headline: "", tips: []),
              modifiedAt: modifiedAt, deletedAt: deletedAt)
    }

    var review: CoachReview? { try? JSONDecoder().decode(CoachReview.self, from: payload) }
}

/// Bilan IA du mois, stocké tel quel en `jsonb`.
nonisolated struct CoachReview: Codable, Hashable, Sendable {
    var headline: String
    var tips: [String]
}
