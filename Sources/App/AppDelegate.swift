import AppKit
import SwiftUI
import Observation

/// 앱 전역 상태 (메뉴바 표시용). `@Observable` ≈ Zustand 스토어.
@Observable
final class AppState {
    var serverState: LocalHTTPServer.State = .stopped

    var serverStatusText: String {
        switch serverState {
        case .stopped: return "알림 서버: 꺼짐"
        case .listening(let port): return "알림 서버: 127.0.0.1:\(port)"
        case .failed(let message): return "알림 서버 오류: \(message)"
        }
    }
}

/// AppKit 생명주기 훅. SwiftUI만으로 어려운 창(NSPanel) 관리를 여기서 한다.
/// React 비유: 최상위 컴포넌트의 마운트/언마운트 effect.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let defaultPort: UInt16 = 47821
    static let portDefaultsKey = "serverPort"

    /// 펫 컨트롤러는 앱 전체에서 하나. 메뉴바 메뉴에서도 이 인스턴스를 쓴다.
    let petController = PetController()
    let appState = AppState()
    let paths = TermPetPaths()
    let characters = CharacterLibrary()
    let integrations = IntegrationManager()
    private var server: LocalHTTPServer?

    var port: UInt16 {
        let stored = UserDefaults.standard.integer(forKey: Self.portDefaultsKey)
        return (1024...65535).contains(stored) ? UInt16(stored) : Self.defaultPort
    }

    /// 단위 테스트가 앱을 호스트로 띄울 때는 펫/서버/파일 설치를 하지 않는다
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningTests else { return }
        if CommandLineTool.run(arguments: CommandLine.arguments, library: characters) { return }
        petController.library = characters
        if let problem = petController.selectCharacter(id: characters.selectedId) {
            NSLog("[TermPet] character load failed: \(problem)")
        }
        petController.start()
        paths.installBundledScripts()
        startServer()
        #if DEBUG
        // 개발용: 메뉴바 패널을 일반 창으로 띄워 스크린샷 확인 (`TermPet --preview-panel`)
        if CommandLine.arguments.contains("--preview-panel") { showPanelPreview() }
        #endif
    }

    #if DEBUG
    private var previewWindow: NSWindow?
    private func showPanelPreview() {
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        let host = NSHostingView(rootView: MenuPanelView(app: self))
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.title = "panel-preview"
        window.contentView = effect
        window.center()
        window.orderFrontRegardless()
        previewWindow = window
    }
    #endif

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    // MARK: - 캐릭터 메뉴 동작

    func selectCharacter(_ id: String) {
        if let problem = petController.selectCharacter(id: id) {
            showAlert("캐릭터를 불러오지 못했어요", problem + "\n기본 캐릭터로 돌아갑니다.")
        }
    }

    /// 이미지 선택 → 배경 제거 + 움직임 생성 → "내 캐릭터"로 교체하고 바로 적용 (캐릭터는 하나만 보관)
    func makeCharacterFromImage() {
        NSApp.activate() // 메뉴바 앱은 비활성 상태라 먼저 앞으로 가져와야 창이 보인다
        let panel = NSOpenPanel()
        panel.title = "캐릭터로 만들 그림 선택"
        panel.message = "배경은 자동으로 지워져요. 지금 있는 내 캐릭터는 새 캐릭터로 바뀌어요."
        panel.prompt = "캐릭터 만들기"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let staging = characters.directory.appendingPathComponent(".staging", isDirectory: true)
        do {
            try? FileManager.default.removeItem(at: staging)
            let result = try ImageCharacterMaker.make(from: url, name: "내 캐릭터", facing: .right, into: staging)
            try characters.installCustom(from: result.folder)
            try? FileManager.default.removeItem(at: staging)
            selectCharacter(CharacterLibrary.customId)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            showAlert("캐릭터를 만들지 못했어요", "\(error)\n\n배경이 단순한 그림(흰 배경, 투명 PNG 등)일수록 잘 돼요.")
        }
    }

    /// 내 캐릭터가 뒤로 걷는 것처럼 보이면 방향 뒤집기
    func flipCustomCharacter() {
        do {
            try characters.flipCustomFacing()
            if characters.selectedId == CharacterLibrary.customId { selectCharacter(CharacterLibrary.customId) }
        } catch {
            showAlert("방향을 바꾸지 못했어요", "\(error)")
        }
    }

    /// 내 캐릭터의 한 동작을 그림 여러 장(프레임)으로 바꾸기
    func pickStateFrames(_ action: PetAction) {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.title = "\(action.title) 그림 선택"
        panel.message = "여러 장을 고르면 파일 이름 순서대로 움직여요 (예: walk1, walk2 …). 한 장이면 그 그림을 살짝 움직여요."
        panel.prompt = "적용"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        do {
            try ImageCharacterMaker.replaceStateFrames(action, in: characters.customFolder, from: panel.urls)
            selectCharacter(CharacterLibrary.customId)
        } catch {
            showAlert("그림을 적용하지 못했어요", "\(error)\n\n배경이 단순한 그림(흰 배경, 투명 PNG 등)일수록 잘 돼요.")
        }
    }

    func resetCustomStates() {
        do {
            try ImageCharacterMaker.resetAllStates(in: characters.customFolder)
            selectCharacter(CharacterLibrary.customId)
        } catch {
            showAlert("되돌리지 못했어요", "\(error)")
        }
    }

    func removeCustomCharacter() {
        do {
            try characters.removeCustom()
            selectCharacter(characters.selectedId)
        } catch {
            showAlert("캐릭터를 지우지 못했어요", "\(error)")
        }
    }

    /// 패널의 AI 연결 버튼: 설정 파일 백업 → 텀펫 항목 추가/삭제
    /// remove: 스위치를 끈 경우 (업데이트가 필요한 상태여도 해제)
    func toggleIntegration(_ kind: IntegrationManager.Kind, remove: Bool = false) {
        let wasOn = integrations.installed[kind] == true
        let updating = integrations.needsUpdate[kind] == true && !remove
        do {
            try integrations.toggle(kind, remove: remove)
            if kind == .zsh && !wasOn {
                showAlert("터미널 명령 알림을 연결했어요", "새로 여는 터미널부터 적용돼요.")
            } else if kind == .claude && (updating || !wasOn) {
                showAlert("Claude Code를 연결했어요", "새로 시작하는 Claude Code 세션부터 펫 머리 위에 작업 중(…)·권한 대기(✋)가 표시돼요.")
            }
        } catch {
            showAlert("\(kind.title) 연결을 바꾸지 못했어요", "\(error)\n\n설정 파일은 바뀌지 않았어요.")
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private func startServer() {
        let token: String
        do {
            token = try paths.loadOrCreateToken()
        } catch {
            appState.serverState = .failed("토큰 생성 실패")
            NSLog("[TermPet] token error: \(error)")
            return
        }
        let port = self.port
        paths.writePort(port)

        let server = LocalHTTPServer(port: port, token: token)
        server.onEvent = { [weak self] event in self?.petController.receive(event) }
        server.onStateChange = { [weak self] state in self?.appState.serverState = state }
        let log = RequestLog(url: paths.eventsLog)
        server.onRequest = { method, path, status, body, event in
            guard path != "/health" else { return } // 상태 확인은 기록 안 함
            log.append(RequestLog.line(date: Date(), method: method, path: path, status: status,
                                       body: body, event: event))
        }
        server.start()
        self.server = server
    }
}
