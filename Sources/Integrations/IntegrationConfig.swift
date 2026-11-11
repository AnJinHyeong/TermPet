import Foundation

/// 사용자 설정 파일에 텀펫 연동을 넣고/빼는 순수 로직 (파일 읽기·쓰기는 IntegrationManager).
/// 원칙: 기존 내용은 건드리지 않고 우리 항목만 추가/삭제. 해석할 수 없는 파일이면 에러로 멈춘다.

enum IntegrationError: Error, CustomStringConvertible, Equatable {
    case unreadable(String)

    var description: String {
        switch self {
        case .unreadable(let why): return why
        }
    }
}

// MARK: - Claude Code (~/.claude/settings.json)

enum ClaudeHooksConfig {
    /// 알림(말풍선)용: 끝남 · 권한 요청 · 에러
    static let coreEvents = ["Stop", "Notification"]
    /// 진행 상황용: 작업 시작 · 도구 실행 후 · 에러로 멈춤 · 세션 종료 (펫 머리 위 "작업 중" 표시)
    static let progressEvents = ["UserPromptSubmit", "PostToolUse", "StopFailure", "SessionEnd"]
    static var events: [String] { coreEvents + progressEvents }
    static let command = "$HOME/.termpet/bin/termpet-hook claude"
    /// PostToolUse 입력에는 도구 결과(파일 내용 등)가 통째로 들어 있어서, 필요한 값만 뽑아 보내는 모드
    static let toolCommand = "$HOME/.termpet/bin/termpet-hook claude-tool"
    static let marker = "termpet-hook"

    /// 연결됨 = 알림 훅(Stop·Notification)이 있음. 진행 상황 훅이 빠져 있으면 `missingEvents`로 "업데이트" 표시.
    static func isInstalled(_ data: Data?) -> Bool {
        guard let hooks = hooksObject(data) else { return false }
        return coreEvents.allSatisfy { contains(hooks[$0]) }
    }

    /// 아직 우리 훅이 없는 이벤트 (예전 버전으로 연결한 경우)
    static func missingEvents(_ data: Data?) -> [String] {
        let hooks = hooksObject(data) ?? [:]
        return events.filter { !contains(hooks[$0]) }
    }

    private static func hooksObject(_ data: Data?) -> [String: Any]? {
        guard let data, let root = try? HooksJSON.parse(data, file: "settings.json") else { return nil }
        return root["hooks"] as? [String: Any]
    }

    /// 이벤트별 훅 항목. 진행 상황 훅은 async(백그라운드)라 Claude를 전혀 기다리게 하지 않는다.
    static func hookEntry(for event: String) -> [String: Any] {
        var entry: [String: Any] = ["type": "command",
                                    "command": event == "PostToolUse" ? toolCommand : command,
                                    "timeout": 5]
        if progressEvents.contains(event) { entry["async"] = true }
        return entry
    }

    /// 없는 이벤트에만 우리 훅을 추가. 다른 키와 다른 훅은 그대로.
    static func install(into data: Data?) throws -> Data {
        try HooksJSON.add(events, entry: hookEntry, into: data, file: "settings.json")
    }

    /// 우리 훅만 지운다. 비게 된 그룹/이벤트도 정리.
    static func uninstall(from data: Data) throws -> Data {
        try HooksJSON.remove(events, from: data, file: "settings.json")
    }

    private static func contains(_ groups: Any?) -> Bool { HooksJSON.contains(groups) }
}

// MARK: - Codex 훅 (~/.codex/hooks.json)

/// Codex 훅은 Claude Code와 같은 모양: {"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":…}]}]}}
/// (https://learn.chatgpt.com/docs/hooks.md) 질문을 보내면 "작업 중(…)" 표시. 끝은 notify가 알려 준다.
/// 주의: Codex는 직접 만든 훅을 사용자가 "신뢰"해야 실행한다 (ChatGPT 앱 설정 → 훅).
enum CodexHooksConfig {
    static let events = ["UserPromptSubmit"]

