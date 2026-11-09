import AppKit

/// 캐릭터 크기만 한 투명 창. 이 창 자체를 움직여서 펫을 이동시킨다.
///
/// `NSPanel`은 `NSWindow`의 서브클래스로, 도구 팔레트처럼 "보조 창"에 쓰인다.
/// `.nonactivatingPanel` 덕분에 클릭해도 TermPet이 활성 앱이 되지 않는다
/// → Cursor/VSCode에서 타이핑하던 포커스를 뺏지 않는다.
final class PetWindow: NSPanel {
    init(size: CGSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        // 모든 Space(데스크톱)에 나타나고, 전체화면 앱 위에도 뜨며, Mission Control/⌘` 순환에서 제외
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isFloatingPanel = true
        hidesOnDeactivate = false   // NSPanel 기본값은 "앱 비활성 시 숨김" → 끈다
        becomesKeyOnlyIfNeeded = true
        isMovable = false           // 창 이동은 코드로만
        animationBehavior = .none
        isReleasedWhenClosed = false
    }

    // 키보드 포커스(key)·메인 창이 되지 않음 → 포커스 절대 안 뺏음
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 펫 창의 루트 뷰. 마우스 이벤트를 전부 받아서 컨트롤러에 넘긴다.
/// 내부의 SwiftUI 뷰(NSHostingView)는 그림만 그리고, 이벤트는 여기서 가로챈다.
/// React 비유: 자식 위에 투명한 div를 깔고 onMouseDown 등을 props 콜백으로 올려보내는 구조.
final class PetInteractionView: NSView {
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseDragged: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?
    var onRightMouseDown: ((NSEvent) -> Void)?

    /// 비활성 상태에서도 첫 클릭을 바로 처리 (기본은 "창 활성화용 클릭"으로 소비됨)
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 자식(SwiftUI) 대신 항상 이 뷰가 이벤트를 받도록
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) != nil ? self : nil
    }

    override func mouseDown(with event: NSEvent) { onMouseDown?(event) }
    override func mouseDragged(with event: NSEvent) { onMouseDragged?(event) }
    override func mouseUp(with event: NSEvent) { onMouseUp?(event) }
    override func rightMouseDown(with event: NSEvent) { onRightMouseDown?(event) }
}
