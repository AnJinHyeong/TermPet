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
        // 옮긴 직후 약 0.25초 동안 실제 마우스 움직임을 무시하는 것을 바로 푼다
        // (매 프레임 옮겨도 사용자가 마우스를 움직일 수 있게 → 움직인 만큼은 컨트롤러가 읽어서 반영)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    /// 마지막으로 옮겨 둔 곳에서 사용자가 마우스를 움직인 만큼 (AppKit 좌표). 1pt 미만은 반올림 오차로 보고 무시
    static func userMove(since warped: CGPoint?, now: CGPoint) -> CGVector {
        guard let warped else { return .zero }
        let d = CGVector(dx: now.x - warped.x, dy: now.y - warped.y)
        return hypot(d.dx, d.dy) < 1 ? .zero : d
    }

    /// 다 옮긴 뒤 호출: 포인터를 옮기면 macOS가 잠깐(약 0.25초) 실제 마우스 움직임을 무시하는데,
    /// 이걸 바로 풀어서 놓아준 즉시 사용자가 마우스를 쓸 수 있게 한다.
    static func finish() {
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
