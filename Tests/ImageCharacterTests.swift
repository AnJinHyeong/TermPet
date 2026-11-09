import XCTest
import ImageIO
@testable import TermPet

final class BackgroundRemoverTests: XCTestCase {
    /// w x h 이미지: 흰 배경 + (2,2)~(w-3,h-3) 검은 테두리 사각형, 그 안은 흰색(=옷/얼굴처럼 배경색과 같은 내부)
    private func outlinedSquare(w: Int = 12, h: Int = 12) -> RGBAImage {
        var data = [UInt8](repeating: 255, count: w * h * 4)
        for y in 2...(h - 3) {
            for x in 2...(w - 3) where x == 2 || y == 2 || x == w - 3 || y == h - 3 {
                let i = (y * w + x) * 4
                data[i] = 0; data[i + 1] = 0; data[i + 2] = 0
            }
        }
        return RGBAImage(width: w, height: h, data: data)
    }

    func testFloodFillRemovesOuterBackgroundButKeepsEnclosedWhite() {
        var img = outlinedSquare()
        XCTAssertTrue(BackgroundRemover.floodFillBackground(&img))
        XCTAssertEqual(img.alpha(0, 0), 0)          // 바깥 배경 → 투명
        XCTAssertEqual(img.alpha(1, 5), 0)
        XCTAssertEqual(img.alpha(2, 2), 255)        // 외곽선 유지
        XCTAssertEqual(img.alpha(5, 5), 255)        // 외곽선 안쪽 흰색 유지
        XCTAssertEqual(BackgroundRemover.alphaBounds(img), CGRect(x: 2, y: 2, width: 8, height: 8))
    }

    func testFloodFillToleratesJPEGNoise() {
        var img = outlinedSquare()
        img.data[(0 * 12 + 5) * 4] = 240 // 배경 픽셀 살짝 다른 색
        XCTAssertTrue(BackgroundRemover.floodFillBackground(&img))
        XCTAssertEqual(img.alpha(5, 0), 0)
    }

    func testNonUniformBorderIsNotFlooded() {
        var img = outlinedSquare()
        for x in 0..<12 { let i = x * 4; img.data[i] = 0; img.data[i + 1] = 0; img.data[i + 2] = 0 } // 윗줄 검정
        for y in 0..<12 { let i = (y * 12) * 4; img.data[i] = 0; img.data[i + 1] = 0; img.data[i + 2] = 0 } // 왼줄 검정
        let before = img
        XCTAssertFalse(BackgroundRemover.floodFillBackground(&img))
        XCTAssertEqual(img, before)
    }

    func testTransparentBorderDetection() {
        var img = outlinedSquare()
        XCTAssertFalse(BackgroundRemover.hasTransparentBorder(img))
        img.data[3] = 0
        XCTAssertTrue(BackgroundRemover.hasTransparentBorder(img))
    }

    func testCutoutCropsToCharacter() throws {
        let cg = outlinedSquare(w: 20, h: 30).makeImage()!
        let (cut, method) = try BackgroundRemover.cutout(cg)
        XCTAssertEqual(method, .floodFill)
        XCTAssertEqual(cut.width, 16)
        XCTAssertEqual(cut.height, 26)
    }

    /// 40x40: 검은 모서리 + 원형 빛번짐(연한 흰/연두) + 노란 반짝이 + 가운데 진한 외곽선의 분홍/크림 캐릭터
    private func glowImage() -> RGBAImage {
        let n = 40
        var img = RGBAImage(width: n, height: n, data: [UInt8](repeating: 255, count: n * n * 4))
        func set(_ x: Int, _ y: Int, _ c: (UInt8, UInt8, UInt8)) {
            let i = img.offset(x, y); img.data[i] = c.0; img.data[i + 1] = c.1; img.data[i + 2] = c.2
        }
        for y in 0..<n { for x in 0..<n {
            let dx = x - 20, dy = y - 20
            if dx * dx + dy * dy > 18 * 18 { set(x, y, (0, 0, 0)) }                 // 검은 모서리
            else { set(x, y, x % 2 == 0 ? (240, 252, 230) : (252, 251, 222)) }    // 빛번짐 (자글자글)
        } }
        set(6, 20, (120, 118, 110))                         // 빛번짐 가장자리의 어두운 잡티
        set(10, 10, (255, 240, 120)); set(11, 10, (255, 240, 120)) // 노란 반짝이
        for y in 14...25 { for x in 14...25 {
            let edge = x == 14 || y == 14 || x == 25 || y == 25
            set(x, y, edge ? (60, 40, 30) : (y < 19 ? (255, 228, 212) : (245, 110, 90)))  // 외곽선 / 크림 머리 / 분홍 몸
        } }
        return img
    }

