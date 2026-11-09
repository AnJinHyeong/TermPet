import AppKit
import SwiftUI

/// 펫 한 마리를 총괄: 창 생성, 60fps 루프, 마우스 입력 → 두뇌(PetBrain)/물리(PetPhysics) → 창 위치·뷰 갱신.
/// 순수 로직은 PetBrain/PetPhysics에 있고, 여기는 AppKit과 연결하는 "접착제" 역할만 한다.
///
/// `@MainActor` = 이 클래스의 코드는 항상 메인(UI) 스레드에서 실행된다는 표시.
/// (브라우저 JS는 원래 단일 스레드라 신경 쓸 필요가 없지만, Swift는 명시해야 한다.)
/// `NSObject`를 상속하는 이유: 타이머·메뉴의 `#selector`(Objective-C 방식 콜백)를 쓰기 위해.
@MainActor
final class PetController: NSObject {
    let model = PetViewModel()

    private let config: PetConfig
    private var brain: PetBrain
    private var physics: PetPhysics
    private var layout = ScreenLayout(frames: [])
    private var rng = SystemRandomNumberGenerator()

    private var window: PetWindow?
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0

    // 드래그 상태
    private var mouseDownLocation: CGPoint?
    private var dragOffset: CGPoint = .zero
    private var isDragging = false

    init(config: PetConfig = PetConfig()) {
        self.config = config
        self.brain = PetBrain(config: config.brain)
        self.physics = PetPhysics(origin: .zero, size: config.size)
        super.init()
    }

    // MARK: - 시작

    func start() {
        guard window == nil else { return }
        refreshLayout()

        // 처음엔 메인 화면 바닥 가운데에 세운다
        if let main = NSScreen.main?.visibleFrame ?? layout.frames.first {
            physics.origin = CGPoint(x: main.midX - config.size.width / 2, y: main.minY)
        }

        let window = PetWindow(size: config.size)
        let root = PetInteractionView(frame: NSRect(origin: .zero, size: config.size))
        // NSHostingView: SwiftUI 뷰를 AppKit 뷰 안에 올리는 어댑터
        // (React 비유: 다른 프레임워크 안에 React 루트를 하나 마운트하는 것)
        let host = NSHostingView(rootView: PetView(model: model))
        host.frame = root.bounds
        host.autoresizingMask = [.width, .height]
        root.addSubview(host)

        root.onMouseDown = { [weak self] e in self?.mouseDown(e) }
        root.onMouseDragged = { [weak self] e in self?.mouseDragged(e) }
        root.onMouseUp = { [weak self] e in self?.mouseUp(e) }
        root.onRightMouseDown = { [weak self] e in self?.showContextMenu(e, in: root) }

        window.contentView = root
        model.layer = PetWindowLayer.load()
        window.apply(layer: model.layer)
        window.setFrameOrigin(physics.origin)
        window.orderFrontRegardless() // 앱을 활성화하지 않고 앞에 띄움
        self.window = window

        // 모니터 연결/해제, 해상도·Dock 변경 감지
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        startTimer()
    }

