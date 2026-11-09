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
        XCTAssertEqual(LoadedCharacter.sprite(sprite).id, CharacterLibrary.customId)
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
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("termpet-lib-\(UUID().uuidString)")
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        defaults.removePersistentDomain(forName: suite)
    }

    func testBuiltInsAlwaysPresentAndDefaultSelected() {
        let lib = CharacterLibrary(directory: dir, defaults: defaults)
        XCTAssertEqual(lib.entries.map(\.id), BuiltInStyle.allCases.map(\.id))
        XCTAssertEqual(lib.selectedId, CharacterLibrary.defaultId)
    }

    func testSelectPersistsAndUnknownIsIgnored() {
        let lib = CharacterLibrary(directory: dir, defaults: defaults)
        lib.select(BuiltInStyle.cat.id)
        lib.select("pack.nope")
        XCTAssertEqual(lib.selectedId, BuiltInStyle.cat.id)
        XCTAssertEqual(CharacterLibrary(directory: dir, defaults: defaults).selectedId, BuiltInStyle.cat.id)
    }

    func testMissingSelectedPackFallsBackToDefault() {
        defaults.set("pack.gone", forKey: CharacterLibrary.selectedDefaultsKey)
        XCTAssertEqual(CharacterLibrary(directory: dir, defaults: defaults).selectedId, CharacterLibrary.defaultId)
    }

    private func lib() -> CharacterLibrary {
        CharacterLibrary(directory: dir, defaults: defaults, discard: { try FileManager.default.removeItem(at: $0) })
    }

    private func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path)
    }

    func testCustomSlotListedAfterBuiltIns() {
        SpriteCharacterTests.makePack(in: dir.appendingPathComponent(CharacterLibrary.customFolderName), id: "whatever")
        let l = lib()
        XCTAssertEqual(l.entries.map(\.id), BuiltInStyle.allCases.map(\.id) + [CharacterLibrary.customId])
        XCTAssertEqual(l.custom?.name, "픽셀")
        XCTAssertNil(l.problem)
    }

    func testBrokenCustomReportsProblem() {
        SpriteCharacterTests.makePack(in: dir.appendingPathComponent(CharacterLibrary.customFolderName),
                                      json: #"{"id":"x","frameWidth":8}"#)
        let l = lib()
        XCTAssertNil(l.custom)
        XCTAssertNotNil(l.problem)
    }

    func testMigrationKeepsSelectedOldPackAndDiscardsOthers() {
        SpriteCharacterTests.makePack(in: dir.appendingPathComponent("img-a"), id: "img-a")
        SpriteCharacterTests.makePack(in: dir.appendingPathComponent("img-b"), id: "img-b")
        defaults.set("pack.img-b", forKey: CharacterLibrary.selectedDefaultsKey)
        let l = lib()
        XCTAssertTrue(exists(CharacterLibrary.customFolderName))
        XCTAssertFalse(exists("img-a"))
        XCTAssertFalse(exists("img-b"))
        XCTAssertEqual(l.selectedId, CharacterLibrary.customId)
        XCTAssertEqual(defaults.string(forKey: CharacterLibrary.selectedDefaultsKey), CharacterLibrary.customId)
        // 선택돼 있던 img-b가 남았는지: 팩 id로 확인
        if case .sprite(let s) = try? l.load(l.custom!) { XCTAssertEqual(s.pack.id, "img-b") } else { XCTFail() }
    }

    func testMigrationLeavesBuiltInSelectionAlone() {
        SpriteCharacterTests.makePack(in: dir.appendingPathComponent("img-a"), id: "img-a")
        defaults.set(BuiltInStyle.cat.id, forKey: CharacterLibrary.selectedDefaultsKey)
        let l = lib()
        XCTAssertEqual(l.selectedId, BuiltInStyle.cat.id)
        XCTAssertNotNil(l.custom) // 옮겨는 둔다
    }

    func testInstallCustomReplacesAndSelects() throws {
        let built1 = dir.appendingPathComponent(".staging/one")
        SpriteCharacterTests.makePack(in: built1, id: "one")
        let l = lib()
        try l.installCustom(from: built1)
        XCTAssertEqual(l.selectedId, CharacterLibrary.customId)
        XCTAssertFalse(FileManager.default.fileExists(atPath: built1.path)) // 이동됨

        let built2 = dir.appendingPathComponent(".staging/two")
        SpriteCharacterTests.makePack(in: built2, id: "two")
        try l.installCustom(from: built2)
        XCTAssertEqual(l.entries.filter { $0.id == CharacterLibrary.customId }.count, 1)
        if case .sprite(let s) = try l.load(l.custom!) { XCTAssertEqual(s.pack.id, "two") } else { XCTFail() }
    }

    func testInstallRejectsInvalidPackAndKeepsOld() throws {
        SpriteCharacterTests.makePack(in: dir.appendingPathComponent(CharacterLibrary.customFolderName), id: "old")
        let bad = dir.appendingPathComponent(".staging/bad")
        SpriteCharacterTests.makePack(in: bad, json: #"{"id":"bad","frameWidth":16,"frameHeight":16,"states":{"idle":{"file":"missing.png"}}}"#)
        let l = lib()
        XCTAssertThrowsError(try l.installCustom(from: bad))
        XCTAssertNotNil(l.custom)
    }

    func testRemoveCustomFallsBackToDefault() throws {
        SpriteCharacterTests.makePack(in: dir.appendingPathComponent(CharacterLibrary.customFolderName), id: "c")
        let l = lib()
        l.select(CharacterLibrary.customId)
        try l.removeCustom()
        XCTAssertNil(l.custom)
        XCTAssertEqual(l.selectedId, CharacterLibrary.defaultId)
    }

    func testFlipFacingToggles() throws {
        SpriteCharacterTests.makePack(in: dir.appendingPathComponent(CharacterLibrary.customFolderName), id: "c")
        let l = lib()
        func facing() throws -> String? {
            try CharacterPack.decode(Data(contentsOf: l.customFolder.appendingPathComponent("character.json"))).facing
        }
        try l.flipCustomFacing()
        XCTAssertEqual(try facing(), "left")
        try l.flipCustomFacing()
        XCTAssertEqual(try facing(), "right")
    }
}

@MainActor
final class CharacterPackExporterTests: XCTestCase {
    func testExportedSamplePackLoadsBack() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("termpet-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = try CharacterPackExporter.export(.cat, to: dir)
        let sprite = try SpriteCharacter(folder: folder)
        XCTAssertEqual(sprite.pack.id, "cat-sprite")
        XCTAssertEqual(sprite.pack.displaySize, LoadedCharacter.defaultSize)
        for action in PetAction.allCases {
            XCTAssertGreaterThan(sprite.animation(for: action)?.frames.count ?? 0, 1, "\(action)")
        }
    }
}
