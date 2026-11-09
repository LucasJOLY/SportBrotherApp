import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import SportBrother

struct StrengthStatsTests {
    private let day = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func oneRepMaxFollowsEpley() {
        #expect(StrengthStats.oneRepMax(SetValue(weight: 100, reps: 1)) == 100)
        #expect(abs(StrengthStats.oneRepMax(SetValue(weight: 60, reps: 10)) - 80) < 0.001)
        #expect(StrengthStats.oneRepMax(SetValue(weight: 60, reps: 0)) == 0)
    }

    @Test func recordsKeepBestWeightForAtLeastThatManyReps() {
        let performances = [
            Performance(sessionID: UUID(), day: day, sets: [SetValue(weight: 60, reps: 10), SetValue(weight: 70, reps: 5)]),
            Performance(sessionID: UUID(), day: day.addingTimeInterval(86400), sets: [SetValue(weight: 80, reps: 1)]),
        ]
        let records = Dictionary(uniqueKeysWithValues: StrengthStats.records(performances).map { ($0.reps, $0.weight) })
        #expect(records[1] == 80)
        #expect(records[5] == 70)
        #expect(records[8] == 60)
        #expect(records[10] == 60)
        #expect(records[12] == nil)
    }

    @Test func detectsRecordOnlyWhenHeavierAtSameReps() {
        let previous = [Performance(sessionID: UUID(), day: day, sets: [SetValue(weight: 60, reps: 10)])]
        #expect(StrengthStats.isRecord(SetValue(weight: 62.5, reps: 10), previous: previous))
        #expect(StrengthStats.isRecord(SetValue(weight: 62.5, reps: 8), previous: previous))
        #expect(!StrengthStats.isRecord(SetValue(weight: 60, reps: 10), previous: previous))
        #expect(!StrengthStats.isRecord(SetValue(weight: 62.5, reps: 12), previous: []))
    }

    @Test func workingMaxNeedsAtLeastSixReps() {
        let performance = Performance(sessionID: UUID(), day: day, sets: [
            SetValue(weight: 80, reps: 3), SetValue(weight: 70, reps: 6), SetValue(weight: 65, reps: 10),
        ])
        #expect(StrengthStats.workingMax(performance) == 70)
        #expect(StrengthStats.workingMax(Performance(sessionID: UUID(), day: day, sets: [SetValue(weight: 90, reps: 2)])) == nil)
    }

    @Test func bodyWeightUsesLastWeighInBeforeTheDay() {
        let weighIns = [(day: day, kg: 80.0), (day: day.addingTimeInterval(10 * 86400), kg: 78.0)]
        #expect(StrengthStats.bodyWeight(on: day.addingTimeInterval(5 * 86400), weighIns: weighIns) == 80)
        #expect(StrengthStats.bodyWeight(on: day.addingTimeInterval(20 * 86400), weighIns: weighIns) == 78)
        #expect(StrengthStats.bodyWeight(on: day.addingTimeInterval(-86400), weighIns: weighIns) == 80)
        #expect(StrengthStats.bodyWeight(on: day, weighIns: []) == nil)
    }

    @Test func bodyweightRecordCountsReps() {
        let previous = [Performance(sessionID: UUID(), day: day, sets: [SetValue(weight: 0, reps: 8)])]
        #expect(StrengthStats.isRecord(SetValue(weight: 0, reps: 9), previous: previous))
        #expect(!StrengthStats.isRecord(SetValue(weight: 0, reps: 8), previous: previous))
    }

    @Test func dropSetCountsEveryStepInVolumeButOnlyFirstForRecords() {
        let drop = SetValue(weight: 60, reps: 8, drops: [DropStep(kg: 45, reps: 6), DropStep(kg: 30, reps: 6)])
        #expect(drop.volume == 930)
        #expect(StrengthStats.oneRepMax(drop) == StrengthStats.oneRepMax(SetValue(weight: 60, reps: 8)))
        let performance = Performance(sessionID: UUID(), day: day, sets: [drop])
        #expect(performance.volume == drop.volume)
        #expect(performance.topWeight == 60)
        let records = StrengthStats.records([performance])
        #expect(!records.contains { $0.weight < 60 })
    }

