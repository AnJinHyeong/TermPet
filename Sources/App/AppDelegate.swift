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
    #if DEBUG
    // 개발용: `--pretend-version 0.0.1` 로 옛 버전인 척해서 업데이트 안내를 확인
    let updater = AppUpdater(current: CommandLine.arguments.firstIndex(of: "--pretend-version")
        .flatMap { CommandLine.arguments.dropFirst($0 + 1).first } ?? AppInfo.version)
    #else
    let updater = AppUpdater()
    #endif
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
        // 텀펫은 하나만: 이미 떠 있는 텀펫이 남을 차례면 나는 바로 종료 (업데이트 직후 두 개가 뜨던 문제)
        guard SingleInstance.claim(ready: { [weak self] in self?.startServer() }) else {
            exit(0)
        }
        petController.library = characters
        if let problem = petController.selectCharacter(id: characters.selectedId) {
            NSLog("[TermPet] character load failed: \(problem)")
        }
        petController.start()
        paths.installBundledScripts()
        // startServer() 는 SingleInstance.claim 이 부른다 (다른 텀펫이 포트를 놓은 뒤)
        updater.startPeriodicChecks()
        #if DEBUG
        // 개발용: 메뉴바 패널을 일반 창으로 띄워 스크린샷 확인 (`TermPet --preview-panel`)
        if CommandLine.arguments.contains("--preview-panel") { showPanelPreview() }
        #endif
    }

    #if DEBUG
    private var previewWindow: NSWindow?
    private func showPanelPreview() {
        // 최근 알림 예시
        var old = PetEvent(source: .claude, kind: .ask, message: "권한이 필요해요", cwd: "/tmp/fitin")
        old.receivedAt = Date().addingTimeInterval(-600)
        petController.history.record(old, content: BubbleContent(title: "fitin", body: "권한이 필요해요"))
        petController.history.record(PetEvent(source: .claude, kind: .done, cwd: "/tmp/TermPet"),
                                     content: BubbleContent(title: "TermPet", body: "작업 끝났어요!"))
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
        var size = host.fittingSize
        if size.height < 100 { size = NSSize(width: 312, height: 760) } // LazyVGrid는 fittingSize가 0일 수 있음
        NSLog("[TermPet] preview panel size \(size)")
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
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

    /// 패널의 "친구 추가하기": 파일 선택 창에서 zip(또는 폴더)을 골라 친구 팩을 더한다 → 새 친구 중 첫 친구로 바꾸기
    /// NSOpenPanel ≈ <input type="file"> 를 코드로 띄우는 것
    func importFriends() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.title = "친구 팩 고르기"
        panel.message = "캐릭터 팩이 든 zip 파일(또는 폴더)을 골라 주세요. 지금 친구들은 그대로 두고 더해요"
        panel.prompt = "추가"
        panel.allowedContentTypes = [.zip, .folder]
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let ids = try FriendPackImporter.importPacks(from: url, into: characters.friendsDirectory)
            characters.reload()
            let names = ids.compactMap { id in characters.entries.first { $0.id == CharacterLibrary.friendPrefix + id }?.name }
            if let first = ids.first { selectCharacter(CharacterLibrary.friendPrefix + first) }
            showAlert("친구 \(ids.count)명을 추가했어요", names.joined(separator: ", "))
        } catch {
            showAlert("친구를 추가하지 못했어요", error.localizedDescription)
        }
    }

    /// 패널 친구 타일 우클릭 → 삭제: 확인 후 폴더를 휴지통으로. 지금 친구였으면 첫 친구로 바꾼다.
    func deleteCharacter(_ id: String) {
        guard let entry = characters.entries.first(where: { $0.id == id }) else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "'\(entry.name)'을(를) 지울까요?"
        alert.informativeText = "휴지통으로 옮겨져요. 잘못 지웠다면 Finder 휴지통에서 'Friends' 폴더로 되돌려 놓으면 돼요."
        alert.addButton(withTitle: "지우기")
        alert.addButton(withTitle: "취소")
        alert.buttons[0].hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let wasSelected = characters.selectedId == id
        do {
            try characters.remove(id)
        } catch {
            showAlert("지우지 못했어요", error.localizedDescription)
            return
        }
        if wasSelected { selectCharacter(characters.selectedId) }
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
            } else if kind == .claudeApp && (updating || !wasOn) {
                showAlert("Claude 앱 채팅을 연결했어요",
                          "Claude 앱을 완전히 종료(⌘Q)했다가 다시 켜 주세요.\n\n"
                          + "처음 답변할 때 'termpet_notify' 도구 사용 허락을 물어보면 '항상 허용'을 눌러 주세요. "
                          + "가끔 알림이 빠지면 Claude 설정 → 프로필 → 개인 맞춤 설정에 "
                          + "\"답변을 마칠 때마다 termpet_notify 도구로 한 줄 요약을 보내줘\"를 적어 두면 더 잘 불러요.")
            } else if kind == .claudeApp && wasOn {
                showAlert("Claude 앱 채팅 연결을 해제했어요", "Claude 앱을 다시 켜면 적용돼요.")
            } else if kind == .codex && (updating || !wasOn) {
                showAlert("Codex를 연결했어요",
                          "답이 끝나면 알림이 오고, 질문을 보내면 펫 머리 위에 작업 중(…)이 표시돼요.\n\n"
                          + "작업 중 표시는 Codex 훅이라 한 번 허락이 필요해요: ChatGPT(Codex) 앱 설정 → 훅(Hooks)에서 "
                          + "termpet-hook 을 신뢰(Trust)해 주세요. 터미널 Codex는 처음 실행할 때 물어봐요.")
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
