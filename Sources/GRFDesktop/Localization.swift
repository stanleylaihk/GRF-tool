import Foundation
import Observation

public enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case english = "en", traditionalChinese = "zh-Hant", japanese = "ja", korean = "ko"
    public var id: String { rawValue }
    public var nativeName: String {
        switch self {
        case .english: return "English"
        case .traditionalChinese: return "繁體中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        }
    }
    public var locale: Locale { Locale(identifier: rawValue) }
}

@Observable public final class InterfaceLocalization {
    public static let preferenceKey = "grf.interfaceLanguage"
    public static let shared = InterfaceLocalization()
    private let defaults: UserDefaults
    public var language: InterfaceLanguage {
        didSet { defaults.set(language.rawValue, forKey: Self.preferenceKey) }
    }
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = defaults.string(forKey: Self.preferenceKey).flatMap(InterfaceLanguage.init(rawValue:)) ?? .english
    }
}

/// Stable English templates keep interpolation separate from translated text.
public struct LocalizedMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    public let key: String
    public let arguments: [String]
    public init(stringLiteral value: String) { key = value; arguments = [] }
    public init(stringInterpolation: StringInterpolation) { key = stringInterpolation.key; arguments = stringInterpolation.arguments }
    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        public init(literalCapacity: Int, interpolationCount: Int) {}
        public mutating func appendLiteral(_ value: String) { key += value }
        public mutating func appendInterpolation<T>(_ value: T) { key += "{\(arguments.count)}"; arguments.append(String(describing: value)) }
    }
}

public enum L10n {
    public static func text(_ message: LocalizedMessage) -> String {
        render(message.key, arguments: message.arguments, language: InterfaceLocalization.shared.language)
    }
    public static func value(_ value: String) -> String {
        translate(value, language: InterfaceLocalization.shared.language)
    }
    public static func render(_ key: String, arguments: [String] = [], language: InterfaceLanguage) -> String {
        let template = translations(for: language)[key] ?? key
        let regex = try! NSRegularExpression(pattern: #"\{([0-9]+)\}"#)
        var result = template
        for match in regex.matches(in: template, range: NSRange(template.startIndex..., in: template)).reversed() {
            guard let number = Range(match.range(at: 1), in: template), let slot = Int(template[number]), arguments.indices.contains(slot),
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: arguments[slot])
        }
        return result
    }
    public static func translations(for language: InterfaceLanguage) -> [String: String] { tables[language] ?? [:] }
    private static let tables: [InterfaceLanguage: [String:String]] = Dictionary(uniqueKeysWithValues: InterfaceLanguage.allCases.filter { $0 != .english }.map { language in
        let url = Bundle.module.url(forResource: language.rawValue, withExtension: "json", subdirectory: "Translations")
            ?? Bundle.module.url(forResource: language.rawValue, withExtension: "json")
        let data = url.flatMap { try? Data(contentsOf: $0) }
        return (language, data.flatMap { try? JSONDecoder().decode([String:String].self, from: $0) } ?? [:])
    })
    private struct Pattern { let key: String; let regex: NSRegularExpression; let slots: [Int] }
    private static let patterns: [Pattern] = {
        let keys = Set(tables.values.flatMap { $0.keys })
        let placeholder = try! NSRegularExpression(pattern: #"\{([0-9]+)\}"#)
        return keys.sorted { $0.count > $1.count }.compactMap { key in
            let range = NSRange(key.startIndex..., in: key), matches = placeholder.matches(in: key, range: range)
            guard !matches.isEmpty else { return nil }
            var expression = "\\A", cursor = key.startIndex, slots: [Int] = []
            for match in matches {
                guard let part = Range(match.range, in: key), let number = Range(match.range(at: 1), in: key), let slot = Int(key[number]) else { return nil }
                expression += NSRegularExpression.escapedPattern(for: String(key[cursor..<part.lowerBound])) + "(.*?)"
                cursor = part.upperBound; slots.append(slot)
            }
            expression += NSRegularExpression.escapedPattern(for: String(key[cursor...])) + "\\z"
            guard let regex = try? NSRegularExpression(pattern: expression, options: [.dotMatchesLineSeparators]) else { return nil }
            return Pattern(key: key, regex: regex, slots: slots)
        }
    }()
    /// For dynamic labels/status messages; archive paths and file contents must
    /// not pass through this method. Unknown diagnostics retain their original text.
    public static func translate(_ value: String, language: InterfaceLanguage) -> String {
        guard language != .english else { return value }
        if let exact = translations(for: language)[value] { return exact }
        for pattern in patterns {
            guard let match = pattern.regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { continue }
            var arguments = Array(repeating: "", count: (pattern.slots.max() ?? 0) + 1)
            for (index, slot) in pattern.slots.enumerated() {
                if let range = Range(match.range(at: index+1), in: value) { arguments[slot] = String(value[range]) }
            }
            return render(pattern.key, arguments: arguments, language: language)
        }
        return value
    }
}
