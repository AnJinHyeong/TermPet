import XCTest
@testable import TermPet

final class HTTPRequestParserTests: XCTestCase {
    private func raw(_ s: String) -> Data { Data(s.utf8) }

    func testParsesCompleteRequest() {
        let body = #"{"a":1}"#
        let data = raw("POST /event?x=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nX-TermPet-Token: abc\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)")
        guard case .complete(let req) = HTTPRequestParser.parse(data) else { return XCTFail() }
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.path, "/event")
        XCTAssertEqual(req.header("X-TERMPET-TOKEN"), "abc")
        XCTAssertEqual(String(data: req.body, encoding: .utf8), body)
    }

    func testIncompleteHeadersAndBody() {
        XCTAssertEqual(HTTPRequestParser.parse(raw("POST /event HTTP/1.1\r\nContent-Le")), .incomplete)
        XCTAssertEqual(HTTPRequestParser.parse(raw("POST /event HTTP/1.1\r\nContent-Length: 10\r\n\r\n12345")), .incomplete)
    }

    func testGetWithoutBody() {
        guard case .complete(let req) = HTTPRequestParser.parse(raw("GET /health HTTP/1.1\r\n\r\n")) else { return XCTFail() }
        XCTAssertEqual(req.path, "/health")
        XCTAssertTrue(req.body.isEmpty)
    }

    func testRejectsGarbageAndHugeBodies() {
        XCTAssertEqual(HTTPRequestParser.parse(raw("NONSENSE\r\n\r\n")), .invalid)
        XCTAssertEqual(HTTPRequestParser.parse(raw("POST / HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n")), .tooLarge)
        XCTAssertEqual(HTTPRequestParser.parse(raw("POST / HTTP/1.1\r\nContent-Length: -5\r\n\r\n")), .invalid)
    }

    func testUTF8Body() {
        let body = #"{"message":"끝났어!"}"#
        let data = raw("POST /event HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)")
        guard case .complete(let req) = HTTPRequestParser.parse(data) else { return XCTFail() }
        XCTAssertEqual(String(data: req.body, encoding: .utf8), body)
    }
}

final class EventRouterTests: XCTestCase {
    private let router = EventRouter(token: "secret")

    private func request(_ method: String, _ path: String, headers: [String: String] = [:], body: String = "") -> HTTPRequest {
        HTTPRequest(method: method, path: path,
                    headers: Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) }),
                    body: Data(body.utf8))
    }

    func testHealthNeedsNoToken() {
        XCTAssertEqual(router.route(request("GET", "/health")).response.status, 200)
    }

    func testUnknownPathAndMethod() {
        XCTAssertEqual(router.route(request("GET", "/nope")).response.status, 404)
        XCTAssertEqual(router.route(request("GET", "/event")).response.status, 405)
    }

    func testRejectsMissingOrWrongToken() {
        let body = #"{"source":"shell","kind":"done"}"#
        XCTAssertEqual(router.route(request("POST", "/event", body: body)).response.status, 401)
        XCTAssertEqual(router.route(request("POST", "/event", headers: ["X-TermPet-Token": "nope"], body: body)).response.status, 401)
    }

    func testRejectsBrowserOrigin() {
        let out = router.route(request("POST", "/event",
                                       headers: ["X-TermPet-Token": "secret", "Origin": "https://evil.example"],
                                       body: #"{"source":"shell","kind":"done"}"#))
        XCTAssertEqual(out.response.status, 403)
        XCTAssertNil(out.event)
    }

    func testAcceptsStandardEvent() {
        let out = router.route(request("POST", "/event", headers: ["X-TermPet-Token": "secret"],
                                       body: #"{"source":"shell","kind":"error","cwd":"/a/fitin"}"#))
        XCTAssertEqual(out.response.status, 202)
        XCTAssertEqual(out.event?.kind, .error)
        XCTAssertEqual(out.event?.projectName, "fitin")
    }

    func testClaudeHookWithHostHeaders() {
        let out = router.route(request("POST", "/hook/claude",
                                       headers: ["X-TermPet-Token": "secret",
                                                 "X-TermPet-Host-Bundle": "com.todesktop.230313mzl4w4u92",
                                                 "X-TermPet-Term-Program": "vscode"],
                                       body: #"{"hook_event_name":"Stop","cwd":"/x/proj","session_id":"s1"}"#))
        XCTAssertEqual(out.response.status, 202)
        XCTAssertEqual(out.event?.hostBundleId, "com.todesktop.230313mzl4w4u92")
        XCTAssertEqual(out.event?.termProgram, "vscode")
    }

    func testEmptyHostHeadersBecomeNil() {
        let out = router.route(request("POST", "/hook/claude",
                                       headers: ["X-TermPet-Token": "secret", "X-TermPet-Host-Bundle": ""],
                                       body: #"{"hook_event_name":"Stop"}"#))
        XCTAssertNil(out.event?.hostBundleId)
    }

    func testIgnoredEventIs200WithoutEvent() {
        let out = router.route(request("POST", "/hook/claude", headers: ["X-TermPet-Token": "secret"],
                                       body: #"{"hook_event_name":"Notification","notification_type":"auth_success"}"#))
        XCTAssertEqual(out.response.status, 200)
        XCTAssertNil(out.event)
    }

    func testBadJSONIs400() {
        let out = router.route(request("POST", "/event", headers: ["X-TermPet-Token": "secret"], body: "{nope"))
        XCTAssertEqual(out.response.status, 400)
    }

    func testResponseSerialization() {
        let text = String(data: HTTPResponse.text(202, "accepted").serialized(), encoding: .utf8)!
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 202 Accepted\r\n"))
        XCTAssertTrue(text.contains("Content-Length: 8\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\naccepted"))
    }
}

final class TermPetPathsTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("termpet-test-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    func testCreatesTokenWithPrivatePermissionsAndReusesIt() throws {
        let paths = TermPetPaths(root: dir)
        let token = try paths.loadOrCreateToken()
        XCTAssertEqual(token.count, 64)
        let attrs = try FileManager.default.attributesOfItem(atPath: paths.tokenFile.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(try paths.loadOrCreateToken(), token)
    }
}
