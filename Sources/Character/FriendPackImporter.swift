import Foundation

/// 친구 팩 가져오기: zip(또는 폴더)을 받아 그 안의 캐릭터 팩들을 Friends 폴더에 설치한다.
/// - zip 안 어디에 있든 `character.json`이 든 폴더를 모두 찾아서 하나씩 설치 (여러 친구를 한 번에)
/// - 같은 id 팩이 이미 있으면 새것으로 교체
/// UI와 분리된 순수 로직 (React 비유: 컴포넌트 밖의 유틸 함수 모듈)
enum FriendPackImporter {
    enum ImportError: LocalizedError {
        case unzipFailed
        case noPacks

        var errorDescription: String? {
            switch self {
            case .unzipFailed: return "zip 파일을 풀지 못했어요."
            case .noPacks: return "캐릭터 팩(character.json)을 찾지 못했어요."
            }
        }
    }

    /// 설치하고, 설치된 팩 id 목록(character.json의 id)을 돌려준다
    @discardableResult
    static func importPacks(from source: URL, into friendsDirectory: URL) throws -> [String] {
        let fm = FileManager.default
        var tempDir: URL?
        defer { if let tempDir { try? fm.removeItem(at: tempDir) } }

        var root = source
        if source.pathExtension.lowercased() == "zip" {
            let dir = fm.temporaryDirectory.appendingPathComponent("termpet-import-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            tempDir = dir
            try unzip(source, to: dir)
            root = dir
        }

        let packs = findPacks(in: root)
        guard !packs.isEmpty else { throw ImportError.noPacks }

        try fm.createDirectory(at: friendsDirectory, withIntermediateDirectories: true)
        var installed: [String] = []
        for (folder, id) in packs where !installed.contains(id) {
            let dest = friendsDirectory.appendingPathComponent(safeFolderName(id), isDirectory: true)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: folder, to: dest)
            installed.append(id)
        }
        return installed
    }

    /// root 아래(자기 자신 포함)에서 읽을 수 있는 character.json이 든 폴더들 → (폴더, 팩 id)
    /// macOS zip에 끼는 __MACOSX·숨김 폴더는 건너뛴다. 이름순이라 결과가 항상 같다.
    static func findPacks(in root: URL) -> [(URL, String)] {
        let fm = FileManager.default
        var result: [(URL, String)] = []
        var queue = [root]
        while !queue.isEmpty {
            let dir = queue.removeFirst()
            if let data = try? Data(contentsOf: dir.appendingPathComponent("character.json")),
               let pack = try? CharacterPack.decode(data) {
                result.append((dir, pack.id))
                continue // 팩 폴더 안은 더 들어가지 않는다
            }
            let children = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                         options: [.skipsHiddenFiles])) ?? []
            queue += children
                .filter { $0.lastPathComponent != "__MACOSX" && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        return result
    }

    /// 팩 id → 폴더 이름 (경로 문자 제거, "../" 같은 이름으로 밖에 쓰지 못하게)
    static func safeFolderName(_ id: String) -> String {
        let cleaned = id.map { "/\\:".contains($0) ? "_" : $0 }
        let name = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return name.isEmpty ? "friend" : name
    }

    /// macOS 기본 도구 ditto로 압축 풀기 (Finder의 압축 풀기와 같은 방식)
    private static func unzip(_ zip: URL, to dir: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, dir.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { throw ImportError.unzipFailed }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw ImportError.unzipFailed }
    }
}
