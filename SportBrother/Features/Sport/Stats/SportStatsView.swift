import Charts
import SwiftData
import SwiftUI

struct SportStatsView: View {
    @Environment(SportSync.self) private var sync
    @Environment(\.modelContext) private var context
    @Query private var sessions: [SportSession]
    @Query private var entries: [SportEntry]
    @Query private var sets: [SportSet]
    @Query private var profiles: [SportProfile]
    @Query private var overrides: [SportExercise]
    @Query(sort: \SportBodyWeight.day) private var weights: [SportBodyWeight]
    @Query private var reviews: [SportCoachReview]
    @AppStorage(myProfileKey) private var myProfileID = ""
    @State private var profileID: UUID?
    @State private var reviewing = false
    @State private var reviewError: String?
    @State private var path = NavigationPath()

    private var profile: SportProfile? {
        profiles.live.first { $0.id == profileID } ?? profiles.live.first { $0.id.uuidString == myProfileID } ?? profiles.live.first
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let profile {
                    content(profile)
                } else {
                    ContentUnavailableView("Aucun profil", systemImage: "person.2")
                }
            }
            .navigationTitle("Stats")
            #if DEBUG
            .task {
                // Captures d'écran : `-debugSportExercise <id>` ouvre la progression de cet exo.
                if let id = UserDefaults.standard.string(forKey: "debugSportExercise"), path.isEmpty { path.append(id) }
            }
            #endif
            .navigationDestination(for: MuscleGroup.self) { group in
                if let profile { GroupExercisesView(group: group, profileID: profile.id) }
            }
            .navigationDestination(for: String.self) { exerciseID in
                if let profile { ExerciseProgressView(exerciseID: exerciseID, profileID: profile.id) }
            }
        }
    }

    private func content(_ profile: SportProfile) -> some View {
        let history = SportHistory(sessions: sessions, entries: entries, sets: sets)
        let exercises = ExerciseCatalog.merged(overrides).byID
        let days = history.days[profile.id] ?? []
        let year = days.filter { Calendar.current.isDate($0, equalTo: .now, toGranularity: .year) }
        let done = history.exercises(profile: profile.id)
        return List {
            if profiles.live.count > 1 {
                Section {
                    Picker("Profil", selection: Binding(get: { profile.id }, set: { profileID = $0 })) {
                        ForEach(profiles.live) { Text($0.name).tag($0.id) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }

            Section {
                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    StatFigure(value: "\(year.count)", label: "séances en \(Date.now.formatted(.dateTime.year()))")
                    StatFigure(value: "\(Regularity.weekStreak(days))", label: "semaines d'affilée")
                    StatFigure(value: Format.number((Regularity.perWeek(days) * 10).rounded() / 10), label: "par semaine")
                }
                .padding(.vertical, 6)
                YearHeatmap(days: days, color: profile.color)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 12, trailing: 0))
            }

            Section("Par groupe") {
                ForEach(MuscleGroup.allCases) { group in
                    let count = done.filter { exercises[$0]?.group == group }.count
                    NavigationLink(value: group) {
                        LabeledContent {
                            Text(count == 0 ? "—" : "\(count) exo\(count > 1 ? "s" : "")").monospacedDigit()
                        } label: {
                            Label(group.label, systemImage: group.symbol)
                        }
                    }
                    .disabled(count == 0)
                }
            }

            reviewSection(profile, history: history, exercises: exercises, days: days)
        }
        .refreshable { await sync.refresh() }
    }

    // MARK: Bilan IA

    private func reviewSection(_ profile: SportProfile, history: SportHistory, exercises: [String: ExerciseInfo], days: Set<Date>) -> some View {
        let month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
        let current = reviews.first { $0.profileID == profile.id && $0.deletedAt == nil && Calendar.current.isDate($0.month, equalTo: month, toGranularity: .month) }
        return Section {
            if let review = current?.review {
                VStack(alignment: .leading, spacing: 10) {
                    Text(review.headline).font(.headline)
                    ForEach(review.tips, id: \.self) { tip in
                        Label {
                            Text(tip)
                        } icon: {
                            Image(systemName: "checkmark.circle").foregroundStyle(.tint)
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.vertical, 4)
            } else if AIService(context: context).isAvailable {
                Button {
                    Task { await askReview(profile, history: history, exercises: exercises, days: days, month: month) }
                } label: {
                    HStack {
                        Label("Demander le bilan du mois", systemImage: "sparkles")
                        Spacer()
                        if reviewing { ProgressView() }
                    }
                }
                .disabled(reviewing || days.isEmpty)
                if let reviewError {
                    Text(reviewError).font(.footnote).foregroundStyle(.red)
                }
            }
        } header: {
            Text("Bilan du mois")
        } footer: {
            if current == nil { Text("Claude commente tes chiffres du mois en 3 conseils. Un bilan par mois, visible sur tous les téléphones.") }
        }
    }

    private func askReview(_ profile: SportProfile, history: SportHistory, exercises: [String: ExerciseInfo], days: Set<Date>, month: Date) async {
        reviewing = true
        reviewError = nil
        defer { reviewing = false }
        let now = Date.now
        let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let twoMonthsAgo = Calendar.current.date(byAdding: .day, value: -60, to: now) ?? now
        var groupSessions: [MuscleGroup: Set<UUID>] = [:]
        var trends: [CoachSummary.ExerciseTrend] = []
        for exerciseID in history.exercises(profile: profile.id) {
            guard let exercise = exercises[exerciseID] else { continue }
            let all = history.performances(profile: profile.id, exercise: exerciseID)
            for performance in all where performance.day > monthAgo { groupSessions[exercise.group, default: []].insert(performance.sessionID) }
            let recent = all.filter { $0.day > twoMonthsAgo }.compactMap { p in p.best.map { StrengthStats.oneRepMax($0) } }
            if let first = recent.first, let last = recent.last, recent.count >= 2, last > 0 {
                trends.append(.init(name: exercise.name, group: exercise.group, sessions: recent.count, first: first, last: last))
            }
        }
        let mine = weights.filter { $0.profileID == profile.id && $0.deletedAt == nil }
        let bodyWeight = mine.last.map { last in
            (now: last.kg, delta: last.kg - (mine.first { $0.day > twoMonthsAgo }?.kg ?? last.kg))
        }
        let summary = CoachSummary.make(
            name: profile.name,
            days: days,
            groupSessions: groupSessions.mapValues(\.count),
            trends: trends.sorted { $0.sessions > $1.sessions },
            neglected: NeglectedGroups.compute(lastTrained: history.lastTrained(profile: profile.id, groups: exercises.mapValues(\.group))),
            bodyWeight: bodyWeight
        )
        do {
            let review = try await AIService(context: context).sportReview(summary: summary)
            let payload = try JSONEncoder().encode(review)
            sync.save(SportCoachReview(profileID: profile.id, month: month, payload: payload))
        } catch {
            reviewError = error.localizedDescription
        }
    }
}

struct StatFigure: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.display(.title))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Grille d'une année glissante : une colonne par semaine, une case par jour, pleine les jours de séance.
struct YearHeatmap: View {
    let days: Set<Date>
    let color: Color
    private let cell: CGFloat = 12
    private let gap: CGFloat = 3

