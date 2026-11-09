#if DEBUG
import Foundation

extension PetEvent {
    /// 디버그 메뉴용 샘플 이벤트. cwd = 이 프로젝트 폴더, 호스트 = Cursor.
    static func debugSample(_ kind: Kind) -> PetEvent {
        // #filePath = 이 소스 파일의 빌드 시점 경로 → 위로 3단계 = 프로젝트 루트
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path
        switch kind {
        case .done:
            return PetEvent(source: .claude, kind: .done,
                            detail: "리팩터링을 마쳤고 테스트도 모두 통과했습니다.",
                            cwd: projectRoot, sessionId: "debug-done",
                            hostBundleId: HostApp.cursor.bundleId)
        case .error:
            return PetEvent(source: .shell, kind: .error, detail: "npm run build",
                            cwd: projectRoot, command: "npm run build", exitCode: 1, durationSec: 84,
                            hostBundleId: HostApp.cursor.bundleId)
        case .ask:
            return PetEvent(source: .claude, kind: .ask,
                            message: "Claude needs your permission to use Bash",
                            cwd: projectRoot, sessionId: "debug-ask",
                            hostBundleId: HostApp.cursor.bundleId, notificationType: "permission_prompt")
        }
    }
}
#endif
