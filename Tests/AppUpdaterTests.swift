import XCTest
@testable import TermPet

final class AppUpdaterTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(AppUpdater.isNewer("v0.3.2", than: "0.3.1"))
        XCTAssertTrue(AppUpdater.isNewer("v0.10.0", than: "0.9.9"))   // 문자열 비교가 아니라 숫자 비교
        XCTAssertTrue(AppUpdater.isNewer("v1.0", than: "0.9.9"))
        XCTAssertFalse(AppUpdater.isNewer("v0.3.1", than: "0.3.1"))
        XCTAssertFalse(AppUpdater.isNewer("v0.3.0", than: "0.3.1"))
        XCTAssertFalse(AppUpdater.isNewer("v0.3.1", than: "0.3.1.0"))
        XCTAssertFalse(AppUpdater.isNewer("v0.4.0", than: "dev"))      // 개발 빌드는 안내 안 함
        XCTAssertFalse(AppUpdater.isNewer("nightly", than: "0.3.1"))
    }

    func testTagNameFromGitHubResponse() {
        let json = #"{"tag_name":"v0.3.2","name":"텀펫 v0.3.2","assets":[]}"#
        XCTAssertEqual(AppUpdater.tagName(from: Data(json.utf8)), "v0.3.2")
        XCTAssertNil(AppUpdater.tagName(from: Data(#"{"message":"Not Found"}"#.utf8)))
        XCTAssertNil(AppUpdater.tagName(from: Data("oops".utf8)))
        XCTAssertEqual(AppUpdater.normalized("v0.3.2"), "0.3.2")
    }

    func testShellQuoteSurvivesQuotes() {
        XCTAssertEqual(AppUpdater.shellQuote("a'b"), #"'a'\''b'"#)
    }
}
