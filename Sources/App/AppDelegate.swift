import AppKit
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    // MARK: - 캐릭터 메뉴 동작

    func selectCharacter(_ id: String) {
        if let problem = petController.selectCharacter(id: id) {
            showAlert("캐릭터를 불러오지 못했어요", problem + "\n기본 캐릭터로 돌아갑니다.")
        }
    }

    /// 폴더 선택 창 → 검증 → 캐릭터 폴더로 복사 → 바로 적용
    func importCharacterPack() {
        NSApp.activate() // 메뉴바 앱은 비활성 상태라 먼저 앞으로 가져와야 창이 보인다
        let panel = NSOpenPanel()
        panel.title = "캐릭터 팩 폴더 선택 (character.json이 들어 있는 폴더)"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            let id = try characters.importPack(from: folder)
            selectCharacter(id)
        } catch {
            showAlert("캐릭터 팩을 가져오지 못했어요", "\(error)\n\n형식은 docs/CHARACTER_PACK.md 를 참고하세요.")
        }
    }

    /// 이미지 선택 → 이름/방향 입력 → 배경 제거 + 움직임 생성 → 바로 적용
    func makeCharacterFromImage() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.title = "캐릭터로 만들 그림 선택"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // 이름 + 바라보는 방향 입력 (NSAlert에 입력 칸을 붙이는 간단한 폼)
        let alert = NSAlert()
        alert.messageText = "이미지로 캐릭터 만들기"
        alert.informativeText = "배경을 자동으로 지우고 상태별 움직임을 입힙니다.\n그림 속 캐릭터가 바라보는 방향을 골라 주세요."
        let nameField = NSTextField(string: url.deletingPathExtension().lastPathComponent)
        nameField.placeholderString = "캐릭터 이름"
        let facingPopup = NSPopUpButton()
        facingPopup.addItems(withTitles: ImageCharacterMaker.Facing.allCases.map(\.title))
        let stack = NSStackView(views: [nameField, facingPopup])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.frame = NSRect(x: 0, y: 0, width: 260, height: 56)
        nameField.frame.size.width = 260
        alert.accessoryView = stack
        alert.addButton(withTitle: "만들기")
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        let facing = ImageCharacterMaker.Facing.allCases[max(0, facingPopup.indexOfSelectedItem)]
        do {
            let result = try ImageCharacterMaker.make(from: url, name: name.isEmpty ? "내 캐릭터" : name,
                                                      facing: facing, into: characters.directory)
            characters.reload()
            selectCharacter(CharacterLibrary.packEntryId(result.packId))
        } catch {
            showAlert("캐릭터를 만들지 못했어요", "\(error)")
        }
    }

    func openCharacterFolder() {
        try? FileManager.default.createDirectory(at: characters.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(characters.directory)
    }

    /// 현재(또는 기본) 도형 캐릭터를 스프라이트 팩으로 내보내 목록에 추가하고 폴더를 연다
    func exportSamplePack() {
        let style: BuiltInStyle
        if case .builtIn(let current) = petController.model.character { style = current } else { style = .mallang }
        do {
            let folder = try CharacterPackExporter.export(style, to: characters.directory)
            characters.reload()
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } catch {
            showAlert("샘플 팩을 만들지 못했어요", "\(error)")
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
