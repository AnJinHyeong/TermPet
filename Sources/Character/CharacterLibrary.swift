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
    /// 내가 만든 캐릭터는 하나만 둔다 → 항상 이 id / 이 폴더
    static let customId = "custom"
    static let customFolderName = "my-character"

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TermPet/Characters", isDirectory: true)
    }

    let directory: URL
    var customFolder: URL { directory.appendingPathComponent(Self.customFolderName, isDirectory: true) }
    private let defaults: UserDefaults
    /// 지우는 대신 휴지통으로 (복구 가능). 테스트에서는 바로 삭제로 바꿔 끼운다. (≈ 의존성 주입)
    private let discard: (URL) throws -> Void

    private(set) var entries: [Entry] = []
    /// 내 캐릭터를 읽지 못했을 때 이유 (메뉴에 표시)
    private(set) var problem: String?
    private(set) var selectedId: String

    init(directory: URL = CharacterLibrary.defaultDirectory, defaults: UserDefaults = .standard,
         discard: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.directory = directory
        self.defaults = defaults
        self.discard = discard
        self.selectedId = defaults.string(forKey: Self.selectedDefaultsKey) ?? Self.defaultId
        migrateOldPacks()
        reload()
    }

    // MARK: - 목록

    /// 기본 캐릭터 + (있으면) 내 캐릭터 하나
    func reload() {
        var list = BuiltInStyle.allCases.map { Entry(id: $0.id, name: $0.name, source: .builtIn($0)) }
        problem = nil
        let json = customFolder.appendingPathComponent("character.json")
        if let data = try? Data(contentsOf: json) {
            do {
                let pack = try CharacterPack.decode(data)
                list.append(Entry(id: Self.customId, name: pack.name ?? "내 캐릭터", source: .pack(customFolder)))
            } catch {
                problem = (error as? CharacterPack.ValidationError)?.description ?? "character.json 형식 오류"
            }
        }
        entries = list
        if !list.contains(where: { $0.id == selectedId }) { selectedId = Self.defaultId }
    }

    var custom: Entry? { entries.first { $0.id == Self.customId } }

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

    // MARK: - 내 캐릭터 (하나만)

    /// 새로 만든 팩 폴더로 내 캐릭터를 교체 (기존 것은 휴지통). 이동이라 원본 폴더는 사라진다.
    func installCustom(from builtFolder: URL) throws {
        _ = try SpriteCharacter(folder: builtFolder) // 이미지까지 읽어서 검증
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if fm.fileExists(atPath: customFolder.path) { try discard(customFolder) }
        try fm.moveItem(at: builtFolder, to: customFolder)
        reload()
        select(Self.customId)
    }

    /// 내 캐릭터 삭제 (휴지통) → 기본 캐릭터로
    func removeCustom() throws {
        if FileManager.default.fileExists(atPath: customFolder.path) { try discard(customFolder) }
        reload()
        if selectedId == Self.defaultId { defaults.set(selectedId, forKey: Self.selectedDefaultsKey) }
    }

    /// 걷는 방향이 반대로 보일 때: 그림이 바라보는 방향(left ↔ right)을 뒤집는다
    func flipCustomFacing() throws {
        let json = customFolder.appendingPathComponent("character.json")
        var pack = try CharacterPack.decode(Data(contentsOf: json))
        pack.facing = (pack.facing == "left") ? "right" : "left"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(pack).write(to: json)
    }

    /// 예전 버전(캐릭터 여러 개)에서 넘어올 때 한 번: 선택돼 있던(없으면 가장 최근) 팩을 내 캐릭터로 옮기고
    /// 나머지는 휴지통으로. 선택 id `pack.xxx` → `custom`.
    func migrateOldPacks() {
        let fm = FileManager.default
        let folders = ((try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
                                                    options: [.skipsHiddenFiles])) ?? [])
            .filter { $0.lastPathComponent != Self.customFolderName }
            .compactMap { folder -> (URL, String, Date)? in
                guard let data = try? Data(contentsOf: folder.appendingPathComponent("character.json")),
                      let pack = try? CharacterPack.decode(data) else { return nil }
                let date = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                return (folder, "pack.\(pack.id)", date ?? .distantPast)
            }
        let wasPack = selectedId.hasPrefix("pack.")
        if !folders.isEmpty {
            if !fm.fileExists(atPath: customFolder.path) {
                let keep = folders.first { $0.1 == selectedId } ?? folders.max { $0.2 < $1.2 }!
                try? fm.moveItem(at: keep.0, to: customFolder)
            }
            for (folder, _, _) in folders where fm.fileExists(atPath: folder.path) { try? discard(folder) }
        }
        if wasPack {
            selectedId = Self.customId
            defaults.set(selectedId, forKey: Self.selectedDefaultsKey)
        }
    }
}
