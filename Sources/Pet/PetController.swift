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
    let bubble = BubbleController()
    /// 진행 중인 AI 세션 목록 (메뉴 패널 "진행 중"에서도 읽음)
    let sessions = SessionStore()
    /// 조용한 시간 / 권한 요청 소리 설정
    let quiet = QuietMode()
    /// 오늘 하루 기록
    let stats = StatsStore()
    /// 최근 성공/실패 (기분 계산용, 최근 20개만)
    private var outcomes: [(Date, Bool)] = []
    private var lastPrune: CFTimeInterval = 0

    private let config: PetConfig
    private var brain: PetBrain
    private var physics: PetPhysics
    private var layout = ScreenLayout(frames: [])
    /// 화면 + 앱 창 지형 (창 위 산책이 꺼져 있거나 바탕화면 층이면 창 없이 화면만)
    private var terrain = Terrain(screens: ScreenLayout(frames: []))
    /// 지금 기어오르는 벽
    private var climbingWall: Terrain.Wall?
    /// 손을 놓을 높이 (꼭대기에 올라설 곳이 없는 벽)
    private var climbLimitY: CGFloat = .infinity
    private var lastWindowScan: CFTimeInterval = 0
    /// 화면 아래 Dock 발판들 (창 위 산책 설정과 무관하게 항상 지형에 포함)
    private var docks: [WindowBox] = []
    private var lastDockCheck: CFTimeInterval = 0
    private var rng = SystemRandomNumberGenerator()

    /// 창 위를 걷고 기어오르기 (메뉴 패널 '창 위 산책' 칩)
    static let walkOnWindowsKey = "walkOnWindows"
    var walkOnWindows: Bool = UserDefaults.standard.object(forKey: PetController.walkOnWindowsKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(walkOnWindows, forKey: Self.walkOnWindowsKey)
            model.walkOnWindows = walkOnWindows
            rescanWindows(force: true)
            if !isDragging, physics.standingOn.map({ !ScreenFloor.isDock($0) }) ?? false || brain.action == .climb { beginFall() }
        }
    }

    private var window: PetWindow?
    /// 캐릭터 팩에 walkSpeed가 있으면 그 값, 없으면 설정값
    private var walkSpeed: CGFloat
    /// 캐릭터 목록 (우클릭 메뉴에서 선택용). AppDelegate가 주입.
    var library: CharacterLibrary?
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0

    // 드래그 상태
    private var mouseDownLocation: CGPoint?
    private var dragOffset: CGPoint = .zero
    private var isDragging = false
    /// 던지기 속도 계산용 최근 마우스 위치들 (시간, 위치)
    private var dragTrail: [(CFTimeInterval, CGPoint)] = []

    init(config: PetConfig = PetConfig()) {
        self.config = config
        self.brain = PetBrain(config: config.brain)
        self.physics = PetPhysics(origin: .zero, size: config.size)
        self.walkSpeed = config.walkSpeed
        super.init()
        bubble.onActivate = { ProjectFocuser.focus($0.event) }
        bubble.onVisibilityChange = { [weak self] _ in self?.applyEffectiveLayer() }
        quiet.onChange = { [weak self] isQuiet in self?.bubble.isQuiet = isQuiet }
    }

    // MARK: - 시작

    func start() {
        guard window == nil else { return }
        refreshLayout()

        // 처음엔 메인 화면 바닥 가운데에 세운다
        if let main = NSScreen.main ?? NSScreen.screens.first {
            // 가운데(= Dock이 있으면 Dock 위)에 세운다
            physics.origin = CGPoint(x: main.frame.midX - physics.size.width / 2, y: main.frame.minY)
            liftOutOfDock()
        }

        let window = PetWindow(size: physics.size)
        let root = PetInteractionView(frame: NSRect(origin: .zero, size: physics.size))
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
        model.walkOnWindows = walkOnWindows
        applyEffectiveLayer()
        window.setFrameOrigin(physics.origin)
        window.orderFrontRegardless() // 앱을 활성화하지 않고 앞에 띄움
        self.window = window

        // 모니터 연결/해제, 해상도·Dock 변경 감지
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // 데스크톱(Space) 전환 = 전체 화면 앱으로 들어가거나 나옴 → Dock 발판을 바로 다시 계산
        // (NSWorkspace 알림은 별도 알림 센터를 쓴다 ≈ 다른 이벤트 버스에 구독)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        startTimer()
        quiet.start()
    }

    private var timerFPS: Double = 0

    /// 움직일 때만 60fps, 가만히 있을 땐 낮춰서 CPU/배터리 절약 (스프라이트는 6~12fps라 눈으로 차이 없음)
    static func loopFPS(for action: PetAction, maxFPS: Double) -> Double {
        switch action {
        case .fall, .dragged: return maxFPS      // 빠르게 움직일 때만 60fps
        case .climb: return min(maxFPS, 30)
        case .walk: return min(maxFPS, 30)       // 걷기는 느려서(약 35pt/s) 30fps로도 부드러움
        case .idle: return min(maxFPS, 12)    // 숨쉬기·눈 깜빡임 정도라 12fps면 충분 (대부분의 시간)
        case .sleep: return min(maxFPS, 6)
        default: return min(maxFPS, 30)       // 신남·화남 등 짧은 반응은 부드럽게
        }
    }

    private func startTimer(fps: Double? = nil) {
        timer?.invalidate()
        timerFPS = fps ?? config.fps
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / timerFPS, target: self,
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
        if visible {
            window?.orderFrontRegardless()
            if timer == nil { startTimer() }
        } else {
            window?.orderOut(nil)
            bubble.hide() // 미확인 알림은 큐에 남아 있다가 다시 보이면 "!"로 표시
            timer?.invalidate() // 숨긴 동안은 루프를 멈춰 CPU 0
            timer = nil
            timerFPS = 0
        }
    }

    /// 외부 이벤트(Claude 완료, 쉘 명령 실패 등) 수신 → 감정 표현 + 말풍선
    func receive(_ incoming: PetEvent) {
        var event = incoming
        sessions.apply(event)
        guard event.isNotification else {
            // 작업 시작·도구 실행·세션 종료: 세션이 다시 움직였으면 그 세션의 지난 알림(권한 요청 등)은 해결된 것
            if sessions.state(of: event) != .waiting { bubble.resolve(sessionOf: event) }
            return
        }
        stats.record(event)
        if event.kind == .done || event.kind == .error {
            let wasGloomy = model.mood == .gloomy
            outcomes.append((Date(), event.kind == .done))
            if outcomes.count > 20 { outcomes.removeFirst(outcomes.count - 20) }
            updateMood()
            // 계속 실패하다가 드디어 성공하면 한마디
            if wasGloomy, event.kind == .done, event.message == nil {
                event.message = ["휴, 이번엔 됐다!", "드디어 성공!", "됐다…! 다행이야"].randomElement(using: &rng)
            }
        }
        brain.handle(.react(event.mood, duration: 3), using: &rng)
        syncModel()
        bubble.enqueue(event)
        if !model.isVisible { bubble.hide() }
        if BubbleController.isSticky(event), quiet.soundOnAsk, !quiet.isQuiet, model.isVisible {
            NSSound(named: "Glass")?.play() // 권한 요청은 작업이 멈춘 상태라 소리로 한 번 더 알림
        }
    }

    private func updateMood(now: Date = Date()) {
        let mood = PetMood.from(outcomes, now: now)
        if model.mood != mood { model.mood = mood }
    }

    /// 표시 층 변경 (프로그램 위 / 바탕화면) + 저장
    func setLayer(_ layer: PetWindowLayer) {
        model.layer = layer
        layer.save()
        applyEffectiveLayer()
        // 바탕화면 층에선 창 뒤에 숨으므로 창 위를 다니지 않는다 → 창 위에 있었다면 내려온다
        rescanWindows(force: true)
        if !isDragging, physics.standingOn.map({ !ScreenFloor.isDock($0) }) ?? false || brain.action == .climb { beginFall() }
    }

    /// 실제로 적용할 층: "바탕화면에만 + 알림 시 앞으로" 모드면 말풍선(알림)이 떠 있는 동안만
    /// 펫과 말풍선을 앱 창 위로 올렸다가, 말풍선이 사라지면 다시 바탕화면 층으로 내린다.
    private func applyEffectiveLayer() {
        let effective = PetWindowLayer.effective(model.layer, bubbleShowing: bubble.isShowing)
        window?.apply(layer: effective)
        bubble.setLayer(effective)
        if model.isVisible { window?.orderFrontRegardless() }
    }

    /// 캐릭터 교체: 창 크기·걷기 속도·말풍선 문구를 캐릭터에 맞춘다.
    func setCharacter(_ character: LoadedCharacter) {
        model.character = character
        walkSpeed = character.walkSpeed ?? config.walkSpeed
        bubble.messages = character.messages

        let newSize = character.size
        guard newSize != physics.size else { return }
        // 발 위치(바닥)와 가로 중심은 유지한 채 크기만 바꾼다
        physics.origin.x += (physics.size.width - newSize.width) / 2
        physics.size = newSize
        window?.setContentSize(newSize)
        window?.setFrameOrigin(physics.origin)
        rebuildTerrain(windows: appWindows)
        if !isDragging { beginFall() } // 화면 밖으로 삐져나갔으면 보정
    }

    /// 라이브러리에서 id로 캐릭터를 골라 적용. 불러오기 실패 시 기본 캐릭터 + 에러 메시지 반환.
    @discardableResult
    func selectCharacter(id: String) -> String? {
        guard let library, let entry = library.entries.first(where: { $0.id == id }) else { return nil }
        do {
            setCharacter(try library.load(entry))
            library.select(id)
            return nil
        } catch {
            // 목록에 있는 다른 캐릭터(첫 친구)로. 그것도 안 되면 내장 캐릭터
            let fallback = library.entries.first { $0.id != id }
            if let fallback, let loaded = try? library.load(fallback) {
                setCharacter(loaded)
                library.select(fallback.id)
            } else {
                setCharacter(.builtIn(.mallang))
            }
            return "\(entry.name): \(error)"
        }
    }

    /// 화면 위쪽에서 떨어뜨리기 (창 위에 떨어지면 거기서 논다)
    func dropFromTop() {
        refreshLayout()
        guard let i = layout.index(containingX: physics.centerX, y: physics.origin.y)
                ?? layout.nearestIndex(toX: physics.centerX) else { return }
        physics.origin.y = layout.frames[i].maxY - physics.size.height
        // 화면 어딘가 랜덤한 가로 위치에서
        let f = layout.frames[i]
        physics.origin.x = CGFloat.random(in: f.minX...(max(f.minX, f.maxX - physics.size.width)), using: &rng)
        window?.setFrameOrigin(physics.origin)
        beginFall()
    }

    // MARK: - 루프

    @objc private func timerFired() {
        let now = CACurrentMediaTime()
        // 슬립에서 깨어났거나 렉이 걸렸을 때 한 번에 순간이동하지 않도록 dt 상한
        let dt = min(now - lastTick, 0.2)
        lastTick = now
        step(dt)
    }

    private func step(_ dt: TimeInterval) {
        brain.tick(dt, using: &rng)
        if !isDragging { rescanWindows() }

        switch brain.action {
        case .walk:
            switch physics.walk(direction: brain.direction, speed: currentWalkSpeed, dt: dt, terrain: terrain) {
            case .moved: break
            case .hitWall(let wall):
                brain.handle(.hitWall(window: wall.windowID != nil), using: &rng)
                if brain.action == .climb { startClimbing(wall) }
            case .reachedEdge:
                brain.handle(.reachedEdge, using: &rng)
                if brain.action == .fall {
                    // 선반 끝에서 폴짝 뛰어내리기
                    physics.prepareFall(terrain: terrain, velocity: CGVector(dx: brain.direction.sign * 110, dy: 420))
                }
            case .startFalling: beginFall()
            }
        case .climb:
            stepClimb(dt)
        case .fall:
            if physics.fall(dt: dt, terrain: terrain) {
                liftOutOfDock() // 던져져서 Dock 뒤 바닥에 떨어졌으면 Dock 위/옆으로
                brain.handle(.landed, using: &rng)
            }
        default:
            // 가만히 서 있는데 발밑 창이 사라졌으면(닫힘·최소화·가려짐) 떨어진다
            if !isDragging, !brain.action.isPhysicsControlled, let id = physics.standingOn,
               terrain.ledge(atX: physics.centerX, y: physics.origin.y, windowID: id) == nil {
                beginFall()
            }
        }

        if !isDragging, let window, window.frame.origin != physics.origin {
            window.setFrameOrigin(physics.origin)
        }
        bubble.follow(petFrame: CGRect(origin: physics.origin, size: physics.size))
        // 오래된 세션 정리·기분 풀림은 10초에 한 번이면 충분
        if lastTick - lastPrune > 10 { lastPrune = lastTick; sessions.prune(); updateMood() }
        // 신날 때는 가만히 있다가 가끔 깡충 (평균 20초에 한 번)
        if model.mood == .cheerful, brain.action == .idle, Double.random(in: 0..<1, using: &rng) < dt / 20 {
            brain.handle(.react(.happy, duration: 1.2), using: &rng)
        }
        let badge = PetBadge.pick(waiting: sessions.tracker.waitingCount, working: sessions.tracker.workingCount,
                                  hasUnread: bubble.hasUnread && !bubble.isShowing)
        if model.badge != badge { model.badge = badge }
        model.time += dt
        syncModel()

        var wanted = Self.loopFPS(for: brain.action, maxFPS: config.fps)
        // 창 위에 있으면 창을 끌 때 매끄럽게 따라가도록 조금 더 자주
        if let id = physics.standingOn, !ScreenFloor.isDock(id) { wanted = max(wanted, min(config.fps, 20)) }
        if wanted != timerFPS { startTimer(fps: wanted) }
    }

    /// 두뇌 상태 → 뷰 모델 복사 (SwiftUI 재렌더 트리거)
    private func syncModel() {
        if model.action != brain.action { model.action = brain.action }
        if model.facing != brain.direction { model.facing = brain.direction }
        if model.variant != brain.variant { model.variant = brain.variant }
        model.actionTime = brain.elapsed
    }

    private func beginFall(velocity: CGVector = .zero) {
        climbingWall = nil
        physics.prepareFall(terrain: terrain, velocity: velocity)
        brain.handle(.startFall, using: &rng)
    }

    /// 걷기 속도: 기분 반영 + 달리기 포즈(walk.2)가 뽑히면 빠르게
    private var currentWalkSpeed: CGFloat {
        var speed = walkSpeed * model.mood.walkFactor
        if case .sprite(let s) = model.character, s.variantCount(for: .walk) > 1,
           brain.variant % s.variantCount(for: .walk) == 1 {
            speed *= 1.9
        }
        return speed
    }

    private func refreshLayout() {
        // 바닥 = 화면 맨 아래 (전체 화면 앱·Dock 숨김일 때도 맨 바닥까지)
        layout = ScreenLayout(frames: NSScreen.screens.map { ScreenFloor.walkableFrame(frame: $0.frame, visible: $0.visibleFrame) })
        refreshDocks()
        rebuildTerrain(windows: appWindows)
    }

    /// Dock 발판 다시 계산 (Dock 크기·실행 중인 앱 수가 바뀔 수 있어서 가끔 갱신)
    private func refreshDocks() {
        lastDockCheck = CACurrentMediaTime()
        let width = WindowScanner.dockWidth()
        let windows = WindowScanner.scan()
        // Dock은 한 화면에만 있다. 그 화면을 전체 화면 앱이 덮고 있으면 Dock은 숨어 있으니 발판도 없다
        docks = NSScreen.screens.lazy.compactMap { s -> WindowBox? in
            guard !ScreenFloor.hasFullscreenWindow(windows, screen: s.frame) else { return nil }
            return ScreenFloor.dockBox(frame: s.frame, visible: s.visibleFrame, dockWidth: width)
        }.first.map { [$0] } ?? []
    }

    /// 바닥에 서 있는데 Dock 자리(Dock 뒤)에 들어가 있으면 Dock 위로 올린다
    /// (처음 시작할 때, Dock이 넓어졌을 때)
    private func liftOutOfDock() {
        guard physics.standingOn == nil, let dock = docks.first,
              let fix = ScreenFloor.resolveDockOverlap(origin: physics.origin, size: physics.size, dock: dock.frame) else { return }
        physics.origin = fix.origin
        if fix.onDock { physics.standingOn = dock.id }
        window?.setFrameOrigin(physics.origin)
    }

    /// 지형의 창 목록에서 Dock 발판을 뺀 실제 앱 창들
    private var appWindows: [WindowBox] { terrain.windows.filter { !ScreenFloor.isDock($0.id) } }

    // MARK: - 창 지형

    /// 창 위를 다닐 수 있는 상태인지 (설정 켜짐 + '프로그램 위' 층일 때만. 바탕화면 층은 창 뒤라 안 됨)
    private var usesWindows: Bool { walkOnWindows && model.layer == .aboveApps }

    private func rebuildTerrain(windows: [WindowBox]) {
        // Dock은 맨 앞(가장 위에 그려짐)에 둔다
        terrain = Terrain(screens: layout, windows: docks + (usesWindows ? windows : []), petSize: physics.size)
    }

    /// 창 목록 다시 읽기. 창 위에 있거나 매달려 있으면 자주(창을 끌면 따라가게), 아니면 가끔.
    private func rescanWindows(force: Bool = false) {
        let now = CACurrentMediaTime()
        if now - lastDockCheck > 1 { // Dock 크기 변화(앱 실행·종료)를 빨리 반영
            let old = docks
            refreshDocks()
            if old != docks {
                rebuildTerrain(windows: appWindows)
                if ScreenFloor.isDock(climbingWall?.windowID) || ScreenFloor.isDock(physics.standingOn) {
                    // Dock 크기가 바뀌었다: 매달려 있거나 서 있던 자리가 달라졌으니 다시 자리 잡기
                    if !isDragging { beginFall() }
                } else if !isDragging, !brain.action.isPhysicsControlled {
                    liftOutOfDock()
                }
            }
        }
        guard usesWindows else {
            if !appWindows.isEmpty || force { rebuildTerrain(windows: []) }
            return
        }
        let onWindow = (physics.standingOn.map { !ScreenFloor.isDock($0) } ?? false)
            || (climbingWall?.windowID.map { !ScreenFloor.isDock($0) } ?? false)
        let interval = onWindow ? 1.0 / 20 : (brain.action == .walk || brain.action == .fall ? 0.25 : 0.6)
        guard force || now - lastWindowScan >= interval else { return }
        lastWindowScan = now
        let old = terrain
        rebuildTerrain(windows: WindowScanner.scan())

        // 서 있던 창이 움직였으면 같이 이동 (창을 끌면 펫도 실려 간다)
        if let id = physics.standingOn {
            if let before = old.window(id: id)?.frame, let after = terrain.window(id: id)?.frame, before != after {
                physics.ride(from: before, to: after)
                if !isDragging { window?.setFrameOrigin(physics.origin) }
            }
        }
        // 매달린 벽(창)이 움직이거나 사라지면 따라가거나 떨어진다
        if let wall = climbingWall, let id = wall.windowID {
            if let after = terrain.window(id: id)?.frame {
                let x = wall.side == .right ? after.minX : after.maxX
                if let before = old.window(id: id)?.frame { physics.ride(from: before, to: after) }
                climbingWall = Terrain.Wall(x: x, top: after.maxY, windowID: id, side: wall.side)
            } else {
                beginFall()
            }
        }
    }

    // MARK: - 벽 오르기

    private func startClimbing(_ wall: Terrain.Wall) {
        climbingWall = wall
        physics.standingOn = nil
        if wall.windowID != nil, terrain.ledgeAfterClimbing(wall) != nil {
            climbLimitY = .infinity            // 창 꼭대기까지 올라가서 올라선다
        } else {
            // 올라설 곳이 없는 벽(화면 끝, 가려진 창 꼭대기): 적당히 오르다 뛰어내린다
            let top = min(wall.top, terrain.ceiling(atX: physics.centerX) ?? wall.top) - physics.size.height
            let room = max(0, top - physics.origin.y)
            climbLimitY = physics.origin.y + room * CGFloat.random(in: 0.25...0.7, using: &rng)
        }
    }

    private func stepClimb(_ dt: TimeInterval) {
        guard let wall = climbingWall else { beginFall(); return }
        // 가끔 힘이 빠져서 미끄러진다 (평균 50초에 한 번)
        if Double.random(in: 0..<1, using: &rng) < dt / 50 {
            brain.handle(.letGo, using: &rng)
            beginFall(velocity: CGVector(dx: -wall.side.sign * 60, dy: 0))
            return
        }
        // 위쪽을 앞 창이 막고 있으면 그 아래까지만 (가려진 벽을 계속 타지 않게)
        let limit = min(climbLimitY, terrain.climbCeiling(for: wall, feetY: physics.origin.y) ?? .infinity)
        switch physics.climb(wall, speed: max(walkSpeed * 1.3, 50), dt: dt, terrain: terrain, limitY: limit) {
        case .climbing:
            break
        case .reachedTop:
            climbingWall = nil
            brain.handle(.climbedUp, using: &rng)
        case .letGo:
            brain.handle(.letGo, using: &rng)
            // 벽을 차고 반대쪽으로 폴짝
            beginFall(velocity: CGVector(dx: -wall.side.sign * 180, dy: 380))
        }
    }

    @objc private func spaceChanged() {
        let old = docks
        refreshDocks()
        guard old != docks else { return }
        rebuildTerrain(windows: appWindows)
        // Dock이 사라졌으면 Dock 위에 있던 펫은 맨 바닥으로, 다시 생겼으면 Dock 뒤에 숨지 않게
        if !isDragging { liftOutOfDock(); beginFall() }
    }

    @objc private func screensChanged() {
        refreshLayout()
        rescanWindows(force: true)
        // 바닥 높이가 바뀌었을 수 있으니 다시 떨어뜨려서 자리 잡기 (Dock 뒤에 숨지 않게 먼저 위로)
        if !isDragging { liftOutOfDock(); beginFall() }
    }

    // MARK: - 마우스

    private func mouseDown(_ event: NSEvent) {
        // NSEvent.mouseLocation: 화면 전체 기준 마우스 좌표 (좌하단 원점)
        let p = NSEvent.mouseLocation
        mouseDownLocation = p
        dragOffset = CGPoint(x: p.x - physics.origin.x, y: p.y - physics.origin.y)
        isDragging = false
        dragTrail = [(CACurrentMediaTime(), p)]
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
        physics.standingOn = nil
        climbingWall = nil
        window?.setFrameOrigin(physics.origin)
        let now = CACurrentMediaTime()
        dragTrail.append((now, p))
        dragTrail.removeAll { now - $0.0 > 0.1 } // 최근 0.1초만
    }

    private func mouseUp(_ event: NSEvent) {
        defer { mouseDownLocation = nil }
        if isDragging {
            isDragging = false
            refreshLayout()
            rescanWindows(force: true)
            beginFall(velocity: Self.throwVelocity(dragTrail))
            return
        }
        if event.clickCount >= 2 {
            openViewer()
        } else {
            handleSingleClick()
        }
        syncModel()
    }

    /// 단일 클릭: 말풍선이 떠 있으면 말풍선 동작(프로젝트로 이동),
    /// 숨겨진 미확인 알림이 있으면 다시 보여주기, 아무것도 없으면 짧은 happy 반응
    private func handleSingleClick() {
        if bubble.isShowing {
            bubble.activateCurrent()
        } else if bubble.hasUnread {
            bubble.show()
        } else {
            brain.handle(.clicked, using: &rng)
            bubble.say(stats.today.speech) // "오늘 12번 끝냈어요!"
        }
    }

    /// 놓는 순간의 마우스 속도 → 던지기 초속 (너무 세지 않게 제한)
    nonisolated static func throwVelocity(_ trail: [(CFTimeInterval, CGPoint)]) -> CGVector {
        guard let first = trail.first, let last = trail.last, last.0 - first.0 > 0.01 else { return .zero }
        let dt = CGFloat(last.0 - first.0)
        var v = CGVector(dx: (last.1.x - first.1.x) / dt, dy: (last.1.y - first.1.y) / dt)
        let speed = hypot(v.dx, v.dy)
        if speed < 150 { return .zero }          // 살살 놓으면 그냥 떨어진다
        let cap: CGFloat = 1800
        if speed > cap { v = CGVector(dx: v.dx * cap / speed, dy: v.dy * cap / speed) }
        return v
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

        if let library {
            let charItem = NSMenuItem(title: "캐릭터", action: nil, keyEquivalent: "")
            let charMenu = NSMenu()
            for entry in library.entries {
                let item = NSMenuItem(title: entry.name, action: #selector(menuSelectCharacter(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry.id
                item.state = entry.id == library.selectedId ? .on : .off
                charMenu.addItem(item)
            }
            charItem.submenu = charMenu
            menu.addItem(charItem)
        }

        let settings = NSMenuItem(title: "설정…", action: nil, keyEquivalent: "")
        settings.isEnabled = false // Phase 3
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "텀펫 종료", action: #selector(menuQuit), keyEquivalent: "")
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
    @objc private func menuSelectCharacter(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        selectCharacter(id: id)
    }
    @objc private func menuQuit(){ NSApplication.shared.terminate(nil) }
}

/// 펫 창 안의 SwiftUI 루트 뷰. Phase 3에서 캐릭터 팩(스프라이트) 렌더러로 교체 가능하게 분리.
struct PetView: View {
    let model: PetViewModel

    var body: some View {
        characterView
        // 머리 위 표시 (overlay ≈ position:absolute 자식)
        .overlay(alignment: .top) {
            PetBadgeView(badge: model.badge, time: model.time)
        }
        // 기분: 신남 ✨ / 시무룩 비구름
        .overlay(alignment: .topTrailing) {
            MoodMarkView(mood: model.mood, time: model.time)
        }
        // 잠잘 때 z z z (그림 팩 캐릭터는 그림에 z가 없으니 여기서 그린다)
        .overlay(alignment: .topTrailing) {
            if model.action == .sleep, case .sprite = model.character {
                SleepZView(time: model.time)
            }
        }
    }

    /// 선택된 캐릭터 종류에 따라 렌더러 선택 (TS의 switch로 컴포넌트 고르기와 같음)
    @ViewBuilder
    private var characterView: some View {
        switch model.character {
        case .builtIn(let style):
            DefaultCharacterView(style: style, action: model.action, facing: model.facing,
                                 time: model.time, actionTime: model.actionTime)
        case .sprite(let sprite):
            SpriteCharacterView(sprite: sprite, action: model.action, variant: model.variant,
                                facing: model.facing, actionTime: model.actionTime)
        }
    }
}

/// 머리 위 작은 표시: "!" 미확인 알림 / "•••" 작업 중 / ✋ 권한 대기 (여러 세션이면 숫자)
struct PetBadgeView: View {
    let badge: PetBadge
    let time: TimeInterval

    var body: some View {
        switch badge {
        case .none:
            EmptyView()
        case .unread:
            Text("!")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color(red: 0.98, green: 0.62, blue: 0.1)))
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                .offset(y: 2 + CGFloat(sin(time * 5)) * 2)
        case .working(let count):
            // 메신저의 "입력 중…" 점 세 개
            HStack(spacing: 2.5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 4, height: 4)
                        .offset(y: -CGFloat(max(0, sin(time * 6 - Double(i) * 0.9))) * 2)
                }
                if count > 1 { countText(count, color: .black.opacity(0.6)) }
            }
            .padding(.horizontal, 6)
            .frame(height: 15)
            .background(Capsule().fill(.white))
            .overlay(Capsule().stroke(Color.black.opacity(0.15), lineWidth: 1))
            .offset(y: 3)
        case .waiting(let count):
            // 권한 대기: 손 흔들기 + 살짝 커졌다 작아짐
            HStack(spacing: 2) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(sin(time * 8) * 15))
                if count > 1 { countText(count, color: .white) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background(Capsule().fill(Color(red: 0.92, green: 0.33, blue: 0.25)))
            .overlay(Capsule().stroke(.white, lineWidth: 1.5))
            .scaleEffect(1 + CGFloat(sin(time * 4)) * 0.06)
            .offset(y: 2)
        }
    }

    private func countText(_ n: Int, color: Color) -> some View {
        Text("\(n)").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(color)
    }
}

