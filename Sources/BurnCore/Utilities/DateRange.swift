import Foundation

public enum DateRange {
    public static func parseDateRange(startInput: String?, endInput: String?) throws -> (start: String, end: String?) {
        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"

        let (startStr, autoEnd): (String, String?) = try {
            guard let input = startInput else {
                let now = Date()
                let comps = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: now)
                guard let year = comps.year, let month = comps.month else {
                    throw BurnError.message("Failed to create start of current month")
                }
                let start = try firstDay(year: year, month: month)
                let end = try lastDayOfMonth(year: year, month: month)
                return (formatter.string(from: start), formatter.string(from: end))
            }

            let parts = input.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
            switch parts.count {
                case 1:
                    guard let year = Int(parts[0]) else { throw BurnError.message("Invalid year format") }
                    let start = try firstDay(year: year, month: 1)
                    var endComps = DateComponents()
                    endComps.year = year
                    endComps.month = 12
                    endComps.day = 31
                    guard let end = calendar.date(from: endComps) else { throw BurnError.message("Invalid year") }
                    return (formatter.string(from: start), formatter.string(from: end))
                case 2:
                    guard let year = Int(parts[0]), let month = Int(parts[1]) else {
                        throw BurnError.message("Invalid year-month format")
                    }
                    let start = try firstDay(year: year, month: month)
                    let end = try lastDayOfMonth(year: year, month: month)
                    return (formatter.string(from: start), formatter.string(from: end))
                case 3:
                    guard let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
                        throw BurnError.message("Invalid date format")
                    }
                    var comps = DateComponents()
                    comps.year = year
                    comps.month = month
                    comps.day = day
                    guard let start = calendar.date(from: comps) else { throw BurnError.message("Invalid date") }
                    return (formatter.string(from: start), nil)
                default:
                    throw BurnError.message("Invalid date format. Use YYYY, YYYY-MM, or YYYY-MM-DD")
            }
        }()

        return (startStr, endInput ?? autoEnd)
    }

    public static func lastDayOfMonth(year: Int, month: Int) throws -> Date {
        let calendar = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = month == 12 ? year + 1 : year
        comps.month = month == 12 ? 1 : month + 1
        comps.day = 1
        guard let nextMonth = calendar.date(from: comps),
            let last = calendar.date(byAdding: .day, value: -1, to: nextMonth)
        else {
            throw BurnError.message("Failed to get last day of month")
        }
        return last
    }

    public static func exclusiveDayAfter(end: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: end),
            let next = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: date)
        else {
            throw BurnError.message("Invalid end date: \(end)")
        }
        return next
    }

    public static func inclusiveEndToRFC3339(end: String) throws -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let next = try exclusiveDayAfter(end: end)
        return "\(formatter.string(from: next))T00:00:00Z"
    }

    public static func startToRFC3339(start: String) throws -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard formatter.date(from: start) != nil else {
            throw BurnError.message("Invalid start date: \(start)")
        }
        return "\(start)T00:00:00Z"
    }

    public static func rfc3339DatePart(_ timestamp: String) -> String {
        timestamp.split(separator: "T", maxSplits: 1).first.map(String.init) ?? timestamp
    }

    public static func dateRangeToUnix(start: String, end: String?) throws -> (start: Int64, end: Int64?) {
        let startTs = try dateToUnix(start)
        let endTs = try end.map { try dateToUnix(formatterString(from: try exclusiveDayAfter(end: $0))) }
        return (startTs, endTs)
    }

    private static func dateToUnix(_ dateStr: String) throws -> Int64 {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else {
            throw BurnError.message("Invalid date: \(dateStr)")
        }
        return Int64(date.timeIntervalSince1970)
    }

    private static func formatterString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func firstDay(year: Int, month: Int) throws -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let date = Calendar(identifier: .gregorian).date(from: comps) else {
            throw BurnError.message("Invalid year-month combination")
        }
        return date
    }
}