    static func entry(hookPath: String) -> [String: Any] {
        let path = hookPath.contains(" ") ? "'\(hookPath)'" : hookPath
        return ["type": "command", "command": "\(path) codex-hook", "timeout": 5, "async": true]
    }

    static func isInstalled(_ data: Data?) -> Bool {
        guard let data, let root = try? HooksJSON.parse(data, file: "hooks.json"),
              let hooks = root["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { HooksJSON.contains(hooks[$0]) }
    }

    static func install(into data: Data?, hookPath: String) throws -> Data {
        try HooksJSON.add(events, entry: { _ in entry(hookPath: hookPath) }, into: data, file: "hooks.json")
    }

    static func uninstall(from data: Data) throws -> Data {
        try HooksJSON.remove(events, from: data, file: "hooks.json")
    }
}

/// Claude Code settings.json 과 Codex hooks.json 이 같이 쓰는 "hooks" 객체 다루기
enum HooksJSON {
    static let marker = "termpet-hook"

    static func add(_ events: [String], entry: (String) -> [String: Any], into data: Data?, file: String) throws -> Data {
        var root = try data.map { try parse($0, file: file) } ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in events where !contains(hooks[event]) {
            var groups = hooks[event] as? [Any] ?? []
            groups.append(["hooks": [entry(event)]])
            hooks[event] = groups
        }
        root["hooks"] = hooks
        return try serialize(root)
    }

    static func remove(_ events: [String], from data: Data, file: String) throws -> Data {
        var root = try parse(data, file: file)
        guard var hooks = root["hooks"] as? [String: Any] else { return data }
        for event in events {
            guard let groups = hooks[event] as? [Any] else { continue }
            let cleaned: [Any] = groups.compactMap { group in
                guard var g = group as? [String: Any], let inner = g["hooks"] as? [Any] else { return group }
                let kept = inner.filter { !isOurs($0) }
                if kept.isEmpty { return nil }
                g["hooks"] = kept
                return g
            }
            hooks[event] = cleaned.isEmpty ? nil : cleaned
        }
        root["hooks"] = hooks
        return try serialize(root)
    }

    static func contains(_ groups: Any?) -> Bool {
        (groups as? [Any] ?? []).contains { group in
            ((group as? [String: Any])?["hooks"] as? [Any] ?? []).contains(where: isOurs)
        }
    }

    private static func isOurs(_ hook: Any) -> Bool {
        ((hook as? [String: Any])?["command"] as? String)?.contains(marker) == true
    }

    static func parse(_ data: Data, file: String) throws -> [String: Any] {
        if data.isEmpty { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IntegrationError.unreadable("\(file) 이 올바른 JSON 객체가 아니에요")
        }
        return obj
    }

    private static func serialize(_ root: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .withoutEscapingSlashes])
    }
}

// MARK: - zsh (~/.zshrc)

enum ZshrcConfig {
    static let line = "[[ -f ~/.termpet/zsh-integration.zsh ]] && source ~/.termpet/zsh-integration.zsh"
    static let marker = ".termpet/zsh-integration.zsh"

    static func isInstalled(_ text: String?) -> Bool {
        (text ?? "").split(separator: "\n").contains { isOurs($0) }
    }

    static func install(into text: String?) -> String {
        let text = text ?? ""
        if isInstalled(text) { return text }
        let base = text.isEmpty || text.hasSuffix("\n") ? text : text + "\n"
        return base + "\n# 텀펫: 오래 걸린 명령 알림\n" + line + "\n"
    }

    static func uninstall(from text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        lines.removeAll { isOurs(Substring($0)) || $0 == "# 텀펫: 오래 걸린 명령 알림" }
        return lines.joined(separator: "\n")
    }

    private static func isOurs(_ line: Substring) -> Bool {
        line.contains(marker) && !line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
    }
}

// MARK: - Codex (~/.codex/config.toml)

