import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import TermPet

final class CharacterPackTests: XCTestCase {
    private func decode(_ json: String) throws -> CharacterPack {
        try CharacterPack.decode(Data(json.utf8))
    }

    private let specExample = """
    {
      "id": "my-cat", "name": "냥이", "frameWidth": 64, "frameHeight": 64, "scale": 2, "walkSpeed": 40, "pixelArt": true,
      "states": {
        "idle":  { "file": "idle.png",  "frames": 4, "fps": 6,  "loop": true },
        "walk":  { "file": "walk.png",  "frames": 6, "fps": 10, "loop": true },
        "happy": { "file": "happy.png", "frames": 6, "fps": 12, "loop": true }
      },
      "messages": { "done": ["끝났어!", "작업 완료~"], "error": ["에러 났어…"], "ask": ["확인해줘!"] }
    }
    """

    func testDecodesSpecExample() throws {
        let pack = try decode(specExample)
        XCTAssertEqual(pack.id, "my-cat")
        XCTAssertEqual(pack.name, "냥이")
        XCTAssertEqual(pack.states["walk"]?.frames, 6)
        XCTAssertEqual(pack.displaySize, CGSize(width: 128, height: 128))
        XCTAssertEqual(pack.bubbleMessages.done, ["끝났어!", "작업 완료~"])
    }

