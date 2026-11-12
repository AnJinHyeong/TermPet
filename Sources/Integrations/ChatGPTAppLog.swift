import Foundation

/// ChatGPT 데스크톱 앱(번들 com.openai.codex)의 일반 GPT 채팅 감지 — 순수 로직. (윈도우판: windows/src/shared/chatgptLog.ts)
///
/// 일반 채팅은 OpenAI 서버에서 돌아서 Codex처럼 notify/훅이 없다. 대신 앱이 자기 로그
/// (~/Library/Logs/com.openai.codex/년/월/일/*.log)에 대화 갱신을 남기므로 그 줄을 읽는다.
/// 공식 형식이 아니라서 앱이 업데이트되면 바뀔 수 있다 (그러면 조용히 아무 알림도 안 올 뿐).
///   …chatgpt_conversation_refetch_completed … conversationId=6af4… reason=explicit_update   ← 답이 끝나 대화가 갱신됨
///   …chatgpt_conversation_update_ignored conversationId=6af4… reason=conversation_not_loaded updateType=completed
///   …[desktop-notifications] show turn-complete conversationId=6af4…                          ← 앱이 직접 띄운 완료 알림
///   …Received turn/started for unknown conversation conversationId=6af4…                      ← 답 시작 (일부 대화만)
/// Codex 대화(UUID v7, 예: 01a1c98a-03f6-7ea0-…)는 notify가 이미 알려 주므로 건너뛴다.
///
/// 주의: `update_ignored … conversation_not_loaded` 는 "이 앱 창에 안 열려 있는 대화"의 서버 소식이라
/// **휴대폰·웹에서 한 대화**가 끝났을 때도 똑같이 찍힌다 (실제로 겪음: 맥에선 아무것도 안 물었는데 알림이 반복).
/// → 이 앱에서 최근에 연 적이 있는 대화(`seen`)일 때만 알린다.
enum ChatGPTAppLog {
    enum Signal: Equatable {
        case started(conversationId: String)
        case completed(conversationId: String)
        /// 이 앱 창에 안 열린 대화가 끝났다는 서버 소식 (다른 기기에서 한 대화일 수 있다)
        case completedElsewhere(conversationId: String)
        /// 이 앱에서 그 대화를 열었거나 갱신했다 (알림은 아니고 "여기서 쓰는 대화" 표시용)
        case seen(conversationId: String)
    }

    static func parse(_ line: String) -> Signal? {
        let ignoredUpdate = line.contains("chatgpt_conversation_update_ignored")
        let started = line.contains("Received turn/started")
        let completed = (line.contains("chatgpt_conversation_refetch_completed") && line.contains("reason=explicit_update"))
            || line.contains("[desktop-notifications] show turn-complete")
        let elsewhere = ignoredUpdate && line.contains("updateType=completed")
        guard let id = conversationId(in: line), !isCodexThread(id) else { return nil }
        if started { return .started(conversationId: id) }
        if completed { return .completed(conversationId: id) }
        if elsewhere { return .completedElsewhere(conversationId: id) }
        // 서버가 밀어 준 소식(update_ignored)·놓친 메시지 따라잡기(missed_messages)는 다른 기기에서 한 대화에도 찍힌다 → 연 것으로 안 친다
        return ignoredUpdate || line.contains("reason=missed_messages") ? nil : .seen(conversationId: id)
    }

