import Foundation

/// 최소한의 HTTP/1.1 요청. Express의 `req`에서 필요한 것만 남긴 버전.
struct HTTPRequest: Equatable {
    var method: String
    var path: String
    /// 헤더 이름은 소문자로 정규화 (HTTP 헤더는 대소문자 무시)
    var headers: [String: String]
    var body: Data

    func header(_ name: String) -> String? { headers[name.lowercased()] }
}

struct HTTPResponse: Equatable {
    var status: Int
    var body: String

    static func text(_ status: Int, _ body: String) -> HTTPResponse { HTTPResponse(status: status, body: body) }

    var reason: String {
        switch status {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        default: return "Error"
        }
    }

    /// 응답 바이트 (항상 Connection: close — 요청 1개 처리 후 연결 종료)
    func serialized() -> Data {
        let bodyData = Data(body.utf8)
        let head = "HTTP/1.1 \(status) \(reason)\r\n"
            + "Content-Type: text/plain; charset=utf-8\r\n"
            + "Content-Length: \(bodyData.count)\r\n"
            + "Connection: close\r\n\r\n"
        return Data(head.utf8) + bodyData
    }
}

/// 받은 바이트를 HTTP 요청으로 해석. TCP는 데이터가 쪼개져 올 수 있어서
/// "아직 덜 옴(incomplete)"을 구분해 계속 받도록 한다. 순수 함수 → 테스트 가능.
enum HTTPRequestParser {
    enum Result: Equatable {
        case incomplete
        case complete(HTTPRequest)
        case invalid
        case tooLarge
    }

    static let maxBodySize = 1_000_000
    static let maxHeaderSize = 16_384

    static func parse(_ data: Data) -> Result {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator) else {
            return data.count > maxHeaderSize ? .tooLarge : .incomplete
        }
        guard let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            return .invalid
        }
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count >= 2 else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0 else { return .invalid }
        guard length <= maxBodySize else { return .tooLarge }

        let bodyStart = headerEnd.upperBound
        guard data.endIndex - bodyStart >= length else { return .incomplete }
        let body = data[bodyStart..<(bodyStart + length)]

        // 쿼리스트링 제거
        let target = String(requestLine[1])
        let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? target

        return .complete(HTTPRequest(method: String(requestLine[0]).uppercased(), path: path,
                                     headers: headers, body: Data(body)))
    }
}
