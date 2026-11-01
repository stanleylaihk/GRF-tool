import Foundation
import Testing
@testable import GRFDesktop

struct LocalizationTests {
    @Test func translationsCoverTheSameKeysAndPreserveAllPlaceholders() throws {
        let languages: [InterfaceLanguage] = [.traditionalChinese, .japanese, .korean]
        let baseline = L10n.translations(for: .traditionalChinese)
        #expect(baseline.count >= 300)
        let regex = try NSRegularExpression(pattern: #"\{[0-9]+\}"#)
        func slots(_ text: String) -> [String] {
            regex.matches(in: text, range: NSRange(text.startIndex...,in: text)).map { String(text[Range($0.range,in: text)!]) }.sorted()
        }
        for language in languages {
            let table = L10n.translations(for: language)
            #expect(Set(table.keys) == Set(baseline.keys))
            for (key,value) in table { #expect(!value.isEmpty); #expect(slots(key) == slots(value), "\(language.rawValue): \(key)") }
        }
    }
    @Test func runtimeLabelsAndDynamicCountsUseTheSelectedLanguage() {
        #expect(L10n.render("Manage",language: .traditionalChinese) == "管理")
        #expect(L10n.render("Settings",language: .japanese) == "設定")
        #expect(L10n.render("Palette",language: .korean) == "팔레트")
        #expect(L10n.translate("Loaded 60,197 files.",language: .traditionalChinese) == "已載入 60,197 個檔案。")
        #expect(L10n.render("{0} actions",arguments: ["104"],language: .korean) == "동작 104개")
        #expect(L10n.render("Extracted {0} of {1} resources.",arguments: ["2","3"],language: .japanese) == "3 リソース中 2 件を展開しました。")
    }
    @Test func interpolationDoesNotTranslateOrReinterpretResourceNames() {
        let path = "data/魔法/{1}_%@.act"
        #expect(L10n.render("From: {0}",arguments: [path],language: .traditionalChinese) == "原路徑：" + path)
        #expect(L10n.translate(path,language: .korean) == path)
        #expect(L10n.render("Unknown diagnostic",language: .japanese) == "Unknown diagnostic")
        #expect(L10n.translate("Manage",language: .english) == "Manage")
    }
    @Test func preferencePersistsAndUnknownValuesFallBackToEnglish() throws {
        let suite = "grf-language-tests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let first = InterfaceLocalization(defaults: defaults)
        #expect(first.language == .english)
        first.language = .japanese
        #expect(InterfaceLocalization(defaults: defaults).language == .japanese)
        defaults.set("unsupported",forKey: InterfaceLocalization.preferenceKey)
        #expect(InterfaceLocalization(defaults: defaults).language == .english)
    }
}
