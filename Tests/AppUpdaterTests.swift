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

    func testOutcomeAfterBrewFinishesWhileAppStillRuns() {
        // 디스크엔 새 버전, 도는 건 예전 것 → 다시 켜기 (brew가 앱을 못 끄고 끝났거나 다른 앱이 켜진 경우)
        XCTAssertEqual(AppUpdater.outcome(exitCode: 0, running: "0.5.1", installed: "0.5.2"), .restart)
        // 이미 최신이라 아무것도 안 함 → 다시 확인해서 "업데이트 중" 표시를 치운다
        XCTAssertEqual(AppUpdater.outcome(exitCode: 0, running: "0.5.2", installed: "0.5.2"), .recheck)
        // brew 실패
        XCTAssertEqual(AppUpdater.outcome(exitCode: 1, running: "0.5.1", installed: "0.5.1"), .failed)
        XCTAssertEqual(AppUpdater.outcome(exitCode: 1, running: "0.5.1", installed: nil), .failed)
    }

    func testInstalledVersionReadsPlistFromDisk() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent("Fake-\(UUID().uuidString).app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: app) }
        XCTAssertNil(AppUpdater.installedVersion(at: app))
        (["CFBundleShortVersionString": "0.5.2"] as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"), atomically: true)
        XCTAssertEqual(AppUpdater.installedVersion(at: app), "0.5.2")
    }

    func testShellQuoteSurvivesQuotes() {
        XCTAssertEqual(AppUpdater.shellQuote("a'b"), #"'a'\''b'"#)
    }
}
