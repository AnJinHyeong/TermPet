import CoreGraphics
import Foundation
import ImageIO

/// 화면에 그릴 준비가 끝난 캐릭터.
/// enum에 값을 붙이는 형태 ≈ TS 판별 유니온 `{ kind: 'builtIn', style } | { kind: 'sprite', sprite }`
enum LoadedCharacter {
    case builtIn(BuiltInStyle)
    case sprite(SpriteCharacter)

    static let defaultSize = CGSize(width: 80, height: 80)

    var id: String {
        switch self {
        case .builtIn(let style): return style.id
        case .sprite(let s): return CharacterLibrary.packEntryId(s.pack.id)
        }
    }

    var size: CGSize {
        switch self {
        case .builtIn: return Self.defaultSize
        case .sprite(let s): return s.pack.displaySize
        }
    }

    var walkSpeed: CGFloat? {
        switch self {
        case .builtIn: return nil
        case .sprite(let s): return s.pack.walkSpeed.map { CGFloat($0) }
        }
    }

    var messages: BubbleMessages {
        switch self {
        case .builtIn: return .default
        case .sprite(let s): return s.pack.bubbleMessages
        }
    }
}

/// 스프라이트 시트를 프레임 단위로 잘라 메모리에 올린 캐릭터.
/// `final class`(참조 타입)로 둔 이유: 이미지 배열을 매 프레임 복사하지 않도록.
final class SpriteCharacter {
    struct Animation {
        let frames: [CGImage]
        let timing: SpriteTiming
    }

    let pack: CharacterPack
    let folder: URL
    private let animations: [PetAction: Animation]

    enum LoadError: Error, CustomStringConvertible {
        case missingJSON
        case invalidJSON(String)
        case imageNotFound(String)
        case imageTooSmall(String)

        var description: String {
            switch self {
            case .missingJSON: return "character.json 없음"
            case .invalidJSON(let m): return "character.json 오류: \(m)"
            case .imageNotFound(let f): return "이미지를 읽을 수 없음: \(f)"
            case .imageTooSmall(let f): return "이미지가 프레임 크기보다 작음: \(f)"
            }
        }
    }

    init(folder: URL) throws {
        let jsonURL = folder.appendingPathComponent("character.json")
        guard let data = try? Data(contentsOf: jsonURL) else { throw LoadError.missingJSON }
        let pack: CharacterPack
        do {
            pack = try CharacterPack.decode(data)
        } catch let e as CharacterPack.ValidationError {
            throw LoadError.invalidJSON(e.description)
        } catch {
            throw LoadError.invalidJSON("\(error)")
        }

        var animations: [PetAction: Animation] = [:]
        for (key, spec) in pack.states {
            guard let action = PetAction(rawValue: key) else { continue } // 모르는 상태 이름은 무시
            let url = folder.appendingPathComponent(spec.file)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw LoadError.imageNotFound(spec.file)
            }
            let available = sheet.width / pack.frameWidth
            guard available >= 1, sheet.height >= pack.frameHeight else {
                throw LoadError.imageTooSmall(spec.file)
            }
            let count = min(spec.frames ?? available, available)
            let frames: [CGImage] = (0..<max(count, 1)).compactMap { i in
                sheet.cropping(to: CGRect(x: i * pack.frameWidth, y: 0,
                                          width: pack.frameWidth, height: pack.frameHeight))
            }
            animations[action] = Animation(
                frames: frames,
                timing: SpriteTiming(frameCount: frames.count, fps: spec.fps ?? 8, loop: spec.loop ?? true))
        }

        self.pack = pack
        self.folder = folder
        self.animations = animations
    }

    /// 상태별 애니메이션. 정의되지 않은 상태는 idle로 대체.
    func animation(for action: PetAction) -> Animation? {
        animations[action] ?? animations[.idle]
    }

    func frame(for action: PetAction, elapsed: TimeInterval) -> CGImage? {
        guard let anim = animation(for: action), !anim.frames.isEmpty else { return nil }
        return anim.frames[anim.timing.frameIndex(at: elapsed)]
    }

    /// 스프라이트 그림이 바라보는 방향: "right"(기본) / "left" / "front"(좌우 반전 안 함)
    var spriteFacing: String { pack.facing ?? "right" }
    var pixelArt: Bool { pack.pixelArt ?? false }
}
