import Foundation
import Observation

/// SwiftUI 뷰가 구독하는 펫 표시 상태.
/// `@Observable` 클래스 ≈ Zustand 스토어: 프로퍼티를 바꾸면 그 값을 읽은 뷰만 다시 렌더링된다.
@Observable
final class PetViewModel {
    var action: PetAction = .idle
    var facing: Direction = .right
    /// 같은 동작의 여러 포즈 중 무엇을 보여줄지 (두뇌가 상태 진입 때 뽑은 난수)
    var variant: Int = 0
    /// 창 위 산책 켜짐 (메뉴 패널 칩 표시용)
    var walkOnWindows: Bool = true
    /// 장난꾸러기 모드 켜짐 (메뉴 패널 칩 표시용)
    var mischief: Bool = false
    /// 포인터를 물고 흔드는 중 → 화난 얼굴 + 몸 흔들기 + "앙!/으르릉"
    var biting: Bool = false
    /// 물기 시작한 시각 (`time` 기준)
    var biteStart: TimeInterval = 0
    /// 앱 시작 후 계속 흐르는 애니메이션 시계(초) — 숨쉬기, 눈 깜빡임 등
    var time: TimeInterval = 0
    /// 현재 상태에 들어온 뒤 지난 시간 — 점프 등 상태 시작 기준 애니메이션
    var actionTime: TimeInterval = 0
    var isVisible: Bool = true
    var layer: PetWindowLayer = .default
    /// 머리 위 표시: 미확인 알림 "!", 작업 중 "…", 권한 대기 ✋
    var badge: PetBadge = .none
    /// 기분 (최근 성공/실패) → 머리 옆 ✨ / 비구름, 걷는 속도
    var mood: PetMood = .normal
    /// 현재 캐릭터 (기본 도형 캐릭터 또는 스프라이트 팩)
    var character: LoadedCharacter = .builtIn(.mallang)
}
