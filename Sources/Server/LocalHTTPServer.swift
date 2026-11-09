import Foundation
import Network

/// 127.0.0.1 전용 초소형 HTTP 서버 (Network.framework의 `NWListener`).
/// Node 비유: `http.createServer(handler).listen(47821, '127.0.0.1')`.
/// 요청 1개 받고 응답 후 연결을 닫는 단순 구조 (훅은 한 번 쏘고 끝이라 충분).
final class LocalHTTPServer {
    enum State: Equatable {
        case stopped
        case listening(UInt16)
        case failed(String)
    }

    private let port: UInt16
    private let router: EventRouter
    private let queue = DispatchQueue(label: "termpet.http")
    private var listener: NWListener?

    /// 이벤트 수신 콜백 (메인 스레드에서 호출됨)
    var onEvent: ((PetEvent) -> Void)?
    var onStateChange: ((State) -> Void)?

    init(port: UInt16, token: String) {
        self.port = port
        self.router = EventRouter(token: token)
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            // 루프백 주소에만 바인딩 → 같은 네트워크의 다른 기기에서 접근 불가
            params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback),
                                                    port: NWEndpoint.Port(rawValue: port)!)
            let listener = try NWListener(using: params)
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                let mapped: State?
                switch state {
                case .ready: mapped = .listening(self.port)
                case .failed(let e): mapped = .failed("\(e)")
                case .cancelled: mapped = .stopped
                default: mapped = nil
                }
                if let mapped {
                    DispatchQueue.main.async { self.onStateChange?(mapped) }
                }
            }
            listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            onStateChange?(.failed("\(error)"))
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - 연결 처리

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        // 느린/악의적 클라이언트가 연결을 붙잡고 있지 않도록 5초 후 강제 종료
        queue.asyncAfter(deadline: .now() + 5) { connection.cancel() }
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            switch HTTPRequestParser.parse(buffer) {
            case .incomplete:
                if isComplete || error != nil {
                    self.respond(.text(400, "incomplete request"), on: connection)
                } else {
                    self.receive(on: connection, buffer: buffer)
                }
            case .invalid:
                self.respond(.text(400, "bad request"), on: connection)
            case .tooLarge:
                self.respond(.text(413, "too large"), on: connection)
            case .complete(let request):
                let outcome = self.router.route(request)
                if let event = outcome.event {
                    DispatchQueue.main.async { self.onEvent?(event) }
                }
                self.respond(outcome.response, on: connection)
            }
        }
    }

    private func respond(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized(), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