/// 세션 추적기를 화면에서 구독할 수 있게 감싼 스토어 (`@Observable` ≈ Zustand)
@Observable
final class SessionStore {
    private(set) var tracker = SessionTracker()

    func apply(_ event: PetEvent) { tracker.apply(event) }

    func state(of event: PetEvent) -> SessionTracker.State? {
        SessionTracker.key(for: event).flatMap { tracker.sessions[$0]?.state }
    }

    /// 바뀐 게 있을 때만 대입 → 패널이 쓸데없이 다시 그려지지 않게
    func prune(now: Date = Date()) {
        var copy = tracker
        if copy.prune(now: now) { tracker = copy }
    }
}

/// 머리 옆 기분 표시
struct MoodMarkView: View {
    let mood: PetMood
    let time: TimeInterval

    var body: some View {
        switch mood {
        case .normal:
            EmptyView()
        case .cheerful:
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.2))
                .shadow(color: .white, radius: 1)
                .opacity(0.6 + 0.4 * abs(sin(time * 2.5)))
                .scaleEffect(0.9 + 0.15 * CGFloat(sin(time * 2.5)))
                .offset(x: -4, y: 6)
        case .gloomy:
            Image(systemName: "cloud.drizzle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.45, green: 0.52, blue: 0.62))
                .shadow(color: .white, radius: 1)
                .offset(x: -6 + CGFloat(sin(time * 0.8)) * 3, y: 4)
        }
    }
}

