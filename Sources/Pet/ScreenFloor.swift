import CoreGraphics

/// 화면 바닥 / Dock 발판 계산 (AppKit 비의존 순수 로직 → 테스트 가능).
///
/// - 펫이 서는 진짜 바닥 = 화면 맨 아래(`frame.minY`). 전체 화면 앱이거나 Dock이 숨겨져 있어도 맨 바닥까지 내려간다.
/// - Dock이 아래에 보이면 그 자리에 "발판"(창처럼 다루는 상자)을 하나 둔다
///   → Dock 위에서 놀다가 끝에서 떨어지고, 바닥에서 Dock 옆면을 기어 올라올 수 있다.
enum ScreenFloor {
    /// Dock 발판 상자의 id (실제 창 id와 겹치지 않게 음수). Dock은 한 번에 한 화면에만 있으므로 하나뿐.
    static let dockIDBase = -1000

    static func isDock(_ id: Int?) -> Bool { (id ?? 0) <= dockIDBase }

    /// 펫이 다닐 화면 영역: 아래는 화면 맨 바닥, 위는 메뉴바 아래까지
    static func walkableFrame(frame: CGRect, visible: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: visible.maxY - frame.minY)
    }

    /// 아래쪽 Dock 상자. Dock이 숨겨졌거나(자동 숨김·전체 화면) 옆에 붙어 있으면 nil.
    /// `dockWidth`: Dock 폭 추정값 (모르면 nil → 화면 폭의 60%)
    static func dockBox(frame: CGRect, visible: CGRect, dockWidth: CGFloat?) -> WindowBox? {
        let height = visible.minY - frame.minY
        guard height > 8 else { return nil }
        let width = min(frame.width, max(120, dockWidth ?? frame.width * 0.6))
        // 실제 Dock 몸통은 visibleFrame 경계보다 살짝 아래(위쪽 여백 약 4pt)
        let rect = CGRect(x: frame.midX - width / 2, y: frame.minY, width: width, height: max(8, height - 4))
        return WindowBox(id: dockIDBase, frame: rect)
    }

    /// 펫 몸이 Dock 자리(Dock 뒤)에 들어가 있으면 빼낸다: 몸 중심이 Dock 안이면 Dock 위로, 아니면 옆으로.
    /// 겹치지 않으면 nil. (드래그로 놓았을 때, 던져서 착지했을 때, Dock이 넓어졌을 때)
    static func resolveDockOverlap(origin: CGPoint, size: CGSize, dock: CGRect) -> (origin: CGPoint, onDock: Bool)? {
        guard origin.y < dock.maxY - 0.5, origin.y >= dock.minY - 1,
              origin.x < dock.maxX, origin.x + size.width > dock.minX else { return nil }
        let center = origin.x + size.width / 2
        if center >= dock.minX, center <= dock.maxX {
            return (CGPoint(x: origin.x, y: dock.maxY), true)
        }
        return (CGPoint(x: center < dock.minX ? dock.minX - size.width : dock.maxX, y: origin.y), false)
    }

    /// 전체 화면 앱이 있으면 Dock은 숨겨져 있다.
    /// 판정: 화면 폭을 꽉 채우고, 아래는 화면 맨 바닥(Dock 자리까지)에 닿고, 위는 화면 꼭대기 근처까지 올라간 창.
    /// (노치 있는 MacBook은 전체 화면 창이 노치 줄(약 45pt)을 빼고 잡혀서 화면 frame 전체와 같지 않다.
    ///  최대화(초록 버튼 + Option)한 창은 Dock 위에서 끝나므로 걸리지 않는다)
    static func hasFullscreenWindow(_ windows: [WindowBox], screen: CGRect) -> Bool {
        windows.contains { w in
            let f = w.frame
            return f.minX <= screen.minX + 2 && f.maxX >= screen.maxX - 2
                && f.minY <= screen.minY + 2 && f.maxY >= screen.maxY - 80
        }
    }

    /// Dock 폭 추정: 아이콘 칸 수 × 칸 폭 + 구분선 + 양끝 여백.
    /// 실측(tilesize 55 → 칸 59.3pt, 구분선 26pt, 여백 5pt씩)으로 맞춘 값.
    /// shortcut: 최소화된 창 칸은 설정에 안 나와서 빠진다 → 정확한 값은 손쉬운 사용 권한(AX)으로 읽는다.
    static func estimatedDockWidth(tileSize: CGFloat, items: Int, separators: Int) -> CGFloat {
        CGFloat(items) * tileSize * 1.078 + CGFloat(separators) * tileSize * 0.47 + 10
    }
}
