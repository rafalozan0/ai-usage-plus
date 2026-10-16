import Foundation
import XCTest

final class UpdateConfigurationTests: XCTestCase {
    func testSignedUpdateConfigurationIsEmbeddedInTheApp() {
        let info = Bundle.main.infoDictionary

        XCTAssertEqual(
            info?["SUFeedURL"] as? String,
            "https://raw.githubusercontent.com/rafalozan0/ai-usage-menubar/main/appcast.xml"
        )
        XCTAssertEqual(
            info?["SUPublicEDKey"] as? String,
            "b9GjYRAnuvagsWfTGGAqqDlAV3Bu9SzvY0maFy/+a/s="
        )
        XCTAssertEqual(info?["SUEnableAutomaticChecks"] as? Bool, true)
        XCTAssertEqual(info?["SURequireSignedFeed"] as? Bool, true)
        XCTAssertEqual(info?["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
        XCTAssertEqual(info?["SUScheduledCheckInterval"] as? Int, 86_400)
    }
}
