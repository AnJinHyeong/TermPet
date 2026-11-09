import Foundation
import Security

/// `~/.termpet/` 아래 파일 경로와 초기화(토큰 생성, 스크립트 설치).
///   ~/.termpet/token                     인증 토큰 (권한 600)
///   ~/.termpet/port                      현재 서버 포트 (훅 스크립트가 읽음)
///   ~/.termpet/bin/termpet-hook          훅 스크립트
///   ~/.termpet/zsh-integration.zsh       zsh 연동 스니펫
struct TermPetPaths {
    let root: URL

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".termpet")) {
        self.root = root
    }

    var tokenFile: URL { root.appendingPathComponent("token") }
    var portFile: URL { root.appendingPathComponent("port") }
    var binDir: URL { root.appendingPathComponent("bin") }
    var hookScript: URL { binDir.appendingPathComponent("termpet-hook") }
    var zshIntegration: URL { root.appendingPathComponent("zsh-integration.zsh") }

    /// 토큰을 읽고, 없으면 새로 만든다. 디렉터리 700 / 파일 600 권한.
    func loadOrCreateToken() throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])

        if let existing = try? String(contentsOf: tokenFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), existing.count >= 32 {
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenFile.path)
            return existing
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CocoaError(.fileWriteUnknown)
        }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        // 파일을 600으로 먼저 만든 뒤 내용 기록 (잠깐이라도 남이 읽을 수 있는 틈 없게)
        fm.createFile(atPath: tokenFile.path, contents: nil, attributes: [.posixPermissions: 0o600])
        try Data(token.utf8).write(to: tokenFile)
        return token
    }

    func writePort(_ port: UInt16) {
        try? Data("\(port)\n".utf8).write(to: portFile)
    }

    /// 앱 번들에 포함된 스크립트를 ~/.termpet/에 설치(항상 최신본으로 덮어씀).
    /// 이 파일들은 TermPet 소유 파일이라 덮어써도 된다 (사용자 설정 파일과 다름).
    func installBundledScripts(from bundle: Bundle = .main) {
        let fm = FileManager.default
        try? fm.createDirectory(at: binDir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        let items: [(resource: String, ext: String?, dest: URL, mode: Int)] = [
            ("termpet-hook", nil, hookScript, 0o755),
            ("zsh-integration", "zsh", zshIntegration, 0o644),
        ]
        for item in items {
            guard let src = bundle.url(forResource: item.resource, withExtension: item.ext),
                  let data = try? Data(contentsOf: src) else {
                NSLog("[TermPet] bundled resource missing: \(item.resource)")
                continue
            }
            if (try? Data(contentsOf: item.dest)) == data { continue }
            do {
                try data.write(to: item.dest, options: .atomic)
                try fm.setAttributes([.posixPermissions: item.mode], ofItemAtPath: item.dest.path)
            } catch {
                NSLog("[TermPet] failed to install \(item.dest.path): \(error)")
            }
        }
    }
}