    func testMinimalPackUsesDefaults() throws {
        let pack = try decode(#"{"id":"a","frameWidth":32,"frameHeight":32,"states":{"idle":{"file":"idle.png"}}}"#)
        XCTAssertEqual(pack.effectiveScale, 1)
        XCTAssertEqual(pack.bubbleMessages, BubbleMessages.default)
    }

    func testEmptyMessageListsFallBack() throws {
        let pack = try decode(#"{"id":"a","frameWidth":8,"frameHeight":8,"states":{"idle":{"file":"i.png"}},"messages":{"done":[],"ask":[""]}}"#)
        XCTAssertEqual(pack.bubbleMessages.done, BubbleMessages.default.done)
        XCTAssertEqual(pack.bubbleMessages.ask, BubbleMessages.default.ask)
    }

    func testValidationErrors() {
        let cases: [(String, CharacterPack.ValidationError)] = [
            (#"{"id":"bad id","frameWidth":8,"frameHeight":8,"states":{"idle":{"file":"i.png"}}}"#, .invalidId),
            (#"{"id":"../x","frameWidth":8,"frameHeight":8,"states":{"idle":{"file":"i.png"}}}"#, .invalidId),
            (#"{"id":"a","frameWidth":0,"frameHeight":8,"states":{"idle":{"file":"i.png"}}}"#, .invalidFrameSize),
            (#"{"id":"a","frameWidth":8,"frameHeight":8,"scale":20,"states":{"idle":{"file":"i.png"}}}"#, .invalidScale),
            (#"{"id":"a","frameWidth":8,"frameHeight":8,"states":{"walk":{"file":"w.png"}}}"#, .missingIdleState),
            (#"{"id":"a","frameWidth":8,"frameHeight":8,"states":{"idle":{"file":"../../etc/x.png"}}}"#, .unsafeFilePath("../../etc/x.png")),
        ]
        for (json, expected) in cases {
            XCTAssertThrowsError(try decode(json)) { error in
                XCTAssertEqual(error as? CharacterPack.ValidationError, expected, json)
            }
        }
    }

    func testHugeSizeIsShrunk() throws {
        let pack = try decode(#"{"id":"a","frameWidth":1000,"frameHeight":500,"scale":2,"states":{"idle":{"file":"i.png"}}}"#)
        XCTAssertEqual(pack.displaySize, CGSize(width: 512, height: 256))
    }

    func testSpriteTiming() {
        let loop = SpriteTiming(frameCount: 4, fps: 10, loop: true)
        XCTAssertEqual(loop.frameIndex(at: 0), 0)
        XCTAssertEqual(loop.frameIndex(at: 0.25), 2)
        XCTAssertEqual(loop.frameIndex(at: 0.45), 0) // 4.5프레임 → 4 % 4
        let once = SpriteTiming(frameCount: 4, fps: 10, loop: false)
        XCTAssertEqual(once.frameIndex(at: 10), 3)
        XCTAssertEqual(SpriteTiming(frameCount: 1, fps: 10, loop: true).frameIndex(at: 5), 0)
        XCTAssertEqual(SpriteTiming(frameCount: 4, fps: 0, loop: true).frameIndex(at: 5), 0)
    }
}

final class SpriteCharacterTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("termpet-chars-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    /// 테스트용 PNG (가로 frames*fw x fh)
    static func writePNG(_ url: URL, width: Int, height: Int) {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
    }

    static func makePack(in folder: URL, id: String = "pix", json: String? = nil) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let body = json ?? """
        {"id":"\(id)","name":"픽셀","frameWidth":16,"frameHeight":16,"scale":3,"pixelArt":true,
         "states":{"idle":{"file":"idle.png","fps":5},"walk":{"file":"walk.png","frames":10,"fps":8},"oops":{"file":"x.png"}}}
        """
        try? Data(body.utf8).write(to: folder.appendingPathComponent("character.json"))
        writePNG(folder.appendingPathComponent("idle.png"), width: 64, height: 16)  // 4프레임
        writePNG(folder.appendingPathComponent("walk.png"), width: 96, height: 16)  // 6프레임
    }

    func testLoadsFramesAndFallsBackToIdle() throws {
        Self.makePack(in: dir)
        let sprite = try SpriteCharacter(folder: dir)
        XCTAssertEqual(sprite.animation(for: .idle)?.frames.count, 4)       // frames 생략 → 너비/프레임폭
        XCTAssertEqual(sprite.animation(for: .walk)?.frames.count, 6)       // 10 요청했지만 6개뿐
        XCTAssertEqual(sprite.animation(for: .angry)?.frames.count, 4)      // 정의 안 됨 → idle
        XCTAssertEqual(sprite.frame(for: .walk, elapsed: 0)?.width, 16)
        XCTAssertTrue(sprite.pixelArt)
        XCTAssertEqual(LoadedCharacter.sprite(sprite).size, CGSize(width: 48, height: 48))
    }

    func testMissingImageFails() {
        Self.makePack(in: dir, json: #"{"id":"a","frameWidth":16,"frameHeight":16,"states":{"idle":{"file":"nope.png"}}}"#)
        XCTAssertThrowsError(try SpriteCharacter(folder: dir))
    }

    func testImageSmallerThanFrameFails() {
        Self.makePack(in: dir, json: #"{"id":"a","frameWidth":100,"frameHeight":16,"states":{"idle":{"file":"idle.png"}}}"#)
        XCTAssertThrowsError(try SpriteCharacter(folder: dir))
    }

    func testMissingJSONFails() {
        XCTAssertThrowsError(try SpriteCharacter(folder: dir))
    }
}

final class CharacterLibraryTests: XCTestCase {
    private var dir: URL!
    private var defaults: UserDefaults!
    private let suite = "CharacterLibraryTests"

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("termpet-friends-\(UUID().uuidString)")
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        defaults.removePersistentDomain(forName: suite)
    }

    /// 친구 팩이 하나도 없으면 말랑이 하나만 (빈 화면 방지용)
    func testNoFriendsFallsBackToSingleBuiltIn() {
        let lib = CharacterLibrary(friendsDirectory: dir, defaults: defaults)
        XCTAssertEqual(lib.entries.map(\.id), [CharacterLibrary.defaultId])
        XCTAssertEqual(lib.selectedId, CharacterLibrary.defaultId)
    }

    func testOnlyFriendsListedAndSelectPersists() {
        SpriteCharacterTests.makePack(in: dir.appendingPathComponent("a"), id: "a")
        SpriteCharacterTests.makePack(in: dir.appendingPathComponent("b"), id: "b")
        let lib = CharacterLibrary(friendsDirectory: dir, defaults: defaults)
        XCTAssertEqual(Set(lib.entries.map(\.id)), ["friend.a", "friend.b"])
        lib.select("friend.b")
        lib.select(BuiltInStyle.cat.id) // 목록에 없는 기본 캐릭터는 무시
        XCTAssertEqual(lib.selectedId, "friend.b")
        XCTAssertEqual(CharacterLibrary(friendsDirectory: dir, defaults: defaults).selectedId, "friend.b")
    }

    /// 삭제: 휴지통 함수로 폴더를 넘기고, 선택돼 있던 친구면 첫 친구로. 마지막 친구까지 지우면 말랑이
    func testRemoveFriend() throws {
        SpriteCharacterTests.makePack(in: dir.appendingPathComponent("a"), id: "a")
        SpriteCharacterTests.makePack(in: dir.appendingPathComponent("b"), id: "b")
        let lib = CharacterLibrary(friendsDirectory: dir, defaults: defaults)
        var trashed: [String] = []
        lib.trash = { url in trashed.append(url.lastPathComponent); try FileManager.default.removeItem(at: url) }
        lib.select("friend.b")
        try lib.remove("friend.b")
        XCTAssertEqual(trashed, ["b"])
        XCTAssertEqual(lib.entries.map(\.id), ["friend.a"])
        XCTAssertEqual(lib.selectedId, "friend.a")
        XCTAssertEqual(defaults.string(forKey: CharacterLibrary.selectedDefaultsKey), "friend.a")
        try lib.remove(CharacterLibrary.defaultId) // 목록에 없는/내장 id 는 무시
        try lib.remove("friend.a")
        XCTAssertEqual(lib.entries.map(\.id), [CharacterLibrary.defaultId])
        XCTAssertFalse(lib.canRemove(lib.entries[0]))
    }

    /// 예전에 고른 기본 캐릭터·내 캐릭터(custom)는 첫 친구로 바뀐다
    func testOldSelectionFallsBackToFirstFriend() {
        SpriteCharacterTests.makePack(in: dir.appendingPathComponent("a"), id: "a")
        for old in ["custom", BuiltInStyle.cat.id] {
            defaults.set(old, forKey: CharacterLibrary.selectedDefaultsKey)
            XCTAssertEqual(CharacterLibrary(friendsDirectory: dir, defaults: defaults).selectedId, "friend.a")
        }
    }
}

final class FriendPackImporterTests: XCTestCase {
    private var tmp: URL!
    private var friends: URL { tmp.appendingPathComponent("Friends") }

    override func setUp() {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("importer-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    /// 폴더 → zip (Finder 압축과 같은 ditto 사용)
    private func zip(_ folder: URL) -> URL {
        let out = tmp.appendingPathComponent("\(folder.lastPathComponent).zip")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", folder.path, out.path]
        try? p.run(); p.waitUntilExit()
        return out
    }

    func testImportsAllPacksFromZipAndLibrarySeesThem() throws {
        let src = tmp.appendingPathComponent("MyFriends")
        SpriteCharacterTests.makePack(in: src.appendingPathComponent("a"), id: "alpha")
        SpriteCharacterTests.makePack(in: src.appendingPathComponent("nested/b"), id: "beta")
        let ids = try FriendPackImporter.importPacks(from: zip(src), into: friends)
        XCTAssertEqual(Set(ids), ["alpha", "beta"])

        let defaults = UserDefaults(suiteName: "importer-\(UUID().uuidString)")!
        let library = CharacterLibrary(friendsDirectory: friends, defaults: defaults)
        XCTAssertEqual(Set(library.entries.map(\.id)), ["friend.alpha", "friend.beta"])
        XCTAssertNoThrow(try library.load(library.entries[0]))
    }

    func testReplacesExistingPackWithSameId() throws {
        SpriteCharacterTests.makePack(in: friends.appendingPathComponent("alpha"), id: "alpha")
        try Data("old".utf8).write(to: friends.appendingPathComponent("alpha/stale.txt"))
        let src = tmp.appendingPathComponent("new/alpha")
        SpriteCharacterTests.makePack(in: src, id: "alpha")
        try FriendPackImporter.importPacks(from: src, into: friends)  // 폴더도 받는다
        XCTAssertFalse(FileManager.default.fileExists(atPath: friends.appendingPathComponent("alpha/stale.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: friends.appendingPathComponent("alpha/character.json").path))
    }

    func testZipInsideZipIsUnpacked() throws {
        let src = tmp.appendingPathComponent("Inner")
        SpriteCharacterTests.makePack(in: src.appendingPathComponent("a"), id: "alpha")
        let inner = zip(src)
        let outer = tmp.appendingPathComponent("Outer")
        try FileManager.default.createDirectory(at: outer, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: inner, to: outer.appendingPathComponent("Inner.zip"))
        XCTAssertEqual(try FriendPackImporter.importPacks(from: zip(outer), into: friends), ["alpha"])
    }

    func testNoPacksErrorListsContents() throws {
        let src = tmp.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try Data("hi".utf8).write(to: src.appendingPathComponent("readme.txt"))
        XCTAssertThrowsError(try FriendPackImporter.importPacks(from: zip(src), into: friends)) { error in
            XCTAssertTrue(error.localizedDescription.contains("empty/readme.txt"), error.localizedDescription)
        }
    }

    func testImportReplacesAllExistingFriends() throws {
        SpriteCharacterTests.makePack(in: friends.appendingPathComponent("old"), id: "old")
        let src = tmp.appendingPathComponent("New")
        SpriteCharacterTests.makePack(in: src.appendingPathComponent("a"), id: "alpha")
        try FriendPackImporter.importPacks(from: zip(src), into: friends)
        let names = try FileManager.default.contentsOfDirectory(atPath: friends.path).filter { !$0.hasPrefix(".") }
        XCTAssertEqual(names, ["alpha"])   // 기존 친구(old)는 지워지고 새 친구만
    }

    func testBadZipKeepsExistingFriends() throws {
        SpriteCharacterTests.makePack(in: friends.appendingPathComponent("old"), id: "old")
        let bad = tmp.appendingPathComponent("bad.zip")
        try Data("not a zip".utf8).write(to: bad)
        XCTAssertThrowsError(try FriendPackImporter.importPacks(from: bad, into: friends))
        XCTAssertTrue(FileManager.default.fileExists(atPath: friends.appendingPathComponent("old/character.json").path))
    }

    func testPickingFolderInsideFriendsStillWorks() throws {
        SpriteCharacterTests.makePack(in: friends.appendingPathComponent("alpha"), id: "alpha")
        XCTAssertEqual(try FriendPackImporter.importPacks(from: friends, into: friends), ["alpha"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: friends.appendingPathComponent("alpha/character.json").path))
    }

    func testZipWithoutPacksFails() throws {
        let src = tmp.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try Data("hi".utf8).write(to: src.appendingPathComponent("readme.txt"))
        XCTAssertThrowsError(try FriendPackImporter.importPacks(from: zip(src), into: friends))
    }

    func testBrokenZipFails() throws {
        let bad = tmp.appendingPathComponent("bad.zip")
        try Data("not a zip".utf8).write(to: bad)
        XCTAssertThrowsError(try FriendPackImporter.importPacks(from: bad, into: friends))
    }

    func testSafeFolderNameBlocksPathTricks() {
        XCTAssertEqual(FriendPackImporter.safeFolderName("../evil"), "_evil")
        XCTAssertEqual(FriendPackImporter.safeFolderName(".."), "friend")
        XCTAssertEqual(FriendPackImporter.safeFolderName("usagi"), "usagi")
    }
}
