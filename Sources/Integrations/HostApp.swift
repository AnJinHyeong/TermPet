import Foundation

/// 알림이 발생한 터미널/에디터 앱.
/// `hostBundleId`(통합 터미널이 상속한 `__CFBundleIdentifier`)로 판별하고, 없으면 `TERM_PROGRAM`으로 추정.
enum HostApp: Equatable {
    case cursor, vscode, vscodeInsiders, windsurf, zed
    case iterm, terminal, warp, ghostty, wezterm, kitty
    /// ChatGPT 데스크톱 앱 (Codex 대화 포함). 번들 ID가 com.openai.codex
    case chatgpt
    case other(bundleId: String)

    static let knownBundleIds: [String: HostApp] = [
        "com.todesktop.230313mzl4w4u92": .cursor,
        "com.microsoft.VSCode": .vscode,
        "com.microsoft.VSCodeInsiders": .vscodeInsiders,
        "com.exafunction.windsurf": .windsurf,
        "dev.zed.Zed": .zed,
        "com.googlecode.iterm2": .iterm,
        "com.apple.Terminal": .terminal,
        "dev.warp.Warp-Stable": .warp,
        "com.mitchellh.ghostty": .ghostty,
        "com.github.wez.wezterm": .wezterm,
        "net.kovidgoyal.kitty": .kitty,
        "com.openai.codex": .chatgpt,
    ]

    /// knownBundleIds 표 하나만 관리 (같은 값을 두 군데 적지 않도록 역으로 찾는다)
    var bundleId: String {
        if case .other(let id) = self { return id }
        return Self.knownBundleIds.first { $0.value == self }!.key
    }

    /// 폴더를 열면 해당 프로젝트 창으로 이동하는 에디터인지
    var opensProjectFolder: Bool {
        switch self {
        case .cursor, .vscode, .vscodeInsiders, .windsurf, .zed: return true
        default: return false
        }
    }

    static func resolve(bundleId: String?, termProgram: String?) -> HostApp? {
        if let bundleId, !bundleId.isEmpty {
            return knownBundleIds[bundleId] ?? .other(bundleId: bundleId)
        }
        switch termProgram {
        // 주의: Cursor도 TERM_PROGRAM=vscode 이므로 번들 ID가 없으면 VSCode로 추정할 수밖에 없다
        case "vscode": return .vscode
        case "iTerm.app": return .iterm
        case "Apple_Terminal": return .terminal
        case "WarpTerminal": return .warp
        case "ghostty": return .ghostty
        case "WezTerm": return .wezterm
        case "zed": return .zed
        default: return nil
        }
    }
}

/// 말풍선 클릭 시 무엇을 할지 (순수 계산 → 테스트 가능)
enum FocusAction: Equatable {
    /// 에디터로 프로젝트 폴더 열기 (이미 열려 있으면 그 창이 앞으로 옴)
    case openFolder(bundleId: String, path: String)
    /// 앱 활성화만
    case activate(bundleId: String)
    /// 앱 딥링크 열기 (예: ChatGPT 앱의 그 대화 `codex://threads/<id>`). 링크가 안 먹으면 앱만 앞으로
    case openURL(url: String, bundleId: String)
    case none

    static func plan(for event: PetEvent, projectRoot: (String) -> String) -> FocusAction {
        guard let app = HostApp.resolve(bundleId: event.hostBundleId, termProgram: event.termProgram) else {
            return .none
        }
        // Codex 대화만 딥링크가 있다 (일반 GPT 채팅은 링크로 못 열어서 앱만 앞으로)
        if app == .chatgpt, let sid = event.sessionId, ChatGPTAppLog.isCodexThread(sid),
           let id = sid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
            return .openURL(url: "codex://threads/\(id)", bundleId: app.bundleId)
        }
        if app.opensProjectFolder, let cwd = event.cwd, !cwd.isEmpty {
            return .openFolder(bundleId: app.bundleId, path: projectRoot(cwd))
        }
        return .activate(bundleId: app.bundleId)
    }
}

/// cwd에서 위로 올라가며 `.git`이 있는 폴더(=프로젝트 루트)를 찾는다.
/// 하위 폴더에서 명령을 실행했을 때 에디터가 하위 폴더를 "새 창"으로 열어버리는 걸 막기 위함.
enum ProjectRootFinder {
    static func find(from cwd: String, home: String = NSHomeDirectory(),
                     exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String {
        var dir = (cwd as NSString).standardizingPath
        while dir != "/" && dir != home && !dir.isEmpty {
            if exists((dir as NSString).appendingPathComponent(".git")) { return dir }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return cwd
    }
}
