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
        XCTAssertEqual(LoadedCharacter.sprite(sprite).id, "pack.pix")
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

    func testScansPacksAndReportsProblems() {
        SpriteCharacterTests.makePack(in: dir.appendingPathComponent("good"), id: "good")
        SpriteCharacterTests.makePack(in: dir.appendingPathComponent("dup"), id: "good")
        SpriteCharacterTests.makePack(in: dir.appendingPathComponent("broken"),
                                      json: #"{"id":"x","frameWidth":8}"#)
        let lib = CharacterLibrary(directory: dir, defaults: defaults)
        XCTAssertEqual(lib.entries.filter { $0.id == "pack.good" }.count, 1)
        XCTAssertEqual(lib.entries.first { $0.id == "pack.good" }?.name, "픽셀")
        XCTAssertEqual(lib.problems.count, 2)
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

    func testImportCopiesValidatedPackAndReplacesSameId() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("termpet-src-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: source) }
        SpriteCharacterTests.makePack(in: source, id: "imported")

        let lib = CharacterLibrary(directory: dir, defaults: defaults)
        XCTAssertEqual(try lib.importPack(from: source), "pack.imported")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("imported/character.json").path))
        XCTAssertNoThrow(try lib.importPack(from: source)) // 두 번째는 교체
        XCTAssertEqual(lib.entries.filter { $0.id == "pack.imported" }.count, 1)
        if case .sprite = try lib.load(lib.entries.first { $0.id == "pack.imported" }!) {} else { XCTFail() }
    }

    func testImportRejectsInvalidPackWithoutCopying() {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("termpet-bad-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: source) }
        SpriteCharacterTests.makePack(in: source, json: #"{"id":"bad","frameWidth":16,"frameHeight":16,"states":{"idle":{"file":"missing.png"}}}"#)
        let lib = CharacterLibrary(directory: dir, defaults: defaults)
        XCTAssertThrowsError(try lib.importPack(from: source))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("bad").path))
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
