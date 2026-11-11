import Foundation
import Observation

/// 사용 가능한 캐릭터 목록(친구들)과 선택 상태.
/// - 친구들(그림 팩 여러 개): ~/Library/Application Support/TermPet/Friends/<id>/character.json
///   → 저작권 그림은 저장소에 넣지 않고 이 폴더에만 둔다. 첫 친구가 기본 선택.
/// - 친구 팩이 하나도 없을 때만 내장 캐릭터(말랑이) 하나를 대신 보여준다 (앱이 빈 화면이 되지 않게).
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
    /// 친구 팩이 하나도 없을 때의 대체 캐릭터
    static let defaultId = BuiltInStyle.mallang.id
    static let friendPrefix = "friend."

    static var defaultFriendsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TermPet/Friends", isDirectory: true)
    }

    let friendsDirectory: URL
    private let defaults: UserDefaults
    /// 삭제 방법: 기본은 휴지통으로 (잘못 지워도 Finder 휴지통에서 되살릴 수 있게). 테스트에서는 바꿔 끼운다.
    @ObservationIgnored var trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }

    private(set) var entries: [Entry] = []
    private(set) var selectedId: String

    init(friendsDirectory: URL = CharacterLibrary.defaultFriendsDirectory, defaults: UserDefaults = .standard) {
        self.friendsDirectory = friendsDirectory
        self.defaults = defaults
        self.selectedId = defaults.string(forKey: Self.selectedDefaultsKey) ?? ""
        reload()
    }

    /// 처음 실행(선택 기록 없음)이거나 선택한 캐릭터가 사라졌을 때 쓸 캐릭터: 첫 친구
    var fallbackId: String { entries.first?.id ?? Self.defaultId }

    // MARK: - 목록

    func reload() {
        var list = loadFriends()
        if list.isEmpty {
            list = [Entry(id: BuiltInStyle.mallang.id, name: BuiltInStyle.mallang.name, source: .builtIn(.mallang))]
        }
        entries = list
        if !list.contains(where: { $0.id == selectedId }) { selectedId = fallbackId }
    }

    /// Friends 폴더의 팩들 (order → 이름 순). 읽지 못한 팩은 건너뛴다.
    private func loadFriends() -> [Entry] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: friendsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return folders.compactMap { folder -> (Int, Entry)? in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("character.json")),
                  let pack = try? CharacterPack.decode(data) else { return nil }
            return (pack.order ?? 999, Entry(id: Self.friendPrefix + pack.id, name: pack.name ?? pack.id, source: .pack(folder)))
        }
        .sorted { ($0.0, $0.1.name) < ($1.0, $1.1.name) }
        .map(\.1)
    }

    // MARK: - 삭제

    /// 친구 팩만 지울 수 있다 (내장 캐릭터는 대체용이라 목록에서 못 지움).
    func canRemove(_ entry: Entry) -> Bool {
        if case .pack = entry.source { return true }
        return false
    }

    /// 친구 삭제: 폴더를 휴지통으로 옮기고 목록을 다시 읽는다.
    /// 지운 친구가 선택돼 있었으면 선택이 첫 친구로 바뀐다 (호출 측이 그 캐릭터를 다시 불러와야 함).
    func remove(_ id: String) throws {
        guard let entry = entries.first(where: { $0.id == id }), case .pack(let folder) = entry.source else { return }
        try trash(folder)
        reload()
        defaults.set(selectedId, forKey: Self.selectedDefaultsKey)
    }

    // MARK: - 선택

    var selectedEntry: Entry {
        entries.first { $0.id == selectedId } ?? entries[0]
    }

    /// 항목을 실제로 불러온다. 실패하면 에러를 던진다 (호출 측에서 대체 캐릭터로).
    func load(_ entry: Entry) throws -> LoadedCharacter {
        switch entry.source {
        case .builtIn(let style): return .builtIn(style)
        case .pack(let folder):
            let sprite = try SpriteCharacter(folder: folder)
            sprite.libraryId = entry.id
            return .sprite(sprite)
        }
    }

    func select(_ id: String) {
        guard entries.contains(where: { $0.id == id }) else { return }
        selectedId = id
        defaults.set(id, forKey: Self.selectedDefaultsKey)
    }
}
