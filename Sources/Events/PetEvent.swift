import Foundation

/// 앱 내부 표준 이벤트. 어떤 소스(Claude Code / Codex / 쉘)에서 왔든 이 형태로 통일한다.
/// TS로 치면 `interface PetEvent { ... }`. `?`가 붙은 타입은 옵셔널(`string | undefined`).
struct PetEvent: Equatable, Identifiable {
    enum Source: String, Equatable { case claude, codex, shell }
    enum Kind: String, Equatable { case done, error, ask }

    let id: UUID
    var source: Source
    var kind: Kind
    /// 말풍선에 그대로 표시할 문구 (없으면 캐릭터 팩의 랜덤 문구)
    var message: String?
    /// 보조 설명 (예: Claude의 마지막 답변 첫 줄, 쉘 명령어)
    var detail: String?
    var cwd: String?
    var sessionId: String?
    var transcriptPath: String?
    var command: String?
    var exitCode: Int?
    var durationSec: Double?
    /// 통합 터미널이 상속한 호스트 앱 번들 ID (`__CFBundleIdentifier`)
    var hostBundleId: String?
    /// `TERM_PROGRAM` 환경변수 (vscode, iTerm.app, Apple_Terminal 등)
    var termProgram: String?
    /// Claude Code Notification 훅의 notification_type (permission_prompt, idle_prompt 등)
    var notificationType: String?
    var receivedAt: Date

    init(id: UUID = UUID(), source: Source, kind: Kind, message: String? = nil, detail: String? = nil,
         cwd: String? = nil, sessionId: String? = nil, transcriptPath: String? = nil,
         command: String? = nil, exitCode: Int? = nil, durationSec: Double? = nil,
         hostBundleId: String? = nil, termProgram: String? = nil,
         notificationType: String? = nil, receivedAt: Date = Date()) {
        self.id = id
        self.source = source
        self.kind = kind
        self.message = message
        self.detail = detail
        self.cwd = cwd
        self.sessionId = sessionId
        self.transcriptPath = transcriptPath
        self.command = command
        self.exitCode = exitCode
        self.durationSec = durationSec
        self.hostBundleId = hostBundleId
        self.termProgram = termProgram
        self.notificationType = notificationType
        self.receivedAt = receivedAt
    }

    /// cwd의 마지막 폴더명 = 프로젝트 이름 (예: /Users/me/fitin → "fitin")
    var projectName: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }

    /// "Claude가 입력을 기다리는 중" 류의 반복성 알림인지
    var isIdlePrompt: Bool { notificationType == "idle_prompt" }

    /// 이벤트 → 펫 감정
    var mood: PetAction {
        switch kind {
        case .done: return .happy
        case .error: return .angry
        case .ask: return .ask
        }
    }
}
