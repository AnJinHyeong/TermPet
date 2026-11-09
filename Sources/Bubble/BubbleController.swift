import AppKit
import SwiftUI

/// 말풍선 창 + 알림 큐 관리.
/// - 새 알림 → 큐에 넣고 말풍선 표시, 15초 뒤 숨김 (미확인 알림은 펫 머리 위 "!"로 남음)
/// - 말풍선 클릭 → 해당 프로젝트로 이동 + 다음 알림
/// - × 클릭 → 이동 없이 다음 알림
@MainActor
final class BubbleController {
    let model = BubbleViewModel()
    private(set) var queue = NotificationQueue()
    private(set) var isShowing = false {
        didSet { if isShowing != oldValue { onVisibilityChange?(isShowing) } }
    }
    /// 말풍선이 나타나거나 사라질 때 (바탕화면 모드에서 잠깐 앞으로 올리기용)
    var onVisibilityChange: ((Bool) -> Void)?

    /// 말풍선 유지 시간 (Phase 3에서 설정과 연결)
    var displayDuration: TimeInterval = 15
    /// 말풍선(본문) 클릭 시 호출 — 프로젝트로 이동
    var onActivate: ((PetNotification) -> Void)?

    private var window: PetWindow?
    private var host: NSHostingView<BubbleView>?
    private var hideTask: Task<Void, Never>?
    private var petFrame: CGRect = .zero
    private var layer: PetWindowLayer = .default
    private var rng = SystemRandomNumberGenerator()

    var hasUnread: Bool { !queue.isEmpty }

    /// 테스트용: 실제 말풍선 창과 SwiftUI 호스트 뷰
    var windowForTesting: NSWindow? { window }
    var hostForTesting: NSView? { host }

    // MARK: - API

    /// 말풍선 기본 문구 (캐릭터 팩의 messages)
    var messages: BubbleMessages = .default

    func enqueue(_ event: PetEvent) {
        let content = BubbleContent.make(for: event, messages: messages, using: &rng)
        guard queue.push(PetNotification(event: event, content: content)) != .ignored else { return }
        show()
    }

    /// 큐 맨 앞 알림을 표시 (숨겨져 있던 미확인 알림 다시 보기 포함)
    func show() {
        guard let current = queue.current else { hide(); return }
        let window = ensureWindow()

        model.content = current.content
        model.kind = current.event.kind
        model.badge = queue.pendingCount
        model.width = BubbleMetrics.bodyWidth(for: current.content, badge: model.badge)
        resize()
        reposition()
        window.orderFrontRegardless()
        isShowing = true
        scheduleHide()
    }

    func hide() {
        hideTask?.cancel()
        window?.orderOut(nil)
        isShowing = false
    }

    /// 말풍선 본문 클릭: 현재 알림 처리(이동) 후 다음 알림
    func activateCurrent() {
        guard let n = queue.popCurrent() else { return }
        onActivate?(n)
        advance()
    }

    /// × 클릭: 이동 없이 버리고 다음 알림
    func dismissCurrent() {
        queue.popCurrent()
        advance()
    }

    func clearAll() {
        queue.removeAll()
        hide()
    }

    /// 펫 위치가 바뀔 때마다 호출 → 말풍선이 따라감
    func follow(petFrame: CGRect) {
        self.petFrame = petFrame
        if isShowing { reposition() }
    }

    func setLayer(_ layer: PetWindowLayer) {
        self.layer = layer
        window?.apply(layer: layer)
        // 펫보다 한 단계 위에 그려지도록
        window?.level = NSWindow.Level(rawValue: layer.windowLevel.rawValue + 1)
    }

    // MARK: - private

    private func advance() {
        if queue.isEmpty { hide() } else { show() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        let duration = displayDuration
        // Task + sleep ≈ JS의 setTimeout. cancel()로 clearTimeout.
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func ensureWindow() -> PetWindow {
        if let window { return window }
        let window = PetWindow(size: CGSize(width: 200, height: 80))
        let root = PetInteractionView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        let host = NSHostingView(rootView: BubbleView(model: model))
        host.frame = root.bounds
        host.autoresizingMask = [.width, .height]
        root.addSubview(host)
        root.onMouseUp = { [weak self, weak root] event in
            guard let self, let root else { return }
            let p = root.convert(event.locationInWindow, from: nil)
            if self.isCloseButtonHit(p, in: root.bounds) { self.dismissCurrent() } else { self.activateCurrent() }
        }
        window.contentView = root
        self.window = window
        self.host = host
        setLayer(layer)
        return window
    }

    /// × 영역 판정 (AppKit 뷰 좌표: 좌하단 원점) — 오른쪽 위 모서리 근처
    private func isCloseButtonHit(_ p: CGPoint, in bounds: CGRect) -> Bool {
        let top = bounds.maxY - BubbleMetrics.outerPadding - (model.tailOnTop ? BubbleMetrics.tailHeight : 0)
        let right = bounds.maxX - BubbleMetrics.outerPadding
        return p.x >= right - 32 && p.y >= top - 26
    }

    private func resize() {
        guard let window, let host else { return }
        // 너비는 확정값(뷰에 frame(width:)로 고정돼 있어 fittingSize도 이 너비), 높이만 SwiftUI에 물어본다
        let width = model.width + BubbleMetrics.outerPadding * 2
        let size = CGSize(width: width, height: host.fittingSize.height.rounded(.up))
        if window.frame.size != size {
            window.setContentSize(size)
        }
        // host 크기는 직접 건드리지 않고 항상 창 내용 영역에 정확히 맞춘다.
        // (주의: host.frame을 먼저 바꾼 뒤 창을 키우면 autoresizing이 차이만큼 또 더해서
        //  host가 창보다 넓어지고 내용이 밀려 잘린다 — 실제로 겪은 버그)
        if let root = window.contentView, host.frame != root.bounds {
            host.frame = root.bounds
        }
    }

    private func reposition() {
        guard let window else { return }
        let center = CGPoint(x: petFrame.midX, y: petFrame.midY)
        let screen = (NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main)?.visibleFrame
            ?? petFrame.insetBy(dx: -500, dy: -500)
        let placement = BubblePlacement.place(bubbleSize: window.frame.size, petFrame: petFrame, screen: screen)
        if model.tailX != placement.tailX { model.tailX = placement.tailX }
        if model.tailOnTop != placement.below { model.tailOnTop = placement.below }
        if window.frame.origin != placement.origin { window.setFrameOrigin(placement.origin) }
    }
}
