import Foundation

struct CoreReviewProgress: Codable, Equatable, Sendable {
    private var count = 0
    private var localDays: Set<String> = []

    private enum CodingKeys: String, CodingKey { case count, localDays }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        count = try values.decodeIfPresent(Int.self, forKey: .count) ?? 0
        localDays = try values.decodeIfPresent(Set<String>.self, forKey: .localDays) ?? []
    }

    var isEligible: Bool { count >= 3 && localDays.count >= 2 }

    static func recording(_ previous: Self?, at date: Date = .now, calendar: Calendar = .current) -> Self {
        var next = previous ?? Self()
        next.record(at: date, calendar: calendar)
        return next
    }

    mutating func record(at date: Date, calendar: Calendar = .current) {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = calendar.timeZone
        let parts = localCalendar.dateComponents([.era, .year, .month, .day], from: date)
        guard let era = parts.era, let year = parts.year, let month = parts.month, let day = parts.day else { return }
        if count < Int.max { count += 1 }
        localDays.insert("\(era)-\(year)-\(month)-\(day)")
    }
}