    /// `conversationId=<uuid>` 또는 대화 주소 `/c/<uuid>` (앱에서 그 대화를 열면 찍힌다)
    static func conversationId(in line: String) -> String? {
        guard let r = line.range(of: #"(conversationId=|/c/)[0-9a-fA-F-]{36}"#, options: .regularExpression) else { return nil }
        return String(line[r].suffix(36)).lowercased()
    }

    /// Codex 스레드 ID = UUID 버전 7 (세 번째 묶음이 7로 시작). 일반 채팅 ID는 그렇지 않다 (예: 6af42003-045c-83ee-…)
    static func isCodexThread(_ id: String) -> Bool {
        let parts = id.split(separator: "-")
        return parts.count == 5 && parts[2].first == "7"
    }

    /// 로그 폴더 (UTC 날짜별로 나뉜다 — 앱 코드가 getUTCFullYear/Month/Date 로 만든다)
    static func logDirectory(home: URL, date: Date) -> URL {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let c = utc.dateComponents([.year, .month, .day], from: date)
        return home.appendingPathComponent(String(format: "Library/Logs/com.openai.codex/%04d/%02d/%02d",
                                                  c.year ?? 0, c.month ?? 0, c.day ?? 0))
    }

    /// 한 대화의 완료 신호가 여러 줄(갱신 + 앱 알림)로 오므로 이 시간 안의 같은 신호는 한 번만
    static let dedupeWindow: TimeInterval = 20
    /// 이 앱에서 대화를 연 뒤 이 시간 안에 온 "안 열린 대화 완료" 소식만 알린다 (물어 놓고 다른 대화로 넘어간 경우)
    static let localWindow: TimeInterval = 30 * 60

    /// 신호 → 펫 이벤트. 같은 대화의 같은 신호가 방금 있었으면 nil.
    struct Reducer {
        private var last: [String: Date] = [:]
        /// 이 앱에서 열었던 대화 → 마지막으로 본 시각
        private var seen: [String: Date] = [:]

        mutating func event(for signal: Signal, now: Date = Date()) -> PetEvent? {
            let (id, kind): (String, PetEvent.Kind)
            switch signal {
            case .started(let c): (id, kind) = (c, .working)
            case .completed(let c): (id, kind) = (c, .done)
            case .completedElsewhere(let c):
                // 이 앱에서 연 적 없는 대화 = 다른 기기에서 한 대화 → 알리지 않는다
                guard let t = seen[c], now.timeIntervalSince(t) < ChatGPTAppLog.localWindow else { return nil }
                (id, kind) = (c, .done)
            case .seen(let c):
                if seen.count > 200 { seen = seen.filter { now.timeIntervalSince($0.value) < ChatGPTAppLog.localWindow } }
                seen[c] = now
                return nil
            }
            if case .completedElsewhere = signal {} else { seen[id] = now }
            let key = "\(kind.rawValue):\(id)"
            if let t = last[key], now.timeIntervalSince(t) < ChatGPTAppLog.dedupeWindow { return nil }
            if last.count > 200 { last = last.filter { now.timeIntervalSince($0.value) < ChatGPTAppLog.dedupeWindow } }
            last[key] = now
            var event = PetEvent(source: .codex, kind: kind, sessionId: id,
                                 hostBundleId: EventDecoder.chatGPTBundleId, receivedAt: now)
            event.title = "ChatGPT"
            return event
        }
    }
}

/// 로그 파일을 1.5초마다 훑어 새로 붙은 줄만 읽는다 (tail -F 비슷하게).
/// 처음 켤 때 이미 있던 내용은 건너뛰고, 그 뒤에 생긴 파일은 처음부터 읽는다.
@MainActor
final class ChatGPTAppWatcher {
    private let home: URL
    private var timer: Timer?
    private var offsets: [String: UInt64] = [:]
    /// 아직 줄바꿈이 안 온 마지막 조각 (다음에 이어 붙임)
    private var partial: [String: String] = [:]
    private var reducer = ChatGPTAppLog.Reducer()
    var onEvent: ((PetEvent) -> Void)?

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        offsets = [:]
        partial = [:]
        for file in logFiles() { offsets[file.path] = size(of: file) } // 지난 내용은 건너뜀
        // Timer ≈ setInterval. 메인 스레드에서 돌고 파일 몇 개의 새 부분만 읽어서 가볍다
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 오늘·어제 폴더의 .log (자정을 넘겨도 앱이 어제 폴더 파일에 계속 쓰므로)
    private func logFiles() -> [URL] {
        let now = Date()
        let dirs = [now.addingTimeInterval(-86_400), now].map { ChatGPTAppLog.logDirectory(home: home, date: $0) }
        return dirs.flatMap { dir in
            ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "log" }
        }
    }

    private func size(of url: URL) -> UInt64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private func poll() {
        for file in logFiles() {
            let path = file.path
            let end = size(of: file)
            var start = offsets[path] ?? 0
            if end < start { start = 0; partial[path] = nil } // 파일이 새로 써졌으면 처음부터
            guard end > start, let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }
            // 한 번에 너무 많이 읽지 않게 (앱이 로그를 한꺼번에 쏟아낼 때)
            let length = Int(min(end - start, 1 << 20))
            try? handle.seek(toOffset: start)
            guard let data = try? handle.read(upToCount: length) else { continue }
            offsets[path] = start + UInt64(data.count)
            var text = (partial[path] ?? "") + String(decoding: data, as: UTF8.self)
            if let lastBreak = text.lastIndex(of: "\n") {
                partial[path] = String(text[text.index(after: lastBreak)...])
                text = String(text[..<lastBreak])
            } else {
                partial[path] = text
                continue
            }
            for line in text.split(separator: "\n") {
                guard let signal = ChatGPTAppLog.parse(String(line)),
                      let event = reducer.event(for: signal) else { continue }
                onEvent?(event)
            }
        }
    }
}
