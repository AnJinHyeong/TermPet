import Foundation
import Observation

/// 사용 가능한 캐릭터 목록 (기본 캐릭터 + 커스텀 팩) 과 선택 상태.
/// 커스텀 팩 위치: ~/Library/Application Support/TermPet/Characters/<id>/character.json
@Observable
final class CharacterLibrary {
    struct Entry: Identifiable, Equatable {
        enum Source: Equatable {
            case builtIn(BuiltInStyle)
            case pack(URL)
        }
        let id: String
        let name: String
        let source: Source
    }

    static let selectedDefaultsKey = "characterId"
    static let defaultId = BuiltInStyle.mallang.id

    static func packEntryId(_ packId: String) -> String { "pack.\(packId)" }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TermPet/Characters", isDirectory: true)
    }

    let directory: URL
    private let defaults: UserDefaults

    private(set) var entries: [Entry] = []
    /// 읽지 못한 팩 폴더와 이유 (설정 화면/메뉴에 표시용)
    private(set) var problems: [String] = []
    private(set) var selectedId: String

    init(directory: URL = CharacterLibrary.defaultDirectory, defaults: UserDefaults = .standard) {
        self.directory = directory
        self.defaults = defaults
        self.selectedId = defaults.string(forKey: Self.selectedDefaultsKey) ?? Self.defaultId
        reload()
    }

    // MARK: - 목록

    /// 폴더를 다시 스캔. JSON만 가볍게 읽어 목록을 만들고, 이미지는 선택할 때 읽는다.
    func reload() {
        var list = BuiltInStyle.allCases.map { Entry(id: $0.id, name: $0.name, source: .builtIn($0)) }
        var problems: [String] = []
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let folders = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey],
                                                   options: [.skipsHiddenFiles])) ?? []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let json = folder.appendingPathComponent("character.json")
            guard let data = try? Data(contentsOf: json) else { continue }
            do {
                let pack = try CharacterPack.decode(data)
                let id = Self.packEntryId(pack.id)
                guard !list.contains(where: { $0.id == id }) else {
                    problems.append("\(folder.lastPathComponent): id '\(pack.id)' 중복")
                    continue
                }
                list.append(Entry(id: id, name: pack.name ?? pack.id, source: .pack(folder)))
            } catch {
                let reason = (error as? CharacterPack.ValidationError)?.description ?? "JSON 형식 오류"
                problems.append("\(folder.lastPathComponent): \(reason)")
            }
        }
        entries = list
        self.problems = problems
        if !list.contains(where: { $0.id == selectedId }) { selectedId = Self.defaultId }
    }

    // MARK: - 선택

    var selectedEntry: Entry {
        entries.first { $0.id == selectedId } ?? entries[0]
    }

    /// 항목을 실제로 불러온다. 실패하면 에러를 던진다 (호출 측에서 기본 캐릭터로 대체).
    func load(_ entry: Entry) throws -> LoadedCharacter {
        switch entry.source {
        case .builtIn(let style): return .builtIn(style)
        case .pack(let folder): return .sprite(try SpriteCharacter(folder: folder))
        }
    }

    func select(_ id: String) {
        guard entries.contains(where: { $0.id == id }) else { return }
        selectedId = id
        defaults.set(id, forKey: Self.selectedDefaultsKey)
    }

    // MARK: - 가져오기

    /// 사용자가 고른 폴더를 검증한 뒤 캐릭터 폴더로 복사. 같은 id가 있으면 교체.
    /// 반환: 새 항목 id
    @discardableResult
    func importPack(from source: URL) throws -> String {
        let loaded = try SpriteCharacter(folder: source) // 이미지까지 전부 읽어서 검증
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let dest = directory.appendingPathComponent(loaded.pack.id, isDirectory: true)

        if source.standardizedFileURL != dest.standardizedFileURL {
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: source, to: dest)
        }
        reload()
        return Self.packEntryId(loaded.pack.id)
    }
}
