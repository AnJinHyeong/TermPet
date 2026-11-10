import AppKit
import ImageIO
import SwiftUI

/// 그림 한 장 → 캐릭터 팩 (배경 제거 → 상태별 움직임을 입혀 스프라이트 시트로 렌더링)
@MainActor
enum ImageCharacterMaker {
    enum Facing: String, CaseIterable {
        case right, left, front

        var title: String {
            switch self {
            case .right: return "오른쪽"
            case .left: return "왼쪽"
            case .front: return "정면 (좌우 반전 안 함)"
            }
        }
    }

    struct Result {
        let folder: URL
        let packId: String
        let method: BackgroundRemover.Method
    }

    static let renderScale: CGFloat = 2

    /// - Parameters:
    ///   - imageURL: PNG/JPG/HEIC 등
    ///   - name: 메뉴에 보일 이름
    ///   - facing: 그림 속 캐릭터가 바라보는 방향
    ///   - directory: 캐릭터 폴더 (보통 CharacterLibrary.directory)
    static func make(from imageURL: URL, name: String, facing: Facing, into directory: URL) throws -> Result {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = loadDownscaled(source) else {
            throw BackgroundRemover.Failure.unreadableImage
        }
        let (cutout, method) = try BackgroundRemover.cutout(image)

        let packId = makeId(from: imageURL)
        let folder = directory.appendingPathComponent(packId, isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.path) { try fm.removeItem(at: folder) }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try SpriteSheetWriter.writePNG(cutout, to: folder.appendingPathComponent("source.png")) // 배경 지운 원본 (참고용)

        let geometry = PuppetAnimator.Geometry.make(
            imageSize: CGSize(width: cutout.width, height: cutout.height))
        let fw = Int(geometry.canvas.width * renderScale), fh = Int(geometry.canvas.height * renderScale)

        var states: [String: CharacterPack.StateSpec] = [:]
        for (action, count, fps) in PuppetAnimator.plan {
            let frames: [CGImage] = (0..<count).compactMap { i in
                let pose = PuppetAnimator.pose(for: action, frame: i, of: count, geometry: geometry)
                let renderer = ImageRenderer(content: PuppetFrameView(image: cutout, geometry: geometry, pose: pose))
                renderer.scale = renderScale
                return renderer.cgImage
            }
            let file = "\(action.rawValue).png"
            try SpriteSheetWriter.writeSheet(frames, frameWidth: fw, frameHeight: fh, to: folder.appendingPathComponent(file))
            states[action.rawValue] = .init(file: file, frames: frames.count, fps: fps, loop: true)
        }

        let pack = CharacterPack(id: packId, name: name, frameWidth: fw, frameHeight: fh,
                                 scale: Double(1 / renderScale), walkSpeed: 35, pixelArt: false,
                                 facing: facing.rawValue, states: states, messages: nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(pack).write(to: folder.appendingPathComponent("character.json"))
        return Result(folder: folder, packId: packId, method: method)
    }

    /// 기존 팩의 일부 상태(예: 잡혔을 때·떨어질 때)만 다른 그림으로 바꾼다.
    /// 프레임 크기·scale 등 팩 설정은 그대로 두고 해당 상태 시트만 다시 렌더링.
    /// (React 비유: 같은 컴포넌트에서 특정 state일 때만 다른 이미지 prop을 넘기는 것)
    @discardableResult
    static func replaceStates(_ actions: [PetAction], in folder: URL, from imageURL: URL,
                              alreadyCutOut: Bool = false) throws -> BackgroundRemover.Method {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = loadDownscaled(source) else {
            throw BackgroundRemover.Failure.unreadableImage
        }
        // 이미 배경을 지운 원본(source.png)이면 다시 지우지 않는다
        let (cutout, method) = alreadyCutOut ? (image, .alreadyTransparent) : try BackgroundRemover.cutout(image)
        let jsonURL = folder.appendingPathComponent("character.json")
        var pack = try JSONDecoder().decode(CharacterPack.self, from: Data(contentsOf: jsonURL))

        let base = PuppetAnimator.Geometry.make(imageSize: CGSize(width: cutout.width, height: cutout.height))
        let geometry = fitted(base, canvas: CGSize(width: CGFloat(pack.frameWidth) / renderScale,
                                                   height: CGFloat(pack.frameHeight) / renderScale))
        for action in actions {
            guard let (_, count, fps) = PuppetAnimator.plan.first(where: { $0.0 == action }) else { continue }
            let frames: [CGImage] = (0..<count).compactMap { i in
                let pose = PuppetAnimator.pose(for: action, frame: i, of: count, geometry: geometry)
                let renderer = ImageRenderer(content: PuppetFrameView(image: cutout, geometry: geometry, pose: pose))
                renderer.scale = renderScale
                return renderer.cgImage
            }
            let file = "\(action.rawValue).png"
            try SpriteSheetWriter.writeSheet(frames, frameWidth: pack.frameWidth, frameHeight: pack.frameHeight,
                                             to: folder.appendingPathComponent(file))
            pack.states[action.rawValue] = .init(file: file, frames: frames.count, fps: fps, loop: true)
        }
        if !alreadyCutOut {
            try SpriteSheetWriter.writePNG(cutout, to: folder.appendingPathComponent("source-\(actions.map(\.rawValue).joined(separator: "-")).png"))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(pack).write(to: jsonURL)
        return method
    }

    /// 한 동작을 그림 여러 장으로 만든다 (진짜 프레임 애니메이션). 파일 이름 순서대로 재생.
    /// 한 장이면 기존처럼 그 그림을 인형극 방식으로 움직인다.
    /// 모든 프레임에 같은 축척을 써서 크기가 들쭉날쭉하지 않게, 발(아래)을 맞춰 가운데 정렬한다.
    static func replaceStateFrames(_ action: PetAction, in folder: URL, from imageURLs: [URL]) throws {
        guard imageURLs.count >= 2 else {
            guard let only = imageURLs.first else { return }
            try replaceStates([action], in: folder, from: only)
            return
        }
        let sorted = imageURLs
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(maxFrames)
        let cutouts: [CGImage] = try sorted.map { url in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = loadDownscaled(source) else {
                throw BackgroundRemover.Failure.unreadableImage
            }
            return try BackgroundRemover.cutout(image).0
        }

        let jsonURL = folder.appendingPathComponent("character.json")
        var pack = try JSONDecoder().decode(CharacterPack.self, from: Data(contentsOf: jsonURL))
        let canvas = CGSize(width: CGFloat(pack.frameWidth) / renderScale, height: CGFloat(pack.frameHeight) / renderScale)
        let maxW = CGFloat(cutouts.map(\.width).max() ?? 1), maxH = CGFloat(cutouts.map(\.height).max() ?? 1)
        let fit = fitted(PuppetAnimator.Geometry.make(imageSize: CGSize(width: maxW, height: maxH)), canvas: canvas)
        let scale = fit.character.height / maxH

        let frames: [CGImage] = cutouts.compactMap { cutout in
            let g = PuppetAnimator.Geometry(canvas: canvas,
                                            character: CGSize(width: CGFloat(cutout.width) * scale,
                                                              height: CGFloat(cutout.height) * scale),
                                            bottomMargin: fit.bottomMargin)
            let renderer = ImageRenderer(content: PuppetFrameView(image: cutout, geometry: g, pose: PuppetPose()))
            renderer.scale = renderScale
            return renderer.cgImage
        }
        let file = "\(action.rawValue).png"
        try SpriteSheetWriter.writeSheet(frames, frameWidth: pack.frameWidth, frameHeight: pack.frameHeight,
                                         to: folder.appendingPathComponent(file))
        pack.states[action.rawValue] = .init(file: file, frames: frames.count, fps: frameFPS(for: action), loop: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(pack).write(to: jsonURL)
    }

    static let maxFrames = 24

    /// 여러 장 애니메이션의 기본 속도 (초당 장 수)
    static func frameFPS(for action: PetAction) -> Double {
        switch action {
        case .walk, .fall, .happy, .angry, .climb: return 8
        case .idle, .talk, .ask, .dragged: return 5
        case .sleep: return 2
        }
    }

    /// 모든 동작을 처음 만든 그림(source.png) 기준 기본 움직임으로 되돌린다
    static func resetAllStates(in folder: URL) throws {
        let source = folder.appendingPathComponent("source.png")
        try replaceStates(PuppetAnimator.plan.map(\.0), in: folder, from: source, alreadyCutOut: true)
    }

    /// 다른 그림을 기존 캔버스에 넣을 때: 높이는 원래 기준(72pt) 유지, 너무 넓으면 캔버스 85% 폭에 맞춰 축소
    static func fitted(_ g: PuppetAnimator.Geometry, canvas: CGSize) -> PuppetAnimator.Geometry {
        let shrink = min(1, canvas.width * 0.85 / max(g.character.width, 1),
                         (canvas.height - (canvas.height * 0.04).rounded()) * 0.9 / max(g.character.height, 1))
        return PuppetAnimator.Geometry(canvas: canvas,
                                       character: CGSize(width: g.character.width * shrink, height: g.character.height * shrink),
                                       bottomMargin: (canvas.height * 0.04).rounded())
    }

    /// 큰 사진도 긴 변 1024px로 줄여서 읽는다 (펫은 화면에 100px 남짓이라 충분, 48MP 사진의 수백 MB 버퍼 방지)
    static func loadDownscaled(_ source: CGImageSource, maxPixelSize: Int = 1024) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary)
    }

    /// 파일 이름 기반 id (영문/숫자만). 쓸 수 있는 글자가 없으면 시간 기반.
    static func makeId(from url: URL, now: Date = Date()) -> String {
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        let cleaned = String(stem.unicodeScalars.map { scalar -> Character in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_")
                ? Character(scalar) : "-"
        })
        .split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        if !cleaned.isEmpty { return "img-" + String(cleaned.prefix(40)) }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return "img-" + f.string(from: now)
    }
}
