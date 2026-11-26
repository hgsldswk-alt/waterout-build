import Foundation

private final class LocalizationBundle {}

enum L {
    static func t(_ key: String) -> String {
        NSLocalizedString(key, bundle: Bundle(for: LocalizationBundle.self), comment: "")
    }

    static func f(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), locale: Locale.current, arguments: arguments)
    }
}
