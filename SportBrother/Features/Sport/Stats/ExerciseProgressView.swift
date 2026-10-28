import Charts
import SwiftData
import SwiftUI

/// Progression d'un profil sur un exo : records par nombre de reps, 1RM estimé et poids de corps sur le même axe de temps.
struct ExerciseProgressView: View {
    let exerciseID: String
    let profileID: UUID
    @Query private var sessions: [SportSession]
    @Query private var entries: [SportEntry]
    @Query private var sets: [SportSet]
    @Query private var profiles: [SportProfile]
    @Query private var overrides: [SportExercise]
    @Query(sort: \SportBodyWeight.day) private var allWeights: [SportBodyWeight]

    private struct Point: Identifiable {
        let day: Date
        let value: Double
        var id: Date { day }
    }

    var body: some View {
        let history = SportHistory(sessions: sessions, entries: entries, sets: sets)
        let performances = history.performances(profile: profileID, exercise: exerciseID)
        let exercise = ExerciseCatalog.merged(overrides).byID[exerciseID]
        let color = profiles.first { $0.id == profileID }?.color ?? .orange
        let isBodyweight = performances.allSatisfy { $0.topWeight == 0 }
        let strength = performances.compactMap { performance in
            performance.best.map {
                Point(day: performance.day, value: isBodyweight ? Double($0.reps) : StrengthStats.oneRepMax($0))
            }
        }
        let loads = isBodyweight ? [] : performances.compactMap { performance in
            StrengthStats.workingMax(performance).map { Point(day: performance.day, value: $0) }
        }
        let bestLoad = loads.max { $0.value < $1.value }
        let weights = allWeights.filter { $0.profileID == profileID && $0.deletedAt == nil }.map { Point(day: $0.day, value: $0.kg) }
        let domain = timeDomain(strength.map(\.day))
        let records = StrengthStats.records(performances)

        ScrollViewReader { proxy in
        List {
            if let exercise {
                Section { ExerciseHero(exercise: exercise).listRowInsets(EdgeInsets()) }
            }

            if !records.isEmpty {
                Section {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                        GridRow {
                            Text("Reps").gridColumnAlignment(.leading)
                            Text("Record").gridColumnAlignment(.trailing)
                            Text("Le").gridColumnAlignment(.trailing)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        ForEach(records, id: \.reps) { record in
                            GridRow {
                                Text(record.reps == 1 ? "1 rep" : "\(record.reps) reps")
                                Text(Format.kg(record.weight)).font(.body.weight(.semibold))
                                Text(record.day.formatted(.dateTime.day().month(.abbreviated)))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .monospacedDigit()
                    .padding(.vertical, 4)
                    if let best = strength.map(\.value).max(), !isBodyweight {
                        LabeledContent("1RM estimé", value: Format.kg((best * 2).rounded() / 2))
                            .monospacedDigit()
                    }
                } header: {
                    Text("Records")
                } footer: {
                    Text("Meilleure charge réussie pour au moins ce nombre de reps. 1RM estimé avec la formule d'Epley.")
                }
            }

            if strength.count > 1 {
                Section {
                    Chart {
                        ForEach(strength) { point in
                            LineMark(x: .value("Jour", point.day), y: .value("kg", point.value), series: .value("Mesure", Self.oneRepMaxLabel))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(by: .value("Mesure", isBodyweight ? Self.repsLabel : Self.oneRepMaxLabel))
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: isBodyweight ? [] : [5, 4]))
                        }
                        ForEach(loads) { point in
                            LineMark(x: .value("Jour", point.day), y: .value("kg", point.value), series: .value("Mesure", Self.loadLabel))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(by: .value("Mesure", Self.loadLabel))
                                .lineStyle(StrokeStyle(lineWidth: 2.5))
                            PointMark(x: .value("Jour", point.day), y: .value("kg", point.value))
                                .symbolSize(24)
                                .foregroundStyle(by: .value("Mesure", Self.loadLabel))
                        }
                    }
                    .chartForegroundStyleScale(isBodyweight
                        ? [Self.repsLabel: color]
                        : [Self.loadLabel: color, Self.oneRepMaxLabel: color.opacity(0.55)])
                    .chartLegend(isBodyweight ? .hidden : .visible)
                    .chartLegend(position: .top, alignment: .leading)
                    .chartXScale(domain: domain)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 200)
                    .padding(.vertical, 8)
                    .accessibilityLabel(isBodyweight ? "Évolution des répétitions" : "Évolution de la charge max et du 1RM estimé")

                    if let bestLoad {
                        LabeledContent("Charge max (\(StrengthStats.workingReps) reps ou +)") {
                            HStack(spacing: 6) {
                                Text(Format.kg(bestLoad.value)).fontWeight(.semibold)
                                Text(bestLoad.day.formatted(.dateTime.day().month(.abbreviated))).foregroundStyle(.secondary)
                            }
                        }
                        .monospacedDigit()
                    }

                    let bodyWeights = weights.filter { domain.contains($0.day) }
                    if bodyWeights.count > 1 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Poids de corps")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Chart(bodyWeights) { point in
                                LineMark(x: .value("Jour", point.day), y: .value("Poids", point.value))
                                    .interpolationMethod(.monotone)
                                    .foregroundStyle(.secondary)
                            }
                            .chartXScale(domain: domain)
                            .chartYScale(domain: .automatic(includesZero: false))
                            .frame(height: 90)
                            .accessibilityLabel("Évolution du poids de corps")
                        }
                        .padding(.bottom, 8)
                    }

                    if !isBodyweight, let last = strength.last, let body = weights.last(where: { $0.day <= last.day }) ?? weights.first {
                        LabeledContent("Force relative") {
                            Text("\(Format.number((last.value / body.value * 100).rounded() / 100)) × ton poids")
                        }
                        .monospacedDigit()
                    }
                } header: {
                    Text(isBodyweight ? "Reps au fil du temps" : "Force au fil du temps").id("force")
                } footer: {
                    if !isBodyweight {
                        Text("Trait plein : la plus lourde charge réussie sur au moins \(StrengthStats.workingReps) reps à chaque séance. Pointillés : 1RM estimé.")
                    }
                }
            }

