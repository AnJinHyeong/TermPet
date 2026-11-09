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
        petController.start()
        paths.installBundledScripts()
        startServer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
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
        server.start()
        self.server = server
    }
}