/// Codex는 루트의 `notify = ["프로그램", "인자", ...]` 하나만 받고, 끝에 JSON을 붙여 실행한다.
/// 이미 다른 notify가 있으면 지우지 않고 "연결(chain)": 우리 훅이 먼저 원래 명령을 그대로 실행한 뒤 펫에 알린다.
///   notify = ["<hook>", "codex-chain", <원래 명령...>]   → 해제 시 원래 줄로 복원
enum CodexNotifyConfig {
    static let marker = "termpet-hook"

    static func isInstalled(_ text: String?) -> Bool {
        guard let text, let (_, args) = rootNotify(in: text) else { return false }
        return args.first?.contains(marker) == true || wrappedIndex(args) != nil
    }

    /// 다른 도구(ChatGPT 앱의 Codex Computer Use 등)가 우리 notify를 자기 명령 안에
    /// `--previous-notify '<JSON 배열>'`로 다시 감싼 경우 그 옵션 위치. 그 도구가 우리를 대신 불러 주므로 연결된 상태다.
    ///   예: ["…/SkyComputerUseClient", "turn-ended", "--previous-notify", "[\"…/termpet-hook\",\"codex-chain\",…]"]
    static func wrappedIndex(_ args: [String]) -> Int? {
        guard let i = args.firstIndex(of: "--previous-notify"), i + 1 < args.count, args[i + 1].contains(marker) else { return nil }
        return i
    }

    static func install(into text: String?, hookPath: String) throws -> String {
        let text = text ?? ""
        if isInstalled(text) { return text }
        if let (index, previous) = rootNotify(in: text) {
            var lines = text.components(separatedBy: "\n")
            lines[index] = render([hookPath, "codex-chain"] + previous)
            return lines.joined(separator: "\n")
        }
        if hasUnparsedRootNotify(text) {
            throw IntegrationError.unreadable("config.toml 의 notify 형식을 읽을 수 없어요. 한 줄 배열로 바꾼 뒤 다시 시도해 주세요")
        }
        // notify는 루트 키라서 첫 [테이블] 앞에 넣어야 한다
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        let firstTable = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.count
        lines.insert(render([hookPath, "codex"]), at: firstTable)
        var result = lines.joined(separator: "\n")
        if !result.hasSuffix("\n") { result += "\n" }
        return result
    }

    static func uninstall(from text: String) -> String {
        guard let (index, args) = rootNotify(in: text) else { return text }
        if args.first?.contains(marker) != true, let i = wrappedIndex(args) {
            // 감싼 도구는 두고, 그 안의 우리 부분만 뺀다. 원래 명령만 남으면(= 감싼 도구 자신) 옵션째 지운다
            let outer = Array(args[..<i]) + Array(args[(i + 2)...])
            let inner = (try? JSONSerialization.jsonObject(with: Data(args[i + 1].utf8))) as? [String] ?? []
            let restored = inner.count > 2 && inner[1] == "codex-chain" ? Array(inner.dropFirst(2)) : []
            var newArgs = outer
            if !restored.isEmpty, restored != Array(args[..<i]),
               let json = try? JSONSerialization.data(withJSONObject: restored), let s = String(data: json, encoding: .utf8) {
                newArgs = Array(args[..<i]) + ["--previous-notify", s] + Array(args[(i + 2)...])
            }
            var lines = text.components(separatedBy: "\n")
            lines[index] = render(newArgs)
            return lines.joined(separator: "\n")
        }
        guard args.first?.contains(marker) == true else { return text }
        var lines = text.components(separatedBy: "\n")
        if args.count > 2, args[1] == "codex-chain" {
            lines[index] = render(Array(args.dropFirst(2)))   // 원래 notify 복원
        } else {
            lines.remove(at: index)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: 아주 작은 TOML 처리 (한 줄짜리 문자열 배열만)

    /// 첫 [테이블] 전에 있는 `notify = [...]` 줄 번호와 값
    static func rootNotify(in text: String) -> (Int, [String])? {
        for (i, raw) in text.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { return nil }
            guard line.hasPrefix("notify"), let eq = line.firstIndex(of: "="),
                  line[..<eq].trimmingCharacters(in: .whitespaces) == "notify" else { continue }
            return parseStringArray(String(line[line.index(after: eq)...])).map { (i, $0) }
        }
        return nil
    }

    private static func hasUnparsedRootNotify(_ text: String) -> Bool {
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { return false }
            if line.hasPrefix("notify") { return true }
        }
        return false
    }

