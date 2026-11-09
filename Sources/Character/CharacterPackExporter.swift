import AppKit
import SwiftUI

/// 기본 캐릭터를 스프라이트 시트 PNG + character.json 으로 내보낸다.
/// 용도: (1) 커스텀 팩 형식의 견본(템플릿) 제공, (2) 스프라이트 렌더링 경로 확인.
@MainActor
enum CharacterPackExporter {
    /// 상태별 (프레임 수, fps)
    private static let plan: [(PetAction, Int, Double)] = [
        (.idle, 8, 6), (.walk, 8, 12), (.talk, 6, 10), (.happy, 8, 12),
        (.angry, 6, 12), (.ask, 8, 10), (.sleep, 8, 4), (.dragged, 6, 10), (.fall, 4, 10),
    ]

    /// `directory/<style>-sprite/` 에 팩을 만들고 그 폴더 URL을 반환
    static func export(_ style: BuiltInStyle, to directory: URL) throws -> URL {
        let packId = "\(style.rawValue)-sprite"
        let folder = directory.appendingPathComponent(packId, isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.path) { try fm.removeItem(at: folder) }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        let renderScale: CGFloat = 2 // 레티나용으로 2배 해상도 → character.json scale 0.5
        let base = LoadedCharacter.defaultSize
        let fw = Int(base.width * renderScale), fh = Int(base.height * renderScale)

        var states: [String: CharacterPack.StateSpec] = [:]
        for (action, count, fps) in plan {
            let frames: [CGImage] = (0..<count).compactMap { i in
                let t = Double(i) / fps
                // 전역 시계는 1초부터 시작 → 0초(눈 깜빡임 순간)가 첫 프레임에 걸리지 않게
                let view = DefaultCharacterView(style: style, action: action, facing: .right, time: 1 + t, actionTime: t)
                    .frame(width: base.width, height: base.height)
                // ImageRenderer ≈ html2canvas: SwiftUI 뷰를 이미지로 렌더링
                let renderer = ImageRenderer(content: view)
                renderer.scale = renderScale
                return renderer.cgImage
            }
            let file = "\(action.rawValue).png"
            try SpriteSheetWriter.writeSheet(frames, frameWidth: fw, frameHeight: fh, to: folder.appendingPathComponent(file))
            states[action.rawValue] = .init(file: file, frames: frames.count, fps: fps, loop: true)
        }

        let pack = CharacterPack(id: packId, name: "\(style.name) (스프라이트)", frameWidth: fw, frameHeight: fh,
                                 scale: Double(1 / renderScale), walkSpeed: 40, pixelArt: false, facing: "right",
                                 states: states,
                                 messages: .init(done: ["\(style.name): 끝났어!"], error: ["\(style.name): 에러 났어…"],
                                                 ask: ["\(style.name): 확인해줘!"]))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(pack).write(to: folder.appendingPathComponent("character.json"))
        return folder
    }
}
