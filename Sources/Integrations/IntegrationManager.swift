import Foundation
import Observation

/// 메뉴 패널의 "AI 연결" 버튼 동작: 설정 파일을 백업한 뒤 텀펫 항목만 추가/삭제한다.
/// 사용자가 버튼을 눌렀을 때만 파일을 바꾼다. `@Observable` ≈ Zustand 스토어 (상태가 바뀌면 패널이 다시 그려짐)
@Observable
final class IntegrationManager {
    enum Kind: String, CaseIterable, Identifiable {
        case claude, claudeApp, codex, zsh
        var id: String { rawValue }

        var title: String {
            switch self {
            case .claude: return "Claude Code"
            case .claudeApp: return "Claude 앱 채팅"
            case .codex: return "Codex"
            case .zsh: return "터미널 명령"
            }
        }

        var subtitle: String {
            switch self {
            case .claude: return "응답 완료 · 권한 요청"
            case .claudeApp: return "답변 완료"
            case .codex: return "응답 완료"
            case .zsh: return "30초 넘게 걸린 명령"
            }
        }
    }

    let home: URL
    private(set) var installed: [Kind: Bool] = [:]
    /// 연결은 돼 있지만 새 기능용 항목이 빠진 경우 (예: Claude "작업 중" 표시용 훅) → 패널에 "업데이트" 버튼
    private(set) var needsUpdate: [Kind: Bool] = [:]

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
        refresh()
    }

    func file(for kind: Kind) -> URL {
        switch kind {
        case .claude: return home.appendingPathComponent(".claude/settings.json")
        case .claudeApp: return home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        case .codex: return home.appendingPathComponent(".codex/config.toml")
        case .zsh: return home.appendingPathComponent(".zshrc")
        }
    }

    var hookPath: String { home.appendingPathComponent(".termpet/bin/termpet-hook").path }
    /// Claude 앱이 MCP 서버로 실행할 명령 = 지금 실행 중인 텀펫 (`TermPet --mcp`)
    var mcpCommand: String = Bundle.main.executablePath ?? "/Applications/TermPet.app/Contents/MacOS/TermPet"

    /// Codex는 ~/.codex 폴더가, Claude 앱은 설정 폴더가 있을 때만 (설치돼 있을 때만) 연결 가능
    func isAvailable(_ kind: Kind) -> Bool {
        switch kind {
        case .codex: return FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex").path)
        case .claudeApp: return FileManager.default.fileExists(atPath: file(for: kind).deletingLastPathComponent().path)
        default: return true
        }
    }

    func refresh() {
        var state: [Kind: Bool] = [:]
        var update: [Kind: Bool] = [:]
        for kind in Kind.allCases {
            let data = try? Data(contentsOf: file(for: kind))
            let text = data.flatMap { String(data: $0, encoding: .utf8) }
            switch kind {
            case .claude:
                state[kind] = ClaudeHooksConfig.isInstalled(data)
                update[kind] = state[kind] == true && !ClaudeHooksConfig.missingEvents(data).isEmpty
            case .claudeApp:
                state[kind] = ClaudeDesktopConfig.isInstalled(data)
                update[kind] = ClaudeDesktopConfig.needsUpdate(data, command: mcpCommand)
            case .codex: state[kind] = CodexNotifyConfig.isInstalled(text)
            case .zsh: state[kind] = ZshrcConfig.isInstalled(text)
            }
        }
        installed = state
        needsUpdate = update
    }

    /// 연결 ↔ 해제 (업데이트가 필요하면 해제 대신 빠진 항목만 추가). 성공하면 백업 파일 경로를 돌려준다.
    @discardableResult
    func toggle(_ kind: Kind, remove: Bool = false) throws -> URL? {
        let url = file(for: kind).resolvingSymlinksInPath() // dotfiles 심볼릭 링크면 실제 파일을 고친다
        // 파일이 없을 때만 "빈 파일"로 본다. 권한 문제 등으로 못 읽으면 덮어쓰지 않고 멈춘다
        // (예전엔 못 읽으면 백업 없이 텀펫 줄만 남기고 덮어쓸 수 있었다)
        let original: Data?
        do {
            original = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            original = nil
        }
        let text = original.flatMap { String(data: $0, encoding: .utf8) }
        // 글자 파일(.zshrc, config.toml)이 UTF-8이 아니면 내용을 이해하지 못한 채 고치게 되니 건드리지 않는다
        if original != nil, text == nil, kind == .zsh || kind == .codex {
            throw IntegrationError.unreadable("\(url.lastPathComponent) 파일이 UTF-8 글자가 아니라서 건드리지 않았어요. 직접 고쳐 주세요.")
        }
        // remove: 업데이트가 필요한 상태에서도 스위치를 끄면 해제
        let on = installed[kind] == true && (remove || needsUpdate[kind] != true)

        let updated: Data
        switch kind {
        case .claude:
            updated = on ? try ClaudeHooksConfig.uninstall(from: original ?? Data())
                         : try ClaudeHooksConfig.install(into: original)
        case .claudeApp:
            updated = on ? try ClaudeDesktopConfig.uninstall(from: original ?? Data())
                         : try ClaudeDesktopConfig.install(into: original, command: mcpCommand)
        case .codex:
            updated = Data((on ? CodexNotifyConfig.uninstall(from: text ?? "")
                               : try CodexNotifyConfig.install(into: text, hookPath: hookPath)).utf8)
        case .zsh:
            updated = Data((on ? ZshrcConfig.uninstall(from: text ?? "") : ZshrcConfig.install(into: text)).utf8)
        }

        var backup: URL?
        if let original {
            let stamp = Self.stamp.string(from: Date())
            backup = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).termpet-backup-\(stamp)")
            try original.write(to: backup!)
            // 백업은 나만 읽을 수 있게 (settings.json 에 API 키 같은 값이 있을 수 있음)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup!.path)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try updated.write(to: url, options: .atomic)
        refresh()
        return backup
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}

