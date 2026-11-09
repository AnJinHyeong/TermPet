import Foundation
import Observation

/// 메뉴 패널의 "AI 연결" 버튼 동작: 설정 파일을 백업한 뒤 텀펫 항목만 추가/삭제한다.
/// 사용자가 버튼을 눌렀을 때만 파일을 바꾼다. `@Observable` ≈ Zustand 스토어 (상태가 바뀌면 패널이 다시 그려짐)
@Observable
final class IntegrationManager {
    enum Kind: String, CaseIterable, Identifiable {
        case claude, codex, zsh
        var id: String { rawValue }

        var title: String {
            switch self {
            case .claude: return "Claude Code"
            case .codex: return "Codex"
            case .zsh: return "터미널 명령"
            }
        }

        var subtitle: String {
            switch self {
            case .claude: return "응답 완료 · 권한 요청"
            case .codex: return "응답 완료"
            case .zsh: return "30초 넘게 걸린 명령"
            }
        }
    }

    let home: URL
    private(set) var installed: [Kind: Bool] = [:]

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
        refresh()
    }

    func file(for kind: Kind) -> URL {
        switch kind {
        case .claude: return home.appendingPathComponent(".claude/settings.json")
        case .codex: return home.appendingPathComponent(".codex/config.toml")
        case .zsh: return home.appendingPathComponent(".zshrc")
        }
    }

    var hookPath: String { home.appendingPathComponent(".termpet/bin/termpet-hook").path }

    /// Codex는 ~/.codex 폴더가 있을 때만 (설치돼 있을 때만) 연결 가능
    func isAvailable(_ kind: Kind) -> Bool {
        kind != .codex || FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex").path)
    }

    func refresh() {
        var state: [Kind: Bool] = [:]
        for kind in Kind.allCases {
            let data = try? Data(contentsOf: file(for: kind))
            let text = data.flatMap { String(data: $0, encoding: .utf8) }
            switch kind {
            case .claude: state[kind] = ClaudeHooksConfig.isInstalled(data)
            case .codex: state[kind] = CodexNotifyConfig.isInstalled(text)
            case .zsh: state[kind] = ZshrcConfig.isInstalled(text)
            }
        }
        installed = state
    }

    /// 연결 ↔ 해제. 성공하면 백업 파일 경로(원본이 있었을 때)를 돌려준다.
    @discardableResult
    func toggle(_ kind: Kind) throws -> URL? {
        let url = file(for: kind).resolvingSymlinksInPath() // dotfiles 심볼릭 링크면 실제 파일을 고친다
        let original = try? Data(contentsOf: url)
        let text = original.flatMap { String(data: $0, encoding: .utf8) }
        let on = installed[kind] == true

        let updated: Data
        switch kind {
        case .claude:
            updated = on ? try ClaudeHooksConfig.uninstall(from: original ?? Data())
                         : try ClaudeHooksConfig.install(into: original)
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
