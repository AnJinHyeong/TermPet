import Foundation

/// 받은 요청 기록 (~/.termpet/events.log). "알림이 안 와요" 디버깅용.
/// 예: 2026-11-09 11:30:02  POST /hook/claude  202  claude/done  TermPet  host=com.todesktop...
struct RequestLog {
    let url: URL
    var maxBytes = 256 * 1024

    static func line(date: Date, method: String, path: String, status: Int, body: String, event: PetEvent?) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var parts = [f.string(from: date), "\(method) \(path)", "\(status)"]
        if let e = event {
            parts.append("\(e.source.rawValue)/\(e.kind.rawValue)")
            parts.append(e.projectName ?? "-")
            if let host = e.hostBundleId ?? e.termProgram { parts.append("host=\(host)") }
            // 어느 대화의 어떤 알림이었는지 (같은 프로젝트에 대화가 여럿일 때·리마인더 구분용)
            if let sid = e.sessionId { parts.append("sid=\(sid.prefix(8))") }
            if let type = e.notificationType { parts.append("type=\(type)") }
        } else if status != 200 || path != "/health" {
            parts.append(body) // 거부/무시 사유
        }
        return parts.joined(separator: "  ")
    }

    func append(_ line: String) {
        let fm = FileManager.default
        // 너무 커지면 새로 시작 (이전 내용은 .1 로 보관)
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxBytes {
            let old = url.appendingPathExtension("1")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