/// 오늘 기록 스토어 (UserDefaults에 저장, `@Observable` ≈ Zustand)
@Observable
final class StatsStore {
    private(set) var stats: DailyStats
    @ObservationIgnored private let defaults: UserDefaults
    static let key = "dailyStats"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(DailyStats.self, from: $0) }
        stats = saved ?? DailyStats(day: DailyStats.dayKey(Date()))
    }

    /// 날짜가 바뀌었으면 빈 기록
    var today: DailyStats { stats.current() }

    func record(_ event: PetEvent) {
        stats.record(event)
        if let data = try? JSONEncoder().encode(stats) { defaults.set(data, forKey: Self.key) }
    }
}

/// 잠잘 때 머리 위로 떠오르는 z z z
struct SleepZView: View {
    let time: TimeInterval

    var body: some View {
        ZStack {
            ForEach(0..<3) { k in
                let q = (time / 2.4 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                Text("z")
                    .font(.system(size: 9 + 7 * q, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.45, green: 0.55, blue: 0.85))
                    .shadow(color: .white, radius: 1)
                    .opacity(sin(q * .pi))
                    .offset(x: -14 + q * 16, y: 22 - q * 22)
            }
        }
        .frame(width: 30, height: 34)
        .allowsHitTesting(false)
    }
}
