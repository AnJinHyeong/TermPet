import AppKit
import CoreGraphics

/// 진짜 마우스 포인터 옮기기 (장난꾸러기 모드에서 물고 흔들기·던지기).
/// 브라우저 JS로는 못 하는 일이지만, 맥 앱은 `CGWarpMouseCursorPosition`으로 포인터를 바로 옮길 수 있다.
enum PointerControl {
    /// AppKit 좌표(좌하단 원점, y 위로) → 포인터를 그 자리로
    static func move(to p: CGPoint) {
        // CG 좌표는 주 화면 좌상단 원점, y 아래로 (WindowScanner와 반대 방향 변환)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        CGWarpMouseCursorPosition(CGPoint(x: p.x, y: primaryHeight - p.y))
    }

    /// 다 옮긴 뒤 호출: 포인터를 옮기면 macOS가 잠깐(약 0.25초) 실제 마우스 움직임을 무시하는데,
    /// 이걸 바로 풀어서 놓아준 즉시 사용자가 마우스를 쓸 수 있게 한다.
    static func finish() {
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