    func testPeelToOutlineRemovesGlowAndSparklesButKeepsCharacter() {
        let original = glowImage()
        var img = original
        BackgroundRemover.growBackground(&img)
        BackgroundRemover.peelToOutline(&img, original: original)
        BackgroundRemover.keepMainComponents(&img)
        XCTAssertEqual(img.alpha(20, 5), 0)        // 빛번짐
        XCTAssertEqual(img.alpha(10, 10), 0)       // 반짝이
        XCTAssertEqual(img.alpha(6, 20), 0)        // 떨어진 잡티
        XCTAssertEqual(img.alpha(14, 14), 255)     // 외곽선
        XCTAssertEqual(img.alpha(17, 16), 255)     // 크림색 머리 (빛번짐과 비슷하지만 붉은 기)
        XCTAssertEqual(img.alpha(20, 22), 255)     // 분홍 몸
        XCTAssertEqual(BackgroundRemover.alphaBounds(img), CGRect(x: 14, y: 14, width: 12, height: 12))
    }

    func testCutoutUsesGlowFillForGlowBackground() throws {
        let (cut, method) = try BackgroundRemover.cutout(glowImage().makeImage()!)
        XCTAssertEqual(method, .glowFill)
        XCTAssertEqual(cut.width, 12)
        XCTAssertEqual(cut.height, 12)
    }

    func testAllTransparentHasNoBounds() {
        let img = RGBAImage(width: 4, height: 4, data: [UInt8](repeating: 0, count: 64))
        XCTAssertNil(BackgroundRemover.alphaBounds(img))
    }
}

final class PuppetAnimatorTests: XCTestCase {
    private let g = PuppetAnimator.Geometry.make(imageSize: CGSize(width: 336, height: 568))

    func testGeometryLeavesHeadroom() {
        XCTAssertEqual(g.character.height, 72)
        XCTAssertEqual(g.canvas.height, 100)
        XCTAssertGreaterThan(g.canvas.width, g.character.width)
        XCTAssertGreaterThan(g.headTop, 0)
    }

    func testWideImageGetsWideCanvas() {
        let wide = PuppetAnimator.Geometry.make(imageSize: CGSize(width: 400, height: 100))
        XCTAssertGreaterThanOrEqual(wide.canvas.width, wide.character.width * 1.8 - 1)
    }

    func testPosesStayInsideReasonableBounds() {
        for (action, n, _) in PuppetAnimator.plan {
            for i in 0..<n {
                let p = PuppetAnimator.pose(for: action, frame: i, of: n, geometry: g)
                XCTAssertGreaterThanOrEqual(p.lift, 0, "\(action)")
                XCTAssertLessThan(p.lift, g.headTop, "\(action) jumps out of frame")
                XCTAssertLessThan(abs(p.rotation), 15, "\(action)")
                for o in p.overlays {
                    XCTAssertTrue((0...g.canvas.width).contains(o.center.x), "\(action) overlay x")
                    XCTAssertTrue((0...g.canvas.height).contains(o.center.y), "\(action) overlay y")
                }
            }
        }
    }

    func testDraggedAndFallHaveNoShadowAndDraggedSwingsFromTop() {
        XCTAssertFalse(PuppetAnimator.pose(for: .dragged, frame: 0, of: 6, geometry: g).shadow)
        XCTAssertTrue(PuppetAnimator.pose(for: .dragged, frame: 0, of: 6, geometry: g).anchorTop)
        XCTAssertFalse(PuppetAnimator.pose(for: .fall, frame: 0, of: 4, geometry: g).shadow)
        XCTAssertTrue(PuppetAnimator.pose(for: .idle, frame: 0, of: 8, geometry: g).shadow)
    }

    func testLoopIsSeamless() {
        // 마지막 프레임 다음 = 첫 프레임 (phase 1.0 == 0.0)
        let first = PuppetAnimator.pose(for: .walk, frame: 0, of: 8, geometry: g)
        let wrapped = PuppetAnimator.pose(for: .walk, frame: 8, of: 8, geometry: g)
        XCTAssertEqual(first.lift, wrapped.lift, accuracy: 0.001)
    }
}

