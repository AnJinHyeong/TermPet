import CoreGraphics

/// 펫 동작 설정값. Phase 3에서 설정 화면(UserDefaults)과 연결 예정.
struct PetConfig {
    /// 펫 창 크기 (pt)
    var size = CGSize(width: 80, height: 80)
    /// 걷기 속도 (pt/s)
    var walkSpeed: CGFloat = 40
    /// 드래그로 판정할 최소 이동 거리 (pt) — 이보다 짧으면 클릭
    var dragThreshold: CGFloat = 4
    /// 이동 루프 fps
    var fps: Double = 60
    var brain = PetBrain.Config()
}