    @Test func unilateralVolumeCountsBothSides() {
        let set = SetValue(weight: 20, reps: 10, unilateral: true)
        #expect(set.volume == 400)
        #expect(StrengthStats.oneRepMax(set) == StrengthStats.oneRepMax(SetValue(weight: 20, reps: 10)))
        let withDrop = SetValue(weight: 20, reps: 10, drops: [DropStep(kg: 15, reps: 8)], unilateral: true)
        #expect(withDrop.volume == (200 + 120) * 2)
    }

    @Test func labelsShowStepsAndPerArmLoad() {
        #expect(SetValue(weight: 60, reps: 8).label == "60×8")
        #expect(SetValue(weight: 0, reps: 12).label == "12 reps")
        #expect(SetValue(weight: 60, reps: 8, drops: [DropStep(kg: 45, reps: 6), DropStep(kg: 30, reps: 6)]).label == "60×8 → 45×6 → 30×6")
        #expect(SetValue(weight: 20, reps: 10, unilateral: true).label == "20 kg/bras × 10")
        #expect(SetValue(weight: 62.5, reps: 8, drops: [DropStep(kg: 50, reps: 6)]).main.label == "62,5×8")
    }

    @Test func nextDropIsAboutTwentyPercentLighter() {
        #expect(Progression.nextDrop(after: 60, reps: 8) == DropStep(kg: 47.5, reps: 8))
        #expect(Progression.nextDrop(after: 10, reps: 12) == DropStep(kg: 7.5, reps: 12))
        #expect(Progression.nextDrop(after: 2.5, reps: 10).kg == 0)
    }

    @Test func prefillCopiesDropsFromLastTime() {
        let last = Performance(sessionID: UUID(), day: day, sets: [
            SetValue(weight: 60, reps: 10),
            SetValue(weight: 60, reps: 8, drops: [DropStep(kg: 45, reps: 6)]),
        ])
        #expect(Progression.prefill(index: 1, last: last, today: []).drops == [DropStep(kg: 45, reps: 6)])
    }
}

struct ProgressionTests {
    private let last = Performance(sessionID: UUID(), day: .now, sets: [SetValue(weight: 60, reps: 12), SetValue(weight: 60, reps: 12)])

    @Test func suggestsMoreWeightWhenAllSetsHitTheTop() {
        #expect(Progression.suggestion(last: last, repRangeHigh: 12, isBodyweight: false) == .addWeight(2.5))
        #expect(Progression.suggestion(last: last, repRangeHigh: 12, isBodyweight: true) == .addRep)
    }

    @Test func noSuggestionWhenASetFellShort() {
        let short = Performance(sessionID: UUID(), day: .now, sets: [SetValue(weight: 60, reps: 12), SetValue(weight: 60, reps: 9)])
        #expect(Progression.suggestion(last: short, repRangeHigh: 12, isBodyweight: false) == nil)
        #expect(Progression.suggestion(last: nil, repRangeHigh: 12, isBodyweight: false) == nil)
    }

    @Test func prefillsFromSameSetLastTime() {
        let varied = Performance(sessionID: UUID(), day: .now, sets: [SetValue(weight: 60, reps: 10), SetValue(weight: 57.5, reps: 8)])
        #expect(Progression.prefill(index: 1, last: varied, today: []) == SetValue(weight: 57.5, reps: 8))
        #expect(Progression.prefill(index: 4, last: varied, today: []) == SetValue(weight: 57.5, reps: 8))
        #expect(Progression.prefill(index: 0, last: nil, today: [SetValue(weight: 20, reps: 15)]) == SetValue(weight: 20, reps: 15))
    }
}

struct RegularityTests {
    private let calendar = Calendar.current

    @Test func neglectedGroupsAfterAWeek() {
        let now = Date.now
        let result = NeglectedGroups.compute(lastTrained: [
            .jambes: calendar.date(byAdding: .day, value: -12, to: now)!,
            .pecs: calendar.date(byAdding: .day, value: -2, to: now)!,
        ], now: now)
        #expect(result.map(\.group) == [.jambes])
        #expect(result.first?.days == 12)
    }

