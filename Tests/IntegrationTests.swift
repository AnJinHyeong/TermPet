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

    /// ChatGPT 앱의 Codex Computer Use가 우리 notify를 `--previous-notify`로 다시 감싼 실제 형태 (2026-11-11 확인)
    func testWrappedByComputerUseStillInstalledAndRestores() throws {
        let sky = "/Users/me/.codex/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient"
        let wrapped = #"notify = [""# + sky + #"", "turn-ended", "--previous-notify", "[\"\\/Users\\/me\\/.termpet\\/bin\\/termpet-hook\",\"codex-chain\",\""# + sky.replacingOccurrences(of: "/", with: "\\/") + #"\",\"turn-ended\"]"]"# + "\nmodel = \"o3\"\n"
        XCTAssertEqual(CodexNotifyConfig.rootNotify(in: wrapped)?.1.count, 4)
        XCTAssertTrue(CodexNotifyConfig.isInstalled(wrapped))
        XCTAssertEqual(try CodexNotifyConfig.install(into: wrapped, hookPath: hook), wrapped, "또 감싸지 않는다 (알림 두 번 방지)")
        let off = CodexNotifyConfig.uninstall(from: wrapped)
        XCTAssertEqual(CodexNotifyConfig.rootNotify(in: off)?.1, [sky, "turn-ended"], "감싼 도구의 원래 줄로")
        XCTAssertFalse(CodexNotifyConfig.isInstalled(off))
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

    func testEscapesRoundTrip() {
        // \t 가 t 로, 줄바꿈이 날것으로 들어가 config.toml 이 깨지던 문제
        let parsed = CodexNotifyConfig.parseStringArray(#"["a\tb", "c\nd", "e\\f"]"#)
        XCTAssertEqual(parsed, ["a\tb", "c\nd", "e\\f"])
        XCTAssertEqual(CodexNotifyConfig.render(parsed!), #"notify = ["a\tb", "c\nd", "e\\f"]"#)
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

extension IntegrationManagerTests {
    func testRefusesToRewriteNonUTF8TextFile() throws {
        let zshrc = home.appendingPathComponent(".zshrc")
        let latin1 = Data([0x65, 0x78, 0x70, 0x6F, 0x72, 0x74, 0x20, 0xE9, 0x0A]) // UTF-8 이 아닌 글자
        try latin1.write(to: zshrc)
        let manager = IntegrationManager(home: home)
        XCTAssertThrowsError(try manager.toggle(.zsh))
        XCTAssertEqual(try Data(contentsOf: zshrc), latin1) // 그대로
    }

    func testBackupIsPrivate() throws {
        let zshrc = home.appendingPathComponent(".zshrc")
        try "export A=1\n".write(to: zshrc, atomically: true, encoding: .utf8)
        let backup = try XCTUnwrap(try IntegrationManager(home: home).toggle(.zsh))
        let mode = try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }
}

final class ClaudeProgressHooksTests: XCTestCase {
    private func hooks(_ data: Data) -> [String: Any] {
        (try! JSONSerialization.jsonObject(with: data) as! [String: Any])["hooks"] as! [String: Any]
    }
    private func ourEntry(_ hooks: [String: Any], _ event: String) -> [String: Any]? {
        (hooks[event] as? [[String: Any]])?.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
            .first { ($0["command"] as? String)?.contains("termpet-hook") == true }
    }

    func testInstallAddsProgressHooksAsAsync() throws {
        let h = hooks(try ClaudeHooksConfig.install(into: nil))
        for event in ClaudeHooksConfig.progressEvents {
            XCTAssertEqual(ourEntry(h, event)?["async"] as? Bool, true, event)
        }
        XCTAssertNil(ourEntry(h, "Stop")?["async"])
        XCTAssertEqual(ourEntry(h, "PostToolUse")?["command"] as? String, ClaudeHooksConfig.toolCommand)
    }

    func testOldInstallNeedsUpdateAndUninstallRemovesAll() throws {
        // 예전 버전처럼 Stop·Notification만 연결된 상태
        let old = Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"$HOME/.termpet/bin/termpet-hook claude"}]}],"Notification":[{"hooks":[{"type":"command","command":"$HOME/.termpet/bin/termpet-hook claude"}]}]}}"#.utf8)
        XCTAssertTrue(ClaudeHooksConfig.isInstalled(old))
        XCTAssertEqual(ClaudeHooksConfig.missingEvents(old), ClaudeHooksConfig.progressEvents)
        let updated = try ClaudeHooksConfig.install(into: old)
        XCTAssertEqual(ClaudeHooksConfig.missingEvents(updated), [])
        XCTAssertEqual((hooks(updated)["Stop"] as! [Any]).count, 1) // 중복 추가 없음
        XCTAssertTrue(hooks(try ClaudeHooksConfig.uninstall(from: updated)).isEmpty)
    }

    func testManagerUpdatesInsteadOfUninstalling() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("termpet-upd-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let settings = home.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"termpet-hook claude"}]}],"Notification":[{"hooks":[{"type":"command","command":"termpet-hook claude"}]}]}}"#.utf8).write(to: settings)

        let manager = IntegrationManager(home: home)
        XCTAssertEqual(manager.needsUpdate[.claude], true)
        try manager.toggle(.claude)
        XCTAssertEqual(manager.installed[.claude], true)   // 해제되지 않고
        XCTAssertEqual(manager.needsUpdate[.claude], false) // 업데이트됨
        try manager.toggle(.claude)
        XCTAssertEqual(manager.installed[.claude], false)
    }
}
