import Foundation

enum OutputKind: String, Codable {
    case speaker, receiver, wired, bluetooth, other, unknown

    var title: String { L.t("route.\(rawValue)") }
    var isExternal: Bool { [.wired, .bluetooth, .other].contains(self) }
}

enum Hearing: String, Codable, CaseIterable, Identifiable {
    case clear, muffled, both, one, skip
    var id: Self { self }
    var title: String { L.t("hearing.\(rawValue)") }
}

struct ListeningConditions: Codable, Equatable {
    let output: OutputKind
    let volume: Int

    var text: String {
        volume < 0 ? L.f("history.changedVolume", output.title) : L.f("history.conditions", output.title, volume)
    }
}

struct CheckSession: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    let check: SoundCheck
    let conditions: ListeningConditions
    var hearing: Hearing
}

struct ListeningComparison: Codable, Identifiable, Equatable {
    var id = UUID()
    let before: CheckSession
    let after: CheckSession

    var sameConditions: Bool {
        before.check == after.check && before.conditions.volume >= 0 && before.conditions == after.conditions
    }

    var exportText: String {
        [
            L.t("history.comparison"),
            L.f("history.exportLine", L.t("history.before"), before.hearing.title, before.conditions.text),
            L.f("history.exportLine", L.t("history.after"), after.hearing.title, after.conditions.text),
            L.t(sameConditions ? "history.same" : "history.different")
        ].joined(separator: "\n")
    }

    static var example: Self {
        let conditions = ListeningConditions(output: .speaker, volume: 35)
        return Self(before: CheckSession(check: .speaker, conditions: conditions, hearing: .muffled),
                    after: CheckSession(check: .speaker, conditions: conditions, hearing: .clear))
    }
}

struct Milestones: Codable {
    private(set) var checks: Set<SoundCheck> = []
    private(set) var days: Set<Date> = []
    private(set) var ratingRequested = false
    private(set) var checklistShown = false
    var completedChecklist: Bool { checks == Set(SoundCheck.allCases) }

    mutating func complete(_ check: SoundCheck?, at now: Date = Date(), calendar: Calendar = .current) {
        if let check { checks.insert(check) }
        let day = calendar.startOfDay(for: now)
        if days.count < 2, !days.contains(where: { calendar.isDate($0, inSameDayAs: day) }) {
            days.insert(day)
        }
    }

    mutating func markChecklistShown() -> Bool {
        guard completedChecklist, !checklistShown else { return false }
        checklistShown = true
        return true
    }

    mutating func claimRating(idle: Bool, shared: Bool) -> Bool {
        guard idle, shared, days.count >= 2, !ratingRequested else { return false }
        ratingRequested = true
        return true
    }
}
