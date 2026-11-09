import Foundation
import Observation

/// SwiftUI 뷰가 구독하는 펫 표시 상태.
/// `@Observable` 클래스 ≈ Zustand 스토어: 프로퍼티를 바꾸면 그 값을 읽은 뷰만 다시 렌더링된다.
@Observable
final class PetViewModel {
    var action: PetAction = .idle
    var facing: Direction = .right
    /// 앱 시작 후 계속 흐르는 애니메이션 시계(초) — 숨쉬기, 눈 깜빡임 등
    var time: TimeInterval = 0
    /// 현재 상태에 들어온 뒤 지난 시간 — 점프 등 상태 시작 기준 애니메이션
    var actionTime: TimeInterval = 0
    var isVisible: Bool = true
}
