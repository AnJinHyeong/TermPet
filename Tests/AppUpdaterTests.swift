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

    func testCheckResultKeepsReasons() {
        let ok = Data(#"{"tag_name":"v0.5.4"}"#.utf8)
        XCTAssertEqual(AppUpdater.checkResult(status: 200, data: ok, current: "0.5.3"), .available("0.5.4"))
        XCTAssertEqual(AppUpdater.checkResult(status: 200, data: ok, current: "0.5.4"), .upToDate)
        XCTAssertEqual(AppUpdater.checkResult(status: 200, data: Data("{}".utf8), current: "0.5.3"), .failed("버전 정보를 읽지 못했어요"))
        // 요청 횟수 제한 응답은 "버전을 못 읽음"이 아니라 그 이유로
        let limited = Data(#"{"message":"API rate limit exceeded"}"#.utf8)
        guard case .failed(let why) = AppUpdater.checkResult(status: 403, data: limited, current: "0.5.3") else { return XCTFail() }
        XCTAssertTrue(why.contains("횟수"))
        XCTAssertEqual(AppUpdater.checkResult(status: 502, data: Data(), current: "0.5.3"), .failed("버전 확인 실패 (HTTP 502)"))
    }

    func testUpdateScriptOpensAppOnlyIfNotRunning() {
        let s = AppUpdater.updateScript(brew: "/opt/homebrew/bin/brew", log: "/tmp/u.log", done: "/tmp/u.done",
                                        appPath: "/Applications/TermPet.app")
        // brew 가 다시 켠 앱이 있으면 또 열지 않는다 (업데이트 후 두 개 뜨던 문제)
        XCTAssertTrue(s.contains("pgrep -xf '/Applications/TermPet.app/Contents/MacOS/TermPet' >/dev/null && exit 0"))
        XCTAssertTrue(s.hasSuffix("open '/Applications/TermPet.app'"))
        XCTAssertFalse(s.contains("open -a"))
        XCTAssertTrue(s.contains("echo \"$rc\" > '/tmp/u.done'"))
        // 쉘 문법 검사 (sh -n)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-n", "-c", s]
        XCTAssertNoThrow(try p.run())
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
    }

    func testShellQuoteSurvivesQuotes() {
        XCTAssertEqual(AppUpdater.shellQuote("a'b"), #"'a'\''b'"#)
    }
}
