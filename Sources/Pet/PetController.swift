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
    /// 최근 알림 (메뉴 패널 "최근 알림")
    let history = HistoryStore()
    /// 크기·걷기 속도·말풍선 시간 (메뉴 패널 "설정" 탭). 바꾸면 바로 저장·반영.
    var preferences = PetPreferences.load() {
        didSet {
            guard preferences != oldValue else { return }
            preferences.save()
            applyPreferences()
        }
    }
    /// 지금 캐릭터의 원래 크기 (설정 배율 적용 전)
    private var baseSize = LoadedCharacter.defaultSize
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
    /// 서 있던 창이 마지막으로 움직인 시각 (창을 끄는 중인지 판단)
    private var lastRideAt: CFTimeInterval = -.infinity
    private var isRidingWindow: Bool {
        guard let id = physics.standingOn, !ScreenFloor.isDock(id) else { return false }
        return CACurrentMediaTime() - lastRideAt < 2
    }
    /// 화면 아래 Dock 발판들 (창 위 산책 설정과 무관하게 항상 지형에 포함)
    private var docks: [WindowBox] = []
    private var lastDockCheck: CFTimeInterval = 0
    /// Space 전환·화면 변경 뒤 이 시각에 한 번만 자리 판정 (전환 애니메이션 중엔 창 목록이 들쭉날쭉해서)
    private var settleAt: CFTimeInterval?
    /// Dock 뒤에 가려져서 그 자리에서 Dock 위로 기어오르는 중
    private var risingOutOf: WindowBox?
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

    /// 장난꾸러기 모드: 포인터를 쫓아와 물고 던진다 (메뉴 패널 '장난꾸러기' 칩, 기본 꺼짐)
    static let mischiefKey = "mischief"
    var mischiefEnabled: Bool = UserDefaults.standard.bool(forKey: PetController.mischiefKey) {
        didSet {
            UserDefaults.standard.set(mischiefEnabled, forKey: Self.mischiefKey)
            model.mischief = mischiefEnabled
            if !mischiefEnabled { stopMischief() }
        }
    }
    private var mischief = Mischief()
    /// 포인터 쫓는 중 (걷기 속도 ↑, 벽은 무조건 타고 끝에선 포인터 쪽으로 뛴다)
    private var chasing: Bool { mischiefEnabled && mischief.phase == .chasing }
    /// 쫓는 포인터까지 가로 거리 (멀면 더 빨리 달린다)
    private var chaseDistance: CGFloat = 0
    /// 던져진 포인터가 날아가는 중 (경로, 지난 시간)
    private var flyingPointer: (path: PointerThrow, t: TimeInterval)?

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
        bubble.displayDuration = preferences.bubbleSeconds
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
        model.mischief = mischiefEnabled
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
        // 앱이 켜지거나 꺼지면 Dock 칸 수가 바뀐다 → Dock 폭 캐시 지우기
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(dockMayHaveChanged), name: name, object: nil)
        }

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
        // 약간의 오차 허용 → macOS가 다른 일과 묶어서 깨워 배터리 절약 (애니메이션엔 티 안 남)
        timer.tolerance = 0.1 / timerFPS
        // .common 모드: 메뉴가 열려 있거나 드래그 중에도 루프가 멈추지 않게
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - 외부 API (메뉴바/우클릭 메뉴에서 호출)

    /// 잠든 상태 (들려서 옮겨지는 중에도 true)
    var isSleeping: Bool { brain.isAsleep }

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
            stopMischief() // 물고 있던 포인터는 놓아준다
            bubble.hide() // 미확인 알림은 큐에 남아 있다가 다시 보이면 "!"로 표시
            timer?.invalidate() // 숨긴 동안은 루프를 멈춰 CPU 0
            timer = nil
            timerFPS = 0
        }
    }

    /// 외부 이벤트(Claude 완료, 쉘 명령 실패 등) 수신 → 감정 표현 + 말풍선
    func receive(_ incoming: PetEvent) {
        // Code 탭에서 훅 알림과 겹치는 "Claude 채팅" 알림은 버린다 (두 번 뜨지 않게)
        if sessions.tracker.isDuplicateChatSignal(incoming) { return }
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
        let content = bubble.enqueue(event)
        history.record(event, content: content)
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
        bubble.messages = character.messages
        baseSize = character.size
        applyPreferences()
    }

    /// 설정(크기·속도·말풍선 시간)을 지금 캐릭터에 반영
    private func applyPreferences() {
        let base: CGFloat = model.character.walkSpeed ?? config.walkSpeed
        walkSpeed = base * CGFloat(preferences.speedScale)
        bubble.displayDuration = preferences.bubbleSeconds
        resize(to: preferences.scaled(baseSize))
    }

    private func resize(to newSize: CGSize) {
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
                if chaseClimbs(wall) {
                    brain.handle(.climbNow, using: &rng)
                } else {
                    brain.handle(wall.leadsToScreen ? .hitStep : .hitWall(window: wall.windowID != nil), using: &rng)
                }
                if brain.action == .climb { startClimbing(wall) } else { giveUpChase() }
            case .reachedScreenEdge:
                if chaseJumpsOff(toward: brain.direction) {
                    beginFall(velocity: physics.screenHop(brain.direction)) // 포인터가 옆 모니터에 → 무조건 건너간다
                } else {
                    brain.handle(.reachedScreenEdge, using: &rng)
                    if brain.action == .fall {
                        // 옆 모니터로 폴짝 (두 모니터에 걸쳐 반쯤 잘려 보이는 시간을 줄인다)
                        physics.prepareFall(terrain: terrain, velocity: physics.screenHop(brain.direction))
                    } else { giveUpChase() }
                }
            case .reachedEdge:
                if chaseJumpsOff(toward: brain.direction) {
                    beginFall(velocity: CGVector(dx: brain.direction.sign * 140, dy: 400)) // 포인터 쪽으로 뛰어내린다
                } else {
                    brain.handle(.reachedEdge, using: &rng)
                    if brain.action == .fall {
                        // 선반 끝에서 폴짝 뛰어내리기
                        physics.prepareFall(terrain: terrain, velocity: CGVector(dx: brain.direction.sign * 110, dy: 420))
                    } else { giveUpChase() }
                }
            case .startFalling: beginFall()
            }
        case .climb:
            if risingOutOf != nil { stepRise(dt) } else { stepClimb(dt) }
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

        stepMischief(dt)
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
        clock += dt
        syncModel()

        var wanted = Self.loopFPS(for: brain.action, maxFPS: config.fps)
        // 서 있는 창이 방금 움직였으면(창을 끄는 중) 매끄럽게 따라가도록 조금 더 자주
        if isRidingWindow { wanted = max(wanted, min(config.fps, 20)) }
        // 포인터를 물고 흔들거나 던지는 중엔 포인터가 매끄럽게 움직이도록 최대로
        if mischief.phase == .biting || mischief.phase == .throwing { wanted = config.fps }
        if wanted != timerFPS { startTimer(fps: wanted) }
    }

    /// 두뇌 상태 → 뷰 모델 복사 (SwiftUI 재렌더 트리거)
    private func syncModel() {
        var changed = false
        // 잠든 채 들려 있거나 떨어지는 중에도 자는 모습 그대로 (물리는 brain.action으로 따로 돈다)
        let shown: PetAction = brain.isAsleep ? .sleep : brain.action
        if model.action != shown { model.action = shown; changed = true }
        if model.facing != brain.direction { model.facing = brain.direction }
        if model.variant != brain.variant { model.variant = brain.variant; changed = true }
        publishClock(force: changed)
    }

    /// 앱 시작 후 흐른 시간. 뷰에는 필요할 때만 넘긴다 (publishClock)
    private var clock: TimeInterval = 0
    private var lastSpriteFrame: Int?

    /// 애니메이션 시계를 뷰 모델에 넘기기.
    /// 시계 값을 바꾸면 SwiftUI가 펫 화면을 다시 그리는데, 그림 팩 캐릭터는 그림이 초당 6~12장만 바뀐다.
    /// → 보여 줄 프레임 번호가 바뀔 때만 넘겨서 루프(최대 30fps)마다 다시 그리지 않게 한다 (CPU 절약).
    /// 기본 도형 캐릭터·머리 위 표시(배지·기분·zzz)는 시계로 계속 움직이므로 그때는 매번 넘긴다.
    /// React 비유: 매 프레임 setState 하지 않고, 화면에 보이는 값이 바뀔 때만 setState.
    private func publishClock(force: Bool = false) {
        if !force, !model.biting, case .sprite(let sprite) = model.character,
           model.badge == .none, model.mood == .normal, model.action != .sleep {
            let frame = sprite.animation(for: model.action, variant: model.variant)?.timing.frameIndex(at: brain.elapsed)
            guard frame != lastSpriteFrame else { return }
            lastSpriteFrame = frame
        } else {
            lastSpriteFrame = nil
        }
        model.time = clock
        model.actionTime = brain.elapsed
    }

    private func beginFall(velocity: CGVector = .zero) {
        climbingWall = nil
        risingOutOf = nil
        physics.prepareFall(terrain: terrain, velocity: velocity)
        brain.handle(.startFall, using: &rng)
    }

    /// 걷기 속도: 기분 반영 + 달리기 포즈(walk.2)가 뽑히면 빠르게
    private var currentWalkSpeed: CGFloat {
        // 포인터 쫓을 땐 달린다 (멀리 있으면 전력 질주)
        if chasing { return max(walkSpeed * 2.4, 90) * (chaseDistance > 500 ? 1.7 : 1) }
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
        let width = currentDockWidth()
        let windows = scanWindows()
        // Dock은 한 화면에만 있다. 그 화면을 전체 화면 앱이 덮고 있으면 Dock은 숨어 있으니 발판도 없다
        // (전체 화면 판정이 한순간 풀려도 Dock이 깜빡 생기지 않게 dockGate로 거른다)
        let found = NSScreen.screens.lazy.compactMap { s -> (CGRect, WindowBox)? in
            ScreenFloor.dockBox(frame: s.frame, visible: s.visibleFrame, dockWidth: width).map { (s.frame, $0) }
        }.first
        let fullscreen = found.map { ScreenFloor.hasFullscreenWindow(windows, screen: $0.0) } ?? false
        let hidden = dockGate.update(fullscreen: fullscreen, spaceChanged: spaceChangedSinceDockCheck)
        spaceChangedSinceDockCheck = false
        docks = (found.map { [$0.1] } ?? []).filter { _ in !hidden }
        if docks != lastLoggedDocks {
            lastLoggedDocks = docks
            let line = "[TermPet] dock \(docks.first.map { "\($0.frame)" } ?? "none") exact=\(WindowScanner.canReadDockExactly)"
            NSLog(line)
            #if DEBUG
            // 개발용: ~/Library/Logs/TermPet-debug.log 에도 남긴다 (open으로 띄우면 NSLog가 안 보여서)
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/TermPet-debug.log")
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(Data((Date().description + " " + line + "\n").utf8)); try? h.close()
            }
            #endif
        }
    }
    private var lastLoggedDocks: [WindowBox]?

    /// Dock 폭 캐시. Dock 설정(다른 앱의 설정 파일)·접근성 트리를 읽는 건 비싸서 매초 하지 않는다.
    /// 앱 실행·종료(Dock 칸 수가 바뀜)·화면 변경 알림이 오면 바로 지우고, 그 밖엔 10초마다 다시 읽는다.
    private var dockWidthCache: (value: CGFloat?, at: CFTimeInterval)?
    private func currentDockWidth() -> CGFloat? {
        let now = CACurrentMediaTime()
        if let cache = dockWidthCache, now - cache.at < 10 { return cache.value }
        let width = WindowScanner.dockWidth()
        dockWidthCache = (width, now)
        return width
    }
    @objc private func dockMayHaveChanged() { dockWidthCache = nil }

    /// 창 목록 읽기. Dock 검사와 지형 갱신이 같은 순간에 두 번 읽지 않게 같은 틱 안에서만(0.03초) 재사용한다
    /// (창 위에 서 있으면 창을 끌 때 따라가도록 0.05초마다 새로 읽어야 해서 길게 잡지 않는다)
    private var lastScan: (windows: [WindowBox], at: CFTimeInterval)?
    private func scanWindows() -> [WindowBox] {
        let now = CACurrentMediaTime()
        if let scan = lastScan, now - scan.at < 0.03 { return scan.windows }
        let windows = WindowScanner.scan()
        lastScan = (windows, now)
        return windows
    }
    private var dockGate = DockFullscreenGate()
    /// Space 전환 뒤 첫 Dock 검사인지 (그땐 전체 화면 해제를 바로 믿는다)
    private var spaceChangedSinceDockCheck = false

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
        if let at = settleAt {
            if now >= at { settleAt = nil; settle() }
        } else if now - lastDockCheck > 1 { // Dock 크기 변화(앱 실행·종료)를 빨리 반영
            let old = docks
            refreshDocks()
            if old != docks {
                rebuildTerrain(windows: appWindows)
                if ScreenFloor.isDock(climbingWall?.windowID) || ScreenFloor.isDock(physics.standingOn) {
                    // Dock 크기가 바뀌었다: 매달려 있거나 서 있던 자리가 달라졌으니 다시 자리 잡기
                    if !isDragging { beginFall() }
                } else if !isDragging, !brain.action.isPhysicsControlled {
                    startRisingOutOfDock()
                }
            }
        }
        guard usesWindows else {
            if !appWindows.isEmpty || force { rebuildTerrain(windows: []) }
            return
        }
        let onWindow = (physics.standingOn.map { !ScreenFloor.isDock($0) } ?? false)
            || (climbingWall?.windowID.map { !ScreenFloor.isDock($0) } ?? false)
        // 창 위에 가만히 있을 땐 0.25초마다, 그 창이 움직이기 시작하면 2초 동안 0.05초마다 (창 끌기 따라가기).
        // 예전엔 창 위에 서 있기만 해도 계속 초당 20번 창 목록을 읽었다 (가만히 있어도 CPU 사용).
        let interval = onWindow ? (isRidingWindow || brain.action == .climb ? 1.0 / 20 : 0.25)
            : (brain.action == .walk || brain.action == .fall ? 0.25 : 0.6)
        guard force || now - lastWindowScan >= interval else { return }
        lastWindowScan = now
        let old = terrain
        rebuildTerrain(windows: scanWindows())

        // 서 있던 창이 움직였으면 같이 이동 (창을 끌면 펫도 실려 간다)
        if let id = physics.standingOn {
            if let before = old.window(id: id)?.frame, let after = terrain.window(id: id)?.frame, before != after {
                lastRideAt = now
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

    // MARK: - 장난꾸러기 (포인터 쫓기·물기·던지기)

    private func stepMischief(_ dt: TimeInterval) {
        // 던진 포인터 날리기
        if let flying = flyingPointer {
            let t = flying.t + dt
            PointerControl.move(to: flying.path.position(at: t))
            if flying.path.isFinished(at: t) {
                flyingPointer = nil
                PointerControl.finish()
                mischief.finishThrow()
            } else {
                flyingPointer = (flying.path, t)
            }
            return
        }
        guard mischiefEnabled || mischief.phase != .ready else { return }
        let input = Mischief.Input(
            petFrame: CGRect(origin: physics.origin, size: physics.size),
            cursor: NSEvent.mouseLocation,
            facing: brain.direction,
            canPlay: mischiefEnabled && model.isVisible && !isDragging && !bubble.isShowing
                && !brain.isAsleep && brain.action != .dragged && risingOutOf == nil,
            mouseDown: NSEvent.pressedMouseButtons != 0,
            grounded: !brain.action.isPhysicsControlled,
            climbingSide: brain.action == .climb && risingOutOf == nil ? climbingWall?.side : nil,
            wallDirection: physics.standingOn == nil && !brain.action.isPhysicsControlled
                ? terrain.nearestWallDirection(originX: physics.origin.x, feetY: physics.origin.y,
                                               targetX: NSEvent.mouseLocation.x) : nil,
            headroom: (terrain.ceiling(atX: physics.centerX) ?? .infinity) - physics.origin.y - physics.size.height)
        chaseDistance = abs(input.cursor.x - input.petFrame.midX)
        switch mischief.tick(dt, input) {
        case .none:
            break
        case .chase(let dir):
            brain.handle(.chase(dir), using: &rng)
        case .jump(let v):
            // 포인터 쪽으로 몸을 날린다 (바닥에서 점프 / 벽을 차고)
            beginFall(velocity: v)
            if abs(v.dx) > 20 { brain.handle(.face(v.dx > 0 ? .right : .left), using: &rng) }
        case .stopChase:
            break
        case .startBite:
            model.biting = true
            model.biteStart = clock
            brain.handle(.react(.angry, duration: mischief.config.biteDuration + 0.4), using: &rng)
            syncModel()
        case .holdPointer(let p):
            PointerControl.move(to: p)
        case .throwPointer:
            model.biting = false
            let start = NSEvent.mouseLocation
            flyingPointer = (PointerThrow.toss(from: start, facing: brain.direction,
                                               screens: NSScreen.screens.map(\.frame), using: &rng), 0)
            brain.handle(.react(.happy, duration: 1.2), using: &rng) // 뿌듯
            syncModel()
        case .release:
            model.biting = false
            PointerControl.finish()
        }
    }

    /// 쫓다가 벽·끝에 막혀 돌아섰으면 포기 (안 그러면 벽 앞에서 좌우로 떨게 된다)
    private func giveUpChase() {
        guard chasing else { return }
        mischief.giveUp()
    }

    /// 쫓는 중 벽에 막힘: 창·옆 모니터 턱이거나 포인터가 머리 위면 확률 없이 바로 타고 오른다
    private func chaseClimbs(_ wall: Terrain.Wall) -> Bool {
        guard chasing else { return false }
        return wall.windowID != nil || wall.leadsToScreen
            || NSEvent.mouseLocation.y > physics.origin.y + physics.size.height
    }

    /// 쫓는 중 끝(창 끝·모니터 경계)에 닿음: 포인터가 그쪽이거나 아래면 바로 뛰어내린다
    private func chaseJumpsOff(toward dir: Direction) -> Bool {
        guard chasing else { return false }
        let p = NSEvent.mouseLocation
        return (p.x - physics.centerX) * dir.sign > 0 || p.y < physics.origin.y
    }

    private func stopMischief() {
        if model.biting || flyingPointer != nil { PointerControl.finish() }
        model.biting = false
        flyingPointer = nil
        mischief.reset()
    }

    // MARK: - 벽 오르기

    private func startClimbing(_ wall: Terrain.Wall) {
        climbingWall = wall
        physics.standingOn = nil
        if wall.leadsToScreen || (wall.windowID != nil && terrain.ledgeAfterClimbing(wall) != nil) {
            climbLimitY = .infinity            // 창 꼭대기(또는 옆 모니터 턱)까지 올라가서 올라선다
        } else {
            // 올라설 곳이 없는 벽(화면 끝, 가려진 창 꼭대기): 적당히 오르다 뛰어내린다
            let top = min(wall.top, terrain.ceiling(atX: physics.centerX) ?? wall.top) - physics.size.height
            let room = max(0, top - physics.origin.y)
            climbLimitY = physics.origin.y + room * CGFloat.random(in: 0.25...0.7, using: &rng)
            // 포인터를 쫓는 중이면 포인터 높이까지 (stepClimb이 매 프레임 포인터를 따라 고친다)
            if chasing { climbLimitY = chaseClimbLimit(wall) }
        }
        if chasing { mischief.didStartClimbing() }
    }

    /// 쫓는 중 벽을 오를 높이(발): 몸 가운데가 포인터 높이에 오도록, 화면 천장 아래까지만
    private func chaseClimbLimit(_ wall: Terrain.Wall) -> CGFloat {
        let top = min(wall.top, terrain.ceiling(atX: physics.centerX) ?? wall.top) - physics.size.height
        return min(top, NSEvent.mouseLocation.y - physics.size.height * 0.5)
    }

    private func stepClimb(_ dt: TimeInterval) {
        guard let wall = climbingWall else { beginFall(); return }
        // 가끔 힘이 빠져서 미끄러진다 (평균 50초에 한 번)
        if Double.random(in: 0..<1, using: &rng) < dt / 50 {
            brain.handle(.letGo, using: &rng)
            beginFall(velocity: CGVector(dx: -wall.side.sign * 60, dy: 0))
            return
        }
        // 쫓는 중 올라설 곳 없는 벽: 오르는 높이를 지금 포인터 높이에 맞춘다 (포인터가 내려가면 바로 몸을 날린다)
        if chasing, climbLimitY.isFinite { climbLimitY = chaseClimbLimit(wall) }
        // 위쪽을 앞 창이 막고 있으면 그 아래까지만 (가려진 벽을 계속 타지 않게)
        let limit = min(climbLimitY, terrain.climbCeiling(for: wall, feetY: physics.origin.y) ?? .infinity)
        switch physics.climb(wall, speed: max(walkSpeed * 1.3, 50) * (chasing ? 2 : 1), dt: dt, terrain: terrain, limitY: limit) {
        case .climbing:
            break
        case .reachedTop:
            climbingWall = nil
            brain.handle(.climbedUp, using: &rng)
        case .letGo:
            brain.handle(.letGo, using: &rng)
            let frame = CGRect(origin: physics.origin, size: physics.size)
            let headroom = (terrain.ceiling(atX: physics.centerX) ?? .infinity) - frame.maxY
            if chasing, let v = Mischief.leapVelocity(petFrame: frame, cursor: NSEvent.mouseLocation, headroom: headroom)
                ?? Mischief.wallLeap(petFrame: frame, cursor: NSEvent.mouseLocation, headroom: headroom),
               v.dx * wall.side.sign <= 0 {
                beginFall(velocity: v) // 포인터 쪽으로 몸을 날린다
            } else {
                // 벽을 차고 반대쪽으로 폴짝
                beginFall(velocity: CGVector(dx: -wall.side.sign * 180, dy: 380))
            }
        case .overStep:
            // 옆 모니터 턱 꼭대기 → 그쪽으로 폴짝 넘어가서 착지 (방향은 걷던 쪽 그대로)
            climbingWall = nil
            beginFall(velocity: physics.screenHop(wall.side))
        }
    }

    /// Space 전환(전체 화면 앱 ↔ 바탕화면): 전환 애니메이션이 끝난 뒤 한 번만 자리 판정
    @objc private func spaceChanged() {
        spaceChangedSinceDockCheck = true
        lastScan = nil
        settleAt = CACurrentMediaTime() + 0.7
    }

    @objc private func screensChanged() {
        dockWidthCache = nil
        lastScan = nil
        settleAt = CACurrentMediaTime() + 0.7
    }

    /// 화면이 바뀐 뒤 자리 잡기 — 순간이동 없이:
    /// - 바닥에 있던 펫은 그대로 바닥에 (Dock이 생겼다고 위로 올리지 않는다)
    /// - Dock 뒤에 가려졌으면 그 자리에서 Dock 위로 기어 올라온다
    /// - 서 있던 Dock·창이 사라졌을 때만 떨어진다
    private func settle() {
        refreshLayout()
        rescanWindows(force: true)
        guard !isDragging else { return }
        if risingOutOf != nil, docks.first != risingOutOf { risingOutOf = nil; beginFall(); return }
        guard !brain.action.isPhysicsControlled else { return } // 떨어지는 중·벽 타는 중이면 그대로
        if let id = physics.standingOn {
            if terrain.ledge(atX: physics.centerX, y: physics.origin.y, windowID: id) == nil { beginFall() }
            return
        }
        let floor = layout.landingFloor(centerX: physics.centerX, fromY: physics.origin.y) ?? physics.origin.y
        if physics.origin.y > floor + 0.5 { beginFall(); return }
        startRisingOutOfDock()
    }

    /// 바닥에서 몸이 Dock 뒤에 들어가 있으면: 가운데가 Dock 안이면 그 자리에서 기어 오르고,
    /// 살짝 걸친 정도면 옆으로 비켜선다.
    private func startRisingOutOfDock() {
        guard physics.standingOn == nil, risingOutOf == nil, let dock = docks.first,
              let fix = ScreenFloor.resolveDockOverlap(origin: physics.origin, size: physics.size, dock: dock.frame) else { return }
        if fix.onDock {
            risingOutOf = dock
            brain.handle(.climbOutOfDock, using: &rng)
            if brain.action != .climb { risingOutOf = nil }
        } else {
            physics.origin = fix.origin
            window?.setFrameOrigin(physics.origin)
        }
    }

    /// Dock 뒤에서 위로 기어오르기 (벽 타기와 같은 속도)
    private func stepRise(_ dt: TimeInterval) {
        guard let dock = risingOutOf, docks.first == dock else {
            risingOutOf = nil
            beginFall()
            return
        }
        physics.origin.y += max(walkSpeed * 1.3, 50) * CGFloat(dt)
        if physics.origin.y >= dock.frame.maxY {
            physics.origin.y = dock.frame.maxY
            physics.standingOn = dock.id
            risingOutOf = nil
            brain.handle(.climbedUp, using: &rng)
        }
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
        risingOutOf = nil
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
        } else if !brain.isAsleep { // 자는 중엔 클릭해도 안 깨고 말도 안 한다
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

        let sleep = NSMenuItem(title: isSleeping ? "깨우기" : "재우기",
                               action: #selector(menuToggleSleep), keyEquivalent: "")
        sleep.target = self
        menu.addItem(sleep)

        let hide = NSMenuItem(title: "숨기기 (메뉴바에서 다시 보이기)", action: #selector(menuHide), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)

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

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "텀펫 종료", action: #selector(menuQuit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func menuToggleSleep() { toggleSleep() }
    @objc private func menuHide() { setVisible(false) }
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
        // 장난꾸러기: 포인터를 물고 개처럼 고개를 휙휙 (발 기준으로 흔들기)
        .rotationEffect(.degrees(model.biting ? sin(model.time * 38) * 9 : 0), anchor: .bottom)
        .overlay(alignment: model.facing == .right ? .topLeading : .topTrailing) {
            if model.biting { BiteMarkView(elapsed: model.time - model.biteStart) }
        }
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

    /// 물고 있을 땐 공중에서도 물기 그림 (팩에 없으면 화난 얼굴)
    private var shownAction: PetAction { model.biting ? .bite : model.action }

    /// 선택된 캐릭터 종류에 따라 렌더러 선택 (TS의 switch로 컴포넌트 고르기와 같음)
    @ViewBuilder
    private var characterView: some View {
        switch model.character {
        case .builtIn(let style):
            DefaultCharacterView(style: style, action: shownAction, facing: model.facing,
                                 time: model.time, actionTime: model.actionTime)
        case .sprite(let sprite):
            SpriteCharacterView(sprite: sprite, action: shownAction, variant: model.variant,
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

/// 최근 알림 스토어 (앱을 끄면 비워짐, `@Observable` ≈ Zustand)
@Observable
final class HistoryStore {
    private(set) var history = NotificationHistory()
    var entries: [NotificationHistory.Entry] { history.entries }
    func record(_ event: PetEvent, content: BubbleContent) { history.record(event, content: content) }
    func clear() { history.removeAll() }
}

/// 포인터를 물었을 때: 처음엔 "앙!", 흔드는 동안 "으르릉"
struct BiteMarkView: View {
    let elapsed: TimeInterval

    var body: some View {
        Text(elapsed < 0.35 ? "앙!" : "으르릉")
            .font(.system(size: elapsed < 0.35 ? 13 : 9.5, weight: .black, design: .rounded))
            .foregroundStyle(Color(red: 0.85, green: 0.25, blue: 0.25))
            .shadow(color: .white, radius: 1.5)
            .offset(x: elapsed < 0.35 ? 0 : sin(elapsed * 30) * 1.5)
            .padding(2)
            .allowsHitTesting(false)
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