            ProfileComparison(exerciseID: exerciseID, history: history, profiles: profiles.live, weights: allWeights, isBodyweight: isBodyweight)
                .id("compare")

            ExerciseHistorySection(exerciseID: exerciseID, profileID: profileID, history: history, profiles: profiles.live)
                .id("history")
        }
        .navigationTitle(exercise?.name ?? "Exo")
        .navigationBarTitleDisplayMode(.inline)
        #if DEBUG
        .task {
            // Captures d'écran : `-debugScrollTo compare` descend jusqu'à la comparaison.
            if let target = UserDefaults.standard.string(forKey: "debugScrollTo") {
                try? await Task.sleep(for: .milliseconds(600))
                proxy.scrollTo(target, anchor: .top)
            }
        }
        #endif
        }
    }

    private static let oneRepMaxLabel = "1RM estimé"
    private static let loadLabel = "Charge max"
    private static let repsLabel = "Reps"

    private func timeDomain(_ days: [Date]) -> ClosedRange<Date> {
        guard let first = days.min(), let last = days.max(), first < last else {
            let now = Date.now
            return now.addingTimeInterval(-30 * 86400)...now
        }
        return first...last
    }
}

/// Une courbe par profil sur le même exo. Rapportée au poids de corps, la comparaison reste juste entre gabarits différents.
private struct ProfileComparison: View {
    let exerciseID: String
    let history: SportHistory
    let profiles: [SportProfile]
    let weights: [SportBodyWeight]
    let isBodyweight: Bool
    @State private var metric = Metric.load

    enum Metric: String, CaseIterable, Identifiable {
        case load = "Charge max", oneRepMax = "1RM", relative = "× poids"
        var id: String { rawValue }
    }

    private struct Point: Identifiable {
        let profile: String
        let day: Date
        let value: Double
        var id: String { "\(profile)-\(day.timeIntervalSince1970)" }
    }

    private struct Summary: Identifiable {
        let profile: SportProfile
        let best: Double
        let change: Double?
        var id: UUID { profile.id }
    }

    private var activeMetric: Metric { isBodyweight ? .load : metric }

    private func points(for profile: SportProfile) -> [Point] {
        let weighIns = weights.filter { $0.profileID == profile.id && $0.deletedAt == nil }.map { (day: $0.day, kg: $0.kg) }
        return history.performances(profile: profile.id, exercise: exerciseID).compactMap { performance in
            let value: Double?
            if isBodyweight {
                value = performance.sets.map { Double($0.reps) }.max()
            } else {
                switch activeMetric {
                case .load: value = StrengthStats.workingMax(performance)
                case .oneRepMax: value = performance.best.map(StrengthStats.oneRepMax)
                case .relative:
                    value = performance.best.map(StrengthStats.oneRepMax).flatMap { strength in
                        StrengthStats.bodyWeight(on: performance.day, weighIns: weighIns).map { strength / $0 }
                    }
                }
            }
            return value.map { Point(profile: profile.name, day: performance.day, value: $0) }
        }
    }

