import Foundation

/// Interpolation is preserved until after lookup, so translations may reorder values.
struct LocalizedMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    let key: String
    let arguments: [String]

    init(stringLiteral value: String) {
        key = value
        arguments = []
    }

    init(stringInterpolation: Interpolation) {
        key = stringInterpolation.key
        arguments = stringInterpolation.arguments
    }

    struct Interpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []

        init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity + interpolationCount * 3)
            arguments.reserveCapacity(interpolationCount)
        }

        mutating func appendLiteral(_ literal: String) { key += literal }

        mutating func appendInterpolation<T>(_ value: T) {
            key += "{\(arguments.count)}"
            arguments.append(String(describing: value))
        }
    }
}

enum L10n {
    static let supported = ["zh-Hans", "zh-Hant", "en", "ja", "ru", "ko", "es"]
    private static let lock = NSLock()
    private static var selected = "system"
    private static var cachedLanguage = "zh-Hans"
    private static var cachedBundle: Bundle = .main

    static func configure(_ selection: String) {
        lock.lock()
        defer { lock.unlock() }
        selected = supported.contains(selection) ? selection : "system"
        updateBundle()
    }

    static func systemLanguageDidChange() {
        lock.lock()
        defer { lock.unlock() }
        if selected == "system" { updateBundle() }
    }

    static var language: String {
        lock.lock()
        defer { lock.unlock() }
        return cachedLanguage
    }

    static var locale: Locale { Locale(identifier: language) }

    static func displayName(for language: String) -> String {
        switch language {
        case "zh-Hans": "简体中文"
        case "zh-Hant": "繁體中文"
        case "en": "English"
        case "ja": "日本語"
        case "ru": "Русский"
        case "ko": "한국어"
        case "es": "Español"
        default: "简体中文"
        }
    }

    static func tr(_ message: LocalizedMessage) -> String {
        lookup(message.key, arguments: message.arguments)
    }

    static func lookup(_ key: String) -> String { lookup(key, arguments: []) }

    private static func lookup(_ key: String, arguments: [String]) -> String {
        lock.lock()
        let bundle = cachedBundle
        lock.unlock()
        var result = bundle.localizedString(forKey: key, value: key, table: "Localizable")
        // Replace indices in reverse order so {1} cannot alter an inserted {0} value.
        for index in arguments.indices.reversed() {
            result = result.replacingOccurrences(of: "{\(index)}", with: arguments[index])
        }
        return result
    }

    private static func updateBundle() {
        let resolved = selected == "system" ? preferredLanguage(Locale.preferredLanguages) : selected
        cachedLanguage = resolved
        if let path = Bundle.main.path(forResource: resolved, ofType: "lproj"), let bundle = Bundle(path: path) {
            cachedBundle = bundle
        } else {
            cachedBundle = .main
        }
    }

    static func preferredLanguage(_ preferences: [String]) -> String {
        for item in preferences {
            let normalized = item.replacingOccurrences(of: "_", with: "-").lowercased()
            if normalized.hasPrefix("zh") {
                if normalized.contains("hant") || normalized.contains("-tw") || normalized.contains("-hk") || normalized.contains("-mo") {
                    return "zh-Hant"
                }
                return "zh-Hans"
            }
            if let language = supported.first(where: { normalized == $0.lowercased() || normalized.hasPrefix($0.lowercased() + "-") }) {
                return language
            }
        }
        return "zh-Hans"
    }
}