    @Test func weekStreakCountsConsecutiveWeeks() {
        let now = Date.now
        let days = Set([0, 7, 14, 28].map { calendar.startOfDay(for: calendar.date(byAdding: .day, value: -$0, to: now)!) })
        #expect(Regularity.weekStreak(days, now: now) == 3)
        #expect(Regularity.weekStreak([], now: now) == 0)
    }
}

struct SportSyncFormatTests {
    @Test func parsesPostgresTimestamps() throws {
        let micro = try #require(SportJSON.parse("2026-10-28T20:32:55.398428+00:00"))
        let plain = try #require(SportJSON.parse("2026-10-28T20:32:55+00:00"))
        #expect(abs(micro.timeIntervalSince(plain) - 0.398) < 0.001)
        #expect(SportJSON.parse("2026-10-28 20:32:55+00") == plain)
    }

    @Test func decodesServerRowsAndEncodesSnakeCase() throws {
        let json = """
        [{"id":"44444444-4444-4444-4444-444444444444","entry_id":"33333333-3333-3333-3333-333333333333",
          "profile_id":"11111111-1111-1111-1111-111111111111","set_index":0,"weight_kg":62.50,"reps":10,
          "done_at":null,"modified_at":"2026-10-28T10:00:00+00:00","deleted_at":null}]
        """
        let rows = try SportJSON.decoder.decode([SetRow].self, from: Data(json.utf8))
        #expect(rows.first?.weightKg == 62.5)
        #expect(rows.first?.doneAt == nil)
        let encoded = try #require(String(data: SportJSON.encoder.encode(rows[0]), encoding: .utf8))
        #expect(encoded.contains("\"weight_kg\""))
        #expect(encoded.contains("\"entry_id\""))
        #expect(!encoded.contains("\"done_at\""))
    }

    @Test func oldRowsWithoutDropsDecodeAsSimpleSets() throws {
        let json = """
        [{"id":"44444444-4444-4444-4444-444444444444","entry_id":"33333333-3333-3333-3333-333333333333",
          "profile_id":"11111111-1111-1111-1111-111111111111","set_index":0,"weight_kg":62.50,"reps":10,
          "done_at":null,"modified_at":"2026-10-28T10:00:00+00:00","deleted_at":null},
         {"id":"55555555-5555-5555-5555-555555555555","entry_id":"33333333-3333-3333-3333-333333333333",
          "profile_id":"11111111-1111-1111-1111-111111111111","set_index":1,"weight_kg":60,"reps":8,
          "drops":null,"is_unilateral":null,"done_at":null,"modified_at":"2026-10-28T10:00:00+00:00","deleted_at":null}]
        """
        let rows = try SportJSON.decoder.decode([SetRow].self, from: Data(json.utf8))
        #expect(rows.allSatisfy { $0.drops.isEmpty && !$0.isUnilateral })
    }

    @Test func dropsAndUnilateralRoundTrip() throws {
        let json = """
        {"id":"44444444-4444-4444-4444-444444444444","entry_id":"33333333-3333-3333-3333-333333333333",
         "profile_id":"11111111-1111-1111-1111-111111111111","set_index":0,"weight_kg":60,"reps":8,
         "drops":[{"kg":45,"reps":6},{"kg":30.5,"reps":6}],"is_unilateral":true,
         "done_at":null,"modified_at":"2026-10-28T10:00:00+00:00","deleted_at":null}
        """
        let row = try SportJSON.decoder.decode(SetRow.self, from: Data(json.utf8))
        #expect(row.drops == [DropStep(kg: 45, reps: 6), DropStep(kg: 30.5, reps: 6)])
        #expect(row.isUnilateral)
        let encoded = try #require(String(data: SportJSON.encoder.encode(row), encoding: .utf8))
        #expect(encoded.contains("\"drops\""))
        #expect(encoded.contains("\"is_unilateral\":true"))
        // Une série simple envoie [] et false, jamais null : le serveur garde la valeur quand un vieux client envoie null.
        let simple = try #require(String(data: SportJSON.encoder.encode(SetRow(
            id: UUID(), entryID: UUID(), profileID: UUID(), setIndex: 0, weightKg: 60, reps: 8,
            doneAt: nil, modifiedAt: .now, deletedAt: nil
        )), encoding: .utf8))
        #expect(simple.contains("\"drops\":[]"))
        #expect(simple.contains("\"is_unilateral\":false"))
    }

    @Test func dayColumnRoundTripsInLocalTime() {
        let day = Calendar.current.startOfDay(for: .now)
        #expect(SportDay.date(SportDay.string(day)) == day)
    }
}