    var body: some View {
        let series = profiles.map { ($0, points(for: $0)) }.filter { !$0.1.isEmpty }
        let compared = profiles.filter { profile in !history.performances(profile: profile.id, exercise: exerciseID).isEmpty }
        if compared.count > 1 {
            Section {
                if !isBodyweight {
                    Picker("Mesure", selection: $metric) {
                        ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                }

                if series.count > 1 {
                    Chart {
                        ForEach(series, id: \.0.id) { profile, points in
                            ForEach(points) { point in
                                LineMark(x: .value("Jour", point.day), y: .value("Valeur", point.value), series: .value("Profil", point.profile))
                                    .interpolationMethod(.monotone)
                                    .foregroundStyle(by: .value("Profil", point.profile))
                                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                                PointMark(x: .value("Jour", point.day), y: .value("Valeur", point.value))
                                    .symbolSize(20)
                                    .foregroundStyle(by: .value("Profil", point.profile))
                            }
                        }
                    }
                    .chartForegroundStyleScale(domain: series.map(\.0.name), range: series.map(\.0.color))
                    .chartLegend(position: .top, alignment: .leading)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel { Text(axisLabel(value.as(Double.self) ?? 0)) }
                        }
                    }
                    .frame(height: 200)
                    .padding(.vertical, 8)
                    .animation(.snappy, value: metric)
                    .accessibilityLabel("Comparaison des profils, \(activeMetric.rawValue)")
                } else {
                    Text("Ajoute des pesées aux profils pour comparer la force rapportée au poids de corps.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ForEach(summaries(series)) { summary in
                    HStack(spacing: 10) {
                        ProfileAvatar(profile: summary.profile, size: 26)
                        Text(summary.profile.name)
                        Spacer()
                        if let change = summary.change {
                            Text("\(change >= 0 ? "+" : "−")\(Int(abs(change).rounded())) %")
                                .font(.subheadline)
                                .foregroundStyle(change > 0 ? .green : .secondary)
                        }
                        Text(valueLabel(summary.best))
                            .font(.body.weight(.semibold))
                            .frame(minWidth: 70, alignment: .trailing)
                    }
                    .monospacedDigit()
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Comparer")
            } footer: {
                Text(footer)
            }
        }
    }

    /// Meilleure valeur et progression entre la première et la dernière séance, du plus fort au moins fort.
    private func summaries(_ series: [(SportProfile, [Point])]) -> [Summary] {
        series.map { profile, points in
            let change: Double? = {
                guard let first = points.first?.value, let last = points.last?.value, points.count > 1, first > 0 else { return nil }
                return (last - first) / first * 100
            }()
            return Summary(profile: profile, best: points.map(\.value).max() ?? 0, change: change)
        }
        .sorted { $0.best > $1.best }
    }

    private func valueLabel(_ value: Double) -> String {
        if isBodyweight { return "\(Int(value)) reps" }
        switch activeMetric {
        case .relative: return "× \(Format.number((value * 100).rounded() / 100))"
        case .load, .oneRepMax: return Format.kg((value * 2).rounded() / 2)
        }
    }

    private func axisLabel(_ value: Double) -> String {
        if isBodyweight { return "\(Int(value))" }
        return activeMetric == .relative ? "×\(Format.number((value * 10).rounded() / 10))" : "\(Int(value))"
    }

    private var footer: String {
        if isBodyweight { return "Meilleure série de chaque séance, en reps. À droite : record et progression depuis la première séance." }
        switch activeMetric {
        case .load: return "Plus lourde charge réussie sur au moins \(StrengthStats.workingReps) reps, à chaque séance. À droite : record et progression depuis la première séance."
        case .oneRepMax: return "1RM estimé de la meilleure série de chaque séance."
        case .relative: return "1RM estimé divisé par le poids de corps du jour : la comparaison la plus juste entre deux gabarits."
        }
    }
}

/// Historique de l'exo, pour le profil affiché ou pour tout le monde. Les 10 plus récents, puis « Tout afficher ».
private struct ExerciseHistorySection: View {
    let exerciseID: String
    let profileID: UUID
    let history: SportHistory
    let profiles: [SportProfile]
    @State private var everyone = false
    @State private var expanded = false

    private static let preview = 10

    private struct Row: Identifiable {
        let profile: SportProfile
        let performance: Performance
        var id: String { "\(profile.id)-\(performance.sessionID)" }
    }

    private var rows: [Row] {
        let shown = everyone ? profiles : profiles.filter { $0.id == profileID }
        return shown
            .flatMap { profile in history.performances(profile: profile.id, exercise: exerciseID).map { Row(profile: profile, performance: $0) } }
            .sorted { ($0.performance.day, $0.profile.sortOrder) > ($1.performance.day, $1.profile.sortOrder) }
    }

    var body: some View {
        let all = rows
        let visible = expanded ? all : Array(all.prefix(Self.preview))
        let othersDidIt = profiles.contains { $0.id != profileID && !history.performances(profile: $0.id, exercise: exerciseID).isEmpty }
        Section {
            if othersDidIt {
                Picker("Profils", selection: $everyone) {
                    Text(profiles.first { $0.id == profileID }?.name ?? "Moi").tag(false)
                    Text("Tout le monde").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
            }
            ForEach(visible) { row in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if everyone {
                        ProfileAvatar(profile: row.profile, size: 22)
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                    }
                    Text(row.performance.day.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)))
                    Spacer(minLength: 12)
                    Text(row.performance.sets.map(\.label).joined(separator: "  "))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .monospacedDigit()
                .accessibilityElement(children: .combine)
            }
            if all.count > Self.preview {
                Button(expanded ? "Afficher moins" : "Tout afficher (\(all.count))") {
                    withAnimation(.snappy) { expanded.toggle() }
                }
            }
        } header: {
            Text("Historique")
        }
        .animation(.snappy, value: everyone)
    }
}
