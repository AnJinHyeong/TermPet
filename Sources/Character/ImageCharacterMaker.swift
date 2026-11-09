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
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
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