    private var weeks: [[Date]] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return (0..<53).reversed().map { back in
            let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek) ?? thisWeek
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        }
    }

    var body: some View {
        let today = Calendar.current.startOfDay(for: .now)
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: gap) {
                    ForEach(weeks, id: \.first) { week in
                        let first = week.first ?? today
                        Text(Calendar.current.component(.day, from: first) <= 7 ? first.formatted(.dateTime.month(.narrow)) : " ")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: cell, alignment: .leading)
                            .fixedSize()
                    }
                }
                HStack(alignment: .top, spacing: gap) {
                    ForEach(weeks, id: \.first) { week in
                        VStack(spacing: gap) {
                            ForEach(week, id: \.self) { day in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(fill(day, today: today))
                                    .frame(width: cell, height: cell)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .defaultScrollAnchor(.trailing)
        .scrollIndicators(.hidden)
        .accessibilityElement()
        .accessibilityLabel("Régularité sur un an")
        .accessibilityValue("\(days.filter { $0 > .now.addingTimeInterval(-365 * 86400) }.count) jours de séance")
    }

    private func fill(_ day: Date, today: Date) -> AnyShapeStyle {
        if day > today { return AnyShapeStyle(.clear) }
        return days.contains(day) ? AnyShapeStyle(color.gradient) : AnyShapeStyle(.quaternary)
    }
}

/// Exos pratiqués dans un groupe, du plus fréquent au moins fréquent.
struct GroupExercisesView: View {
    let group: MuscleGroup
    let profileID: UUID
    @Query private var sessions: [SportSession]
    @Query private var entries: [SportEntry]
    @Query private var sets: [SportSet]
    @Query private var overrides: [SportExercise]

    var body: some View {
        let history = SportHistory(sessions: sessions, entries: entries, sets: sets)
        let exercises = ExerciseCatalog.merged(overrides).byID
        let rows = history.exercises(profile: profileID)
            .compactMap { id in exercises[id].map { ($0, history.performances(profile: profileID, exercise: id)) } }
            .filter { $0.0.group == group }
            .sorted { $0.1.count > $1.1.count }
        List(rows, id: \.0.id) { exercise, performances in
            NavigationLink(value: exercise.id) {
                ExerciseRowLabel(
                    exercise: exercise,
                    detail: "\(performances.count) séance\(performances.count > 1 ? "s" : "")"
                        + (performances.last?.best.map { " · dernier \($0.label)" } ?? "")
                )
            }
        }
        .navigationTitle(group.label)
    }
}
