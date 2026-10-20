import Foundation
import XCTest

final class LocalizationTests: XCTestCase {
    private var catalog: [String: Any] {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("AIUsage/Localizable.xcstrings")
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            return try XCTUnwrap(object as? [String: Any])
        }
    }

    /// Every language declared in Info.plist must translate every string,
    /// except brand names and symbols marked as not translatable.
    func testEveryDeclaredLanguageTranslatesEveryString() throws {
        let strings = try XCTUnwrap(try catalog["strings"] as? [String: [String: Any]])
        let languages = try declaredLanguages().filter { $0 != "en" }
        XCTAssertFalse(languages.isEmpty)

        for language in languages {
            let missing = strings.filter { _, entry in
                guard entry["shouldTranslate"] as? Bool != false else { return false }
                let localizations = entry["localizations"] as? [String: Any]
                let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                return unit?["state"] as? String != "translated"
            }.keys.sorted()
            XCTAssertEqual(missing, [], "Untranslated \(language) strings")
        }
    }

    /// A language present in the catalog but missing from Info.plist is never
    /// offered, and a declared one without translations shows English.
    func testInfoPlistDeclaresExactlyTheCatalogLanguages() throws {
        let strings = try XCTUnwrap(try catalog["strings"] as? [String: [String: Any]])
        let catalogLanguages = Set(strings.values.flatMap {
            ($0["localizations"] as? [String: Any])?.keys.map { $0 } ?? []
        })
        XCTAssertEqual(Set(try declaredLanguages()), catalogLanguages.union(["en"]))
    }

    private func declaredLanguages() throws -> [String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AIUsage/Info.plist")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try XCTUnwrap((plist as? [String: Any])?["CFBundleLocalizations"] as? [String])
    }
}