@MainActor
final class ImageCharacterMakerTests: XCTestCase {
    func testMakeIdFromFileName() {
        XCTAssertEqual(ImageCharacterMaker.makeId(from: URL(fileURLWithPath: "/x/My Avatar!.png")), "img-my-avatar")
        XCTAssertEqual(ImageCharacterMaker.makeId(from: URL(fileURLWithPath: "/x/f4aa32.jpg")), "img-f4aa32")
        let korean = ImageCharacterMaker.makeId(from: URL(fileURLWithPath: "/x/내캐릭터.png"),
                                                now: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(korean.hasPrefix("img-19"), korean)
    }

    func testEndToEndProducesLoadablePack() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("termpet-img-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        // 흰 배경 위 검은 외곽선 캐릭터(사각형) 이미지
        var data = [UInt8](repeating: 255, count: 40 * 60 * 4)
        for y in 5..<55 { for x in 10..<30 where x == 10 || x == 29 || y == 5 || y == 54 {
            let i = (y * 40 + x) * 4; data[i] = 0; data[i + 1] = 0; data[i + 2] = 0
        } }
        let src = tmp.appendingPathComponent("hero.png")
        try SpriteSheetWriter.writePNG(RGBAImage(width: 40, height: 60, data: data).makeImage()!, to: src)

        let out = tmp.appendingPathComponent("chars")
        let result = try ImageCharacterMaker.make(from: src, name: "히어로", facing: .front, into: out)
        XCTAssertEqual(result.packId, "img-hero")
        XCTAssertEqual(result.method, .floodFill)

        let sprite = try SpriteCharacter(folder: result.folder)
        XCTAssertEqual(sprite.pack.name, "히어로")
        XCTAssertEqual(sprite.spriteFacing, "front")
        for action in PetAction.allCases {
            XCTAssertGreaterThan(sprite.animation(for: action)?.frames.count ?? 0, 1, "\(action)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.folder.appendingPathComponent("source.png").path))
    }

    func testReplaceStatesSwapsOnlyChosenSheetsAndKeepsPackSettings() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("termpet-img-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        func square(_ name: String, w: Int, h: Int) throws -> URL {
            var data = [UInt8](repeating: 255, count: w * h * 4)
            let m = h / 4 // 여백 (배경 제거가 "캐릭터를 분리했다"고 인정할 만큼)
            for y in m..<(h - m) { for x in m..<(w - m) where x == m || x == w - m - 1 || y == m || y == h - m - 1 {
                let i = (y * w + x) * 4; data[i] = 0; data[i + 1] = 0; data[i + 2] = 0
            } }
            let url = tmp.appendingPathComponent(name)
            try SpriteSheetWriter.writePNG(RGBAImage(width: w, height: h, data: data).makeImage()!, to: url)
            return url
        }
        let result = try ImageCharacterMaker.make(from: try square("hero.png", w: 40, h: 40), name: "히어로",
                                                  facing: .left, into: tmp.appendingPathComponent("chars"))
        let idle = try Data(contentsOf: result.folder.appendingPathComponent("idle.png"))
        let draggedBefore = try Data(contentsOf: result.folder.appendingPathComponent("dragged.png"))
        let before = try SpriteCharacter(folder: result.folder).pack

        // 아주 넓은 그림 → 캔버스 폭에 맞게 축소되어야 함
        try ImageCharacterMaker.replaceStates([.dragged, .fall], in: result.folder, from: try square("wide.png", w: 240, h: 80))

        let after = try SpriteCharacter(folder: result.folder)
        XCTAssertEqual(after.pack.frameWidth, before.frameWidth)
        XCTAssertEqual(after.pack.scale, before.scale)
        XCTAssertEqual(after.pack.facing, "left")
        XCTAssertEqual(try Data(contentsOf: result.folder.appendingPathComponent("idle.png")), idle)
        XCTAssertNotEqual(try Data(contentsOf: result.folder.appendingPathComponent("dragged.png")), draggedBefore)
        XCTAssertGreaterThan(after.animation(for: .fall)?.frames.count ?? 0, 1)
    }

    func testFittedShrinksWideImageIntoCanvas() {
        let g = PuppetAnimator.Geometry.make(imageSize: CGSize(width: 500, height: 100))
        let f = ImageCharacterMaker.fitted(g, canvas: CGSize(width: 150, height: 100))
        XCTAssertLessThanOrEqual(f.character.width, 150 * 0.85 + 0.001)
        XCTAssertEqual(f.character.width / f.character.height, 5, accuracy: 0.01) // 비율 유지
        XCTAssertEqual(f.canvas, CGSize(width: 150, height: 100))
    }

    func testLoadDownscaledShrinksOnlyBigImages() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("termpet-big-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tmp) }
        for (w, h, expectedMax) in [(3000, 600, 1024), (200, 100, 200)] {
            try SpriteSheetWriter.writePNG(RGBAImage(width: w, height: h, data: [UInt8](repeating: 200, count: w * h * 4)).makeImage()!, to: tmp)
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(tmp as CFURL, nil))
            let image = try XCTUnwrap(ImageCharacterMaker.loadDownscaled(source))
            XCTAssertEqual(max(image.width, image.height), expectedMax)
        }
    }

    func testUnreadableImageThrows() {
        XCTAssertThrowsError(try ImageCharacterMaker.make(from: URL(fileURLWithPath: "/nope.png"), name: "x",
                                                          facing: .right, into: FileManager.default.temporaryDirectory))
    }
}