    /// `["a", "b\"c"] # 주석` → ["a", "b\"c"]. 형식이 다르면 nil.
    static func parseStringArray(_ value: String) -> [String]? {
        var s = Substring(value.trimmingCharacters(in: .whitespaces))
        guard s.first == "[" else { return nil }
        s = s.dropFirst()
        var result: [String] = []
        while true {
            s = s.drop { $0 == " " || $0 == "\t" }
            if s.first == "]" { return result }
            guard s.first == "\"" else { return nil }
            s = s.dropFirst()
            var item = ""
            while let c = s.first {
                s = s.dropFirst()
                if c == "\\", let next = s.first {
                    // TOML 기본 문자열 이스케이프. 모르는 건 원래 글자 그대로 둔다 (예전엔 \t → t 로 망가졌다)
                    switch next {
                    case "n": item.append("\n")
                    case "t": item.append("\t")
                    case "r": item.append("\r")
                    case "\"", "\\": item.append(next)
                    default: item.append("\\"); item.append(next)
                    }
                    s = s.dropFirst()
                    continue
                }
                if c == "\"" { break }
                item.append(c)
            }
            result.append(item)
            s = s.drop { $0 == " " || $0 == "\t" }
            if s.first == "," { s = s.dropFirst() }
        }
    }

    static func render(_ args: [String]) -> String {
        let items = args.map {
            "\"" + $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t")
                .replacingOccurrences(of: "\r", with: "\\r") + "\""
        }
        return "notify = [" + items.joined(separator: ", ") + "]"
    }
}

// MARK: - Claude 데스크톱 앱 (~/Library/Application Support/Claude/claude_desktop_config.json)

/// Claude 앱 일반 채팅 알림: `mcpServers.termpet` 항목 하나만 넣고 뺀다 (다른 MCP 서버·설정은 그대로).
/// 형식(공식 문서 modelcontextprotocol.io/docs/develop/connect-local-servers):
///   { "mcpServers": { "termpet": { "command": "/Applications/TermPet.app/Contents/MacOS/TermPet", "args": ["--mcp"] } } }
/// Claude 앱을 완전히 종료했다가 다시 켜야 적용된다.
enum ClaudeDesktopConfig {
    static let key = ClaudeAppMCP.serverName

    static func entry(command: String) -> [String: Any] {
        ["command": command, "args": [ClaudeAppMCP.flag]]
    }

    static func isInstalled(_ data: Data?) -> Bool { server(data) != nil }

    /// 연결은 돼 있는데 실행 경로가 지금 앱과 다르면 (앱을 옮겼거나 예전 설치) → "업데이트"
    static func needsUpdate(_ data: Data?, command: String) -> Bool {
        guard let s = server(data) else { return false }
        return s["command"] as? String != command
    }

    static func install(into data: Data?, command: String) throws -> Data {
        var root = try data.map(parse) ?? [:]
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers[key] = entry(command: command)
        root["mcpServers"] = servers
        return try serialize(root)
    }

    static func uninstall(from data: Data) throws -> Data {
        var root = try parse(data)
        guard var servers = root["mcpServers"] as? [String: Any] else { return data }
        servers[key] = nil
        root["mcpServers"] = servers
        return try serialize(root)
    }

    private static func server(_ data: Data?) -> [String: Any]? {
        guard let data, let root = try? parse(data) else { return nil }
        return (root["mcpServers"] as? [String: Any])?[key] as? [String: Any]
    }

    private static func parse(_ data: Data) throws -> [String: Any] {
        if data.isEmpty { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IntegrationError.unreadable("claude_desktop_config.json 이 올바른 JSON 객체가 아니에요")
        }
        return obj
    }

    private static func serialize(_ root: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .withoutEscapingSlashes])
    }
}