    private func startTimer() {
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / config.fps, target: self,
                          selector: #selector(timerFired), userInfo: nil, repeats: true)
        // .common 모드: 메뉴가 열려 있거나 드래그 중에도 루프가 멈추지 않게
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - 외부 API (메뉴바/우클릭 메뉴에서 호출)

    var isSleeping: Bool { brain.action == .sleep }

    func toggleSleep() {
        brain.handle(isSleeping ? .wake : .sleep, using: &rng)
        syncModel()
    }

    func react(_ action: PetAction) {
        brain.handle(.react(action), using: &rng)
        syncModel()
    }

    func setVisible(_ visible: Bool) {
        model.isVisible = visible
        if visible { window?.orderFrontRegardless() } else { window?.orderOut(nil) }
    }

    /// 표시 층 변경 (프로그램 위 / 바탕화면) + 저장
    func setLayer(_ layer: PetWindowLayer) {
        model.layer = layer
        layer.save()
        window?.apply(layer: layer)
        if model.isVisible { window?.orderFrontRegardless() }
    }

    /// 디버그용: 화면 위쪽에서 떨어뜨리기
    func dropFromTop() {
        refreshLayout()
        guard let i = layout.index(containingX: physics.centerX, y: physics.origin.y)
                ?? layout.nearestIndex(toX: physics.centerX) else { return }
        physics.origin.y = layout.frames[i].maxY - config.size.height
        beginFall()
    }

    // MARK: - 루프

    @objc private func timerFired() {
        let now = CACurrentMediaTime()
        // 슬립에서 깨어났거나 렉이 걸렸을 때 한 번에 순간이동하지 않도록 dt 상한
        let dt = min(now - lastTick, 1.0 / 15)
        lastTick = now
        step(dt)
    }

    private func step(_ dt: TimeInterval) {
        brain.tick(dt, using: &rng)

        switch brain.action {
        case .walk:
            switch physics.walk(direction: brain.direction, speed: config.walkSpeed,
                                dt: dt, layout: layout) {
            case .moved: break
            case .hitWall: brain.handle(.hitWall, using: &rng)
            case .startFalling: beginFall()
            }
        case .fall:
            if physics.fall(dt: dt, layout: layout) {
                brain.handle(.landed, using: &rng)
            }
        default:
            break
        }

        if !isDragging, let window, window.frame.origin != physics.origin {
            window.setFrameOrigin(physics.origin)
        }
        model.time += dt
        syncModel()
    }

    /// 두뇌 상태 → 뷰 모델 복사 (SwiftUI 재렌더 트리거)
    private func syncModel() {
        if model.action != brain.action { model.action = brain.action }
        if model.facing != brain.direction { model.facing = brain.direction }
        model.actionTime = brain.elapsed
    }

    private func beginFall() {
        physics.prepareFall(layout: layout)
        brain.handle(.startFall, using: &rng)
    }

    private func refreshLayout() {
        layout = ScreenLayout(frames: NSScreen.screens.map(\.visibleFrame))
    }

    @objc private func screensChanged() {
        refreshLayout()
        // 바닥 높이가 바뀌었을 수 있으니 다시 떨어뜨려서 자리 잡기
        if !isDragging { beginFall() }
    }

    // MARK: - 마우스

    private func mouseDown(_ event: NSEvent) {
        // NSEvent.mouseLocation: 화면 전체 기준 마우스 좌표 (좌하단 원점)
        let p = NSEvent.mouseLocation
        mouseDownLocation = p
        dragOffset = CGPoint(x: p.x - physics.origin.x, y: p.y - physics.origin.y)
        isDragging = false
    }

    private func mouseDragged(_ event: NSEvent) {
        guard let start = mouseDownLocation else { return }
        let p = NSEvent.mouseLocation
        if !isDragging {
            guard hypot(p.x - start.x, p.y - start.y) >= config.dragThreshold else { return }
            isDragging = true
            brain.handle(.dragStarted, using: &rng)
            syncModel()
        }
        physics.origin = CGPoint(x: p.x - dragOffset.x, y: p.y - dragOffset.y)
        window?.setFrameOrigin(physics.origin)
    }

    private func mouseUp(_ event: NSEvent) {
        defer { mouseDownLocation = nil }
        if isDragging {
            isDragging = false
            refreshLayout()
            beginFall()
            return
        }
        if event.clickCount >= 2 {
            openViewer()
        } else {
            // TODO(Phase 2): 말풍선이 있으면 말풍선 동작
            brain.handle(.clicked, using: &rng)
        }
        syncModel()
    }

    private func openViewer() {
        // TODO(Phase 4): 터미널 확장판 창 열기
    }

    // MARK: - 우클릭 메뉴

    private func showContextMenu(_ event: NSEvent, in view: NSView) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let viewer = NSMenuItem(title: "터미널 확장판 열기", action: nil, keyEquivalent: "")
        viewer.isEnabled = false // Phase 4
        menu.addItem(viewer)

        let sleep = NSMenuItem(title: isSleeping ? "깨우기" : "재우기",
                               action: #selector(menuToggleSleep), keyEquivalent: "")
        sleep.target = self
        menu.addItem(sleep)

        // 표시 위치 하위 메뉴 (현재 선택에 체크 표시)
        let layerItem = NSMenuItem(title: "표시 위치", action: nil, keyEquivalent: "")
        let layerMenu = NSMenu()
        for layer in PetWindowLayer.allCases {
            let item = NSMenuItem(title: layer.title, action: #selector(menuSelectLayer(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = layer.rawValue
            item.state = layer == model.layer ? .on : .off
            layerMenu.addItem(item)
        }
        layerItem.submenu = layerMenu
        menu.addItem(layerItem)

        let settings = NSMenuItem(title: "설정…", action: nil, keyEquivalent: "")
        settings.isEnabled = false // Phase 3
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "TermPet 종료", action: #selector(menuQuit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func menuToggleSleep() { toggleSleep() }
    @objc private func menuSelectLayer(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let layer = PetWindowLayer(rawValue: raw) else { return }
        setLayer(layer)
    }
    @objc private func menuQuit(){ NSApplication.shared.terminate(nil) }
}

/// 펫 창 안의 SwiftUI 루트 뷰. Phase 3에서 캐릭터 팩(스프라이트) 렌더러로 교체 가능하게 분리.
struct PetView: View {
    let model: PetViewModel

    var body: some View {
        DefaultCharacterView(
            action: model.action,
            facing: model.facing,
            time: model.time,
            actionTime: model.actionTime
        )
    }
}
