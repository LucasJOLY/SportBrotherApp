import Foundation

nonisolated enum WeekCalendar {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    /// Lundi 00:00 de la semaine contenant `date`.
    static func monday(of date: Date) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    /// 0 = lundi … 6 = dimanche.
    static func dayIndex(of date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    static func weekNumber(of date: Date) -> Int {
        calendar.component(.weekOfYear, from: date)
    }

    static func dayName(_ day: Int) -> String {
        ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"][day]
    }

    static func rangeLabel(weekStart: Date) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let format = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))
        return "\(weekStart.formatted(format)) – \(end.formatted(format))"
    }
}