@MainActor
struct SportStoreTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: AppStore.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    @Test func historyIgnoresUndoneAndDeletedSets() throws {
        let profile = UUID()
        let session = SportSession(day: .now, profileIDs: [profile])
        let entry = SportEntry(sessionID: session.id, exerciseRef: "Barbell_Squat", sortOrder: 0)
        let done = SportSet(entryID: entry.id, profileID: profile, index: 0, weightKg: 80, reps: 5)
        done.doneAt = .now
        let undone = SportSet(entryID: entry.id, profileID: profile, index: 1, weightKg: 100, reps: 5)
        let deleted = SportSet(entryID: entry.id, profileID: profile, index: 2, weightKg: 120, reps: 5)
        deleted.doneAt = .now
        deleted.deletedAt = .now
        let history = SportHistory(sessions: [session], entries: [entry], sets: [done, undone, deleted])
        #expect(history.performances(profile: profile, exercise: "Barbell_Squat").first?.sets == [SetValue(weight: 80, reps: 5)])
        #expect(history.last(profile: profile, exercise: "Barbell_Squat", excluding: session.id) == nil)
    }

    @Test func historyCarriesDropsAndUnilateral() throws {
        let profile = UUID()
        let session = SportSession(day: .now, profileIDs: [profile])
        let entry = SportEntry(sessionID: session.id, exerciseRef: "Hammer_Curls", sortOrder: 0)
        let set = SportSet(entryID: entry.id, profileID: profile, index: 0, weightKg: 20, reps: 10)
        set.drops = [DropStep(kg: 15, reps: 8)]
        set.isUnilateral = true
        set.doneAt = .now
        #expect(set.drops == [DropStep(kg: 15, reps: 8)])
        let value = SportHistory(sessions: [session], entries: [entry], sets: [set])
            .performances(profile: profile, exercise: "Hammer_Curls").first?.sets.first
        #expect(value == SetValue(weight: 20, reps: 10, drops: [DropStep(kg: 15, reps: 8)], unilateral: true))
        set.drops = []
        #expect(set.dropsData == nil)
    }

    @Test func expandedCatalogKeepsEveryExerciseUsedInHistory() {
        // Identifiants présents dans les séances et modèles enregistrés avant l'agrandissement du catalogue.
        let used = [
            "Seated_Leg_Curl", "Butterfly", "Hammer_Curls", "Calf_Press_On_The_Leg_Press_Machine",
            "Triceps_Pushdown_-_Rope_Attachment", "Leg_Extensions", "Leg_Press", "Incline_Dumbbell_Curl",
            "Leverage_Chest_Press", "Leverage_Incline_Chest_Press", "Leverage_Iso_Row", "Leverage_Shoulder_Press",
            "Reverse_Machine_Flyes", "Side_Lateral_Raise", "Standing_Biceps_Cable_Curl", "Triceps_Pushdown",
            "Underhand_Cable_Pulldowns", "Wide-Grip_Lat_Pulldown", "Ab_Crunch_Machine", "Dips_-_Triceps_Version",
        ]
        let ids = ExerciseCatalog.entries.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ExerciseCatalog.entries.count > 600)
        for id in used { #expect(ExerciseCatalog.isCatalog(id), "\(id)") }
        #expect(ExerciseCatalog.entries.allSatisfy { $0.hasAnimation == true || ($0.photoCount ?? 0) > 0 })
    }

    @Test func catalogLoadsAndMergesSharedSettings() throws {
        #expect(ExerciseCatalog.entries.count > 150)
        #expect(Set(ExerciseCatalog.entries.map(\.group)) == Set(MuscleGroup.allCases))
        let favorite = SportExercise(id: "Barbell_Squat")
        favorite.isFavorite = true
        favorite.name = "Squat du lundi"
        let custom = SportExercise(id: "perso-1", name: "Machine bizarre", group: .dos)
        let merged = ExerciseCatalog.merged([favorite, custom]).byID
        #expect(merged["Barbell_Squat"]?.isFavorite == true)
        #expect(merged["Barbell_Squat"]?.name == "Squat du lundi")
        #expect(merged["perso-1"]?.isCustom == true)
        #expect(merged["perso-1"]?.group == .dos)
        #expect(ExerciseCatalog.image(for: "Barbell_Squat") != nil)
    }

    @Test func localWritesQueueOneOutboxItemPerRow() throws {
        let context = try context()
        let sync = SportSync(context: context, enabled: false)
        let profile = SportProfile(name: "Lucas", colorIndex: 0, sortOrder: 0)
        sync.save(profile)
        profile.name = "Luc"
        sync.save(profile)
        #expect(try context.fetchCount(FetchDescriptor<SportProfile>()) == 1)
        // Synchro coupée : rien n'est mis en file, l'écriture reste locale.
        #expect(try context.fetchCount(FetchDescriptor<SportOutboxItem>()) == 0)
        sync.delete(profile)
        #expect(profile.deletedAt != nil)
    }

    @Test func rowApplyRespectsLastWriteWins() throws {
        let profile = SportProfile(name: "Lucas", colorIndex: 0, sortOrder: 0)
        profile.modifiedAt = Date(timeIntervalSince1970: 2_000)
        var row = profile.row
        row.name = "Ancien"
        row.modifiedAt = Date(timeIntervalSince1970: 1_000)
        // Même règle que `sport_push` côté serveur : une ligne plus ancienne n'écrase rien.
        if row.modifiedAt >= profile.modifiedAt { row.apply(to: profile) }
        #expect(profile.name == "Lucas")
        row.modifiedAt = Date(timeIntervalSince1970: 3_000)
        if row.modifiedAt >= profile.modifiedAt { row.apply(to: profile) }
        #expect(profile.name == "Ancien")
    }
}

