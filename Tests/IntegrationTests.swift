import XCTest
@testable import TermPet

final class ClaudeHooksConfigTests: XCTestCase {
    private func json(_ data: Data) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    func testInstallKeepsOtherSettingsAndHooks() throws {
        let original = Data(#"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"orca stop"}]}],"PreToolUse":[]}}"#.utf8)
        let out = try ClaudeHooksConfig.install(into: original)
        let root = json(out)
        XCTAssertEqual(root["model"] as? String, "opus")
        let hooks = root["hooks"] as! [String: Any]
        XCTAssertEqual((hooks["Stop"] as! [Any]).count, 2)          // orca + 텀펫
        XCTAssertEqual((hooks["Notification"] as! [Any]).count, 1)
        XCTAssertNotNil(hooks["PreToolUse"])
        XCTAssertTrue(ClaudeHooksConfig.isInstalled(out))
        // 두 번 눌러도 중복 추가 안 됨
        XCTAssertEqual((json(try ClaudeHooksConfig.install(into: out))["hooks"] as! [String: Any])["Stop"].map { ($0 as! [Any]).count }, 2)
    }

    func testInstallIntoMissingFile() throws {
        XCTAssertTrue(ClaudeHooksConfig.isInstalled(try ClaudeHooksConfig.install(into: nil)))
    }

    func testUninstallRemovesOnlyOurs() throws {
        let original = Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"orca stop"}]}]}}"#.utf8)
        let out = try ClaudeHooksConfig.uninstall(from: try ClaudeHooksConfig.install(into: original))
        let hooks = json(out)["hooks"] as! [String: Any]
        XCTAssertEqual((hooks["Stop"] as! [Any]).count, 1)
        XCTAssertNil(hooks["Notification"])
        XCTAssertFalse(ClaudeHooksConfig.isInstalled(out))
    }

    func testBrokenJSONThrowsInsteadOfOverwriting() {
        XCTAssertThrowsError(try ClaudeHooksConfig.install(into: Data("{ oops".utf8)))
    }
}

final class ZshrcConfigTests: XCTestCase {
    func testInstallAppendsOnceAndUninstallRestores() {
        let original = "export PATH=x\nalias ll='ls -l'\n"
        let installed = ZshrcConfig.install(into: original)
        XCTAssertTrue(installed.hasPrefix(original))
        XCTAssertTrue(ZshrcConfig.isInstalled(installed))
        XCTAssertEqual(ZshrcConfig.install(into: installed), installed)
        XCTAssertFalse(ZshrcConfig.isInstalled(ZshrcConfig.uninstall(from: installed)))
        XCTAssertTrue(ZshrcConfig.uninstall(from: installed).contains("alias ll='ls -l'"))
    }

    func testCommentedLineDoesNotCount() {
        XCTAssertFalse(ZshrcConfig.isInstalled("# source ~/.termpet/zsh-integration.zsh"))
    }
}

final class CodexNotifyConfigTests: XCTestCase {
    let hook = "/Users/me/.termpet/bin/termpet-hook"

    func testInsertsBeforeFirstTable() throws {
        let original = "model = \"o3\"\n\n[tui]\nnotifications = true\n"
        let out = try CodexNotifyConfig.install(into: original, hookPath: hook)
        let lines = out.components(separatedBy: "\n")
        let notify = lines.firstIndex { $0.hasPrefix("notify") }!
        XCTAssertLessThan(notify, lines.firstIndex(of: "[tui]")!)
        XCTAssertTrue(CodexNotifyConfig.isInstalled(out))
        XCTAssertEqual(CodexNotifyConfig.rootNotify(in: out)?.1, [hook, "codex"])
        XCTAssertFalse(CodexNotifyConfig.isInstalled(CodexNotifyConfig.uninstall(from: out)))
    }

    func testChainsExistingNotifyAndRestoresItExactly() throws {
        let existing = #"notify = ["/Apps/Sky Client", "turn-ended"]"#
        let original = existing + "\nmodel = \"o3\"\n"
        let out = try CodexNotifyConfig.install(into: original, hookPath: hook)
        XCTAssertEqual(CodexNotifyConfig.rootNotify(in: out)?.1, [hook, "codex-chain", "/Apps/Sky Client", "turn-ended"])
        XCTAssertEqual(CodexNotifyConfig.uninstall(from: out), original)
    }

    func testNotifyInsideTableIsNotRoot() throws {
        let original = "[tui]\nnotify = [\"x\"]\n"
        XCTAssertNil(CodexNotifyConfig.rootNotify(in: original))
        XCTAssertTrue(try CodexNotifyConfig.install(into: original, hookPath: hook).hasPrefix("notify = "))
    }

    func testUnparseableNotifyThrows() {
        XCTAssertThrowsError(try CodexNotifyConfig.install(into: "notify = [\n  \"a\",\n]\n", hookPath: hook))
    }

    func testParseStringArray() {
        XCTAssertEqual(CodexNotifyConfig.parseStringArray(#" ["a", "b \"q\"" ] # c"#), ["a", "b \"q\""])
        XCTAssertEqual(CodexNotifyConfig.parseStringArray("[]"), [])
        XCTAssertNil(CodexNotifyConfig.parseStringArray("'a'"))
        XCTAssertEqual(CodexNotifyConfig.render(["a b", "c\"d"]), #"notify = ["a b", "c\"d"]"#)
    }
}

final class IntegrationManagerTests: XCTestCase {
    private var home: URL!

    override func setUp() {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("termpet-home-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: home) }

    func testToggleBacksUpAndFollowsSymlink() throws {
        // dotfiles 저장소처럼 ~/.zshrc 가 심볼릭 링크인 경우
        let real = home.appendingPathComponent("dotfiles/zshrc")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "export A=1\n".write(to: real, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(".zshrc"), withDestinationURL: real)

        let manager = IntegrationManager(home: home)
        XCTAssertEqual(manager.installed[.zsh], false)
        let backup = try XCTUnwrap(try manager.toggle(.zsh))
        XCTAssertEqual(try String(contentsOf: backup), "export A=1\n")
        XCTAssertEqual(manager.installed[.zsh], true)
        // 링크는 그대로, 실제 파일이 바뀜
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: home.appendingPathComponent(".zshrc").path))
        XCTAssertTrue(try String(contentsOf: real).contains("zsh-integration.zsh"))

        try manager.toggle(.zsh)
        XCTAssertEqual(manager.installed[.zsh], false)
    }

    func testCodexUnavailableWithoutFolder() {
        let manager = IntegrationManager(home: home)
        XCTAssertFalse(manager.isAvailable(.codex))
        XCTAssertTrue(manager.isAvailable(.claude))
    }
}
