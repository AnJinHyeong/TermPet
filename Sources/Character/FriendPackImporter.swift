import Foundation

/// 친구 팩 가져오기: zip(또는 폴더)을 받아 그 안의 캐릭터 팩들을 Friends 폴더에 설치한다.
/// - zip 안 어디에 있든 `character.json`이 든 폴더를 모두 찾아서 하나씩 설치 (여러 친구를 한 번에)
/// - 더하기: 기존 친구는 그대로 두고, 같은 id의 친구만 새 것으로 바꾼다
/// UI와 분리된 순수 로직 (React 비유: 컴포넌트 밖의 유틸 함수 모듈)
enum FriendPackImporter {
    enum ImportError: LocalizedError {
        case unzipFailed(String)
        case noPacks(found: [String])

        var errorDescription: String? {
            switch self {
            case .unzipFailed(let reason):
                return "zip 파일을 풀지 못했어요." + (reason.isEmpty ? "" : "\n(\(reason))")
            case .noPacks(let found):
                let list = found.prefix(8).joined(separator: ", ")
                return "캐릭터 팩(character.json)을 찾지 못했어요." + (list.isEmpty ? "\n(zip 안이 비어 있어요)" : "\n안에 있던 것: \(list)")
            }
        }
    }

    /// 설치하고, 설치된 팩 id 목록(character.json의 id)을 돌려준다
    /// - 기존 친구는 남기고 더한다. 같은 id의 친구가 있으면 (폴더 이름이 달라도) 그 친구만 새 것으로 바꾼다.
    /// - 팩을 무사히 찾고 복사 준비가 끝난 뒤에만 Friends 폴더를 건드린다 → 잘못된 zip이면 아무것도 안 바뀜
    @discardableResult
    static func importPacks(from source: URL, into friendsDirectory: URL) throws -> [String] {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("termpet-import-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        var root = source
        if source.pathExtension.lowercased() == "zip" {
            // 먼저 앱이 직접 임시 폴더로 복사 → 거기서 푼다.
            // (다운로드·데스크탑 폴더는 macOS 개인정보 보호로, 파일 선택 창에서 고른 앱 자신만 읽을 수 있고
            //  앱이 실행한 압축 도구(ditto)는 막힐 수 있다)
            let copy = dir.appendingPathComponent("source.zip")
            try fm.copyItem(at: source, to: copy)
            let unpacked = dir.appendingPathComponent("unpacked", isDirectory: true)
            try unzip(copy, to: unpacked)
            try unzipNestedZips(in: unpacked)
            root = unpacked
        }

        let packs = findPacks(in: root)
        guard !packs.isEmpty else { throw ImportError.noPacks(found: listing(root)) }

        // 1) 먼저 임시 폴더에 모아 둔다 (고른 폴더가 Friends 안이어도 지우기 전에 안전하게 복사)
        let staging = dir.appendingPathComponent("staging", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        var installed: [String] = []
        for (folder, id) in packs where !installed.contains(id) {
            try fm.copyItem(at: folder, to: staging.appendingPathComponent(safeFolderName(id), isDirectory: true))
            installed.append(id)
        }
        // 2) 같은 id의 기존 친구만 지운다 (직접 복사해 넣어 폴더 이름이 id와 다른 경우도). 다른 친구는 그대로
        try fm.createDirectory(at: friendsDirectory, withIntermediateDirectories: true)
        for (old, id) in findPacks(in: friendsDirectory) where installed.contains(id) {
            try fm.removeItem(at: old)
        }
        // 3) 새 친구 넣기 (같은 이름의 폴더가 남아 있으면 교체)
        for id in installed {
            let name = safeFolderName(id)
            let dest = friendsDirectory.appendingPathComponent(name, isDirectory: true)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.moveItem(at: staging.appendingPathComponent(name, isDirectory: true), to: dest)
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

    /// zip 안에 또 zip이 있으면 (메신저로 보내며 한 번 더 감싸진 경우) 그 자리에 풀어 둔다. 한 단계만.
    private static func unzipNestedZips(in dir: URL) throws {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        let zips = walker.compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "zip" && !$0.path.contains("/__MACOSX/") }
        for zip in zips {
            let target = zip.deletingPathExtension()
            try? unzip(zip, to: target.appendingPathExtension("unzipped"))
        }
    }

    /// 실패 안내용: 풀린 내용물 이름 (맨 위 두 단계)
    private static func listing(_ root: URL) -> [String] {
        let fm = FileManager.default
        let top = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return top.filter { $0.lastPathComponent != "__MACOSX" }.sorted { $0.path < $1.path }.flatMap { item -> [String] in
            let kids = (try? fm.contentsOfDirectory(atPath: item.path))?.filter { !$0.hasPrefix(".") }.sorted() ?? []
            return kids.isEmpty ? [item.lastPathComponent] : kids.map { item.lastPathComponent + "/" + $0 }
        }
    }

    /// macOS 기본 도구 ditto로 압축 풀기 (Finder의 압축 풀기와 같은 방식)
    private static func unzip(_ zip: URL, to dir: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, dir.path]
        let errPipe = Pipe()
        p.standardOutput = FileHandle.nullDevice
        p.standardError = errPipe
        do { try p.run() } catch { throw ImportError.unzipFailed(error.localizedDescription) }
        let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw ImportError.unzipFailed(errText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