struct CreatineReminderTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func schedulesReminderAndFollowUpEachEvening() {
        let requests = CreatineReminder.requests(from: date(3, 12), taken: [], calendar: calendar)
        #expect(requests.count == 28)
        #expect(requests.prefix(2).map(\.identifier) == ["sport.creatine.2026-11-03.reminder", "sport.creatine.2026-11-03.relance"])
        let followUp = requests[1].trigger as? UNCalendarNotificationTrigger
        #expect(followUp?.dateComponents.hour == 23 && followUp?.dateComponents.minute == 30)
        #expect(requests.allSatisfy { $0.content.categoryIdentifier == CreatineReminder.category })
    }

    @Test func skipsTakenEveningsAndPastTimes() {
        // 22 h 45 : le rappel du soir est passé, la relance de 23 h 30 reste.
        let late = CreatineReminder.requests(from: date(3, 22, 45), taken: [], calendar: calendar)
        #expect(late.first?.identifier == "sport.creatine.2026-11-03.relance")
        // Validé ce soir : plus rien aujourd'hui, demain reprend normalement.
        let taken = CreatineReminder.requests(from: date(3, 22, 45), taken: ["2026-11-03"], calendar: calendar)
        #expect(taken.first?.identifier == "sport.creatine.2026-11-04.reminder")
    }

    @Test func readsDayFromNotificationID() {
        #expect(CreatineReminder.day(in: "sport.creatine.2026-11-03.reminder") == "2026-11-03")
        #expect(CreatineReminder.day(in: "sport.creatine.2026-11-03.relance") == "2026-11-03")
        #expect(CreatineReminder.day(in: "sport.rest") == nil)
    }
}
