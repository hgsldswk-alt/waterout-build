import Foundation

enum Launch {
    static let freePeriod = true
    static var arguments: [String] { ProcessInfo.processInfo.arguments }
    static var testing: Bool { arguments.contains("-ui-testing") }
}
