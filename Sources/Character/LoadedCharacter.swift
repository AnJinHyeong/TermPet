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
        case .sprite(let s): return s.libraryId
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
        /// 이 그림이 바라보는 방향 ("right"/"left"/"front")
        let facing: String
    }

    let pack: CharacterPack
    let folder: URL
    /// 캐릭터 목록에서의 id (friend.<id>)
    var libraryId: String = ""
    /// 동작별 포즈 목록 (변형 번호 순)
    private let animations: [PetAction: [Animation]]

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

        var numbered: [PetAction: [(Int, Animation)]] = [:]
        for (key, spec) in pack.states {
            guard let (action, number) = CharacterPack.parseStateKey(key) else { continue } // 모르는 상태 이름은 무시
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
            let anim = Animation(
                frames: frames,
                timing: SpriteTiming(frameCount: frames.count, fps: spec.fps ?? 8, loop: spec.loop ?? true),
                facing: spec.facing ?? pack.facing ?? "right")
            numbered[action, default: []].append((number, anim))
        }
        let animations = numbered.mapValues { $0.sorted { $0.0 < $1.0 }.map(\.1) }

        self.pack = pack
        self.folder = folder
        self.animations = animations
    }

    /// 상태별 애니메이션. 정의되지 않은 상태는 비슷한 동작 → idle 순으로 대체.
    /// `variant`: 두뇌가 상태에 들어갈 때 뽑은 난수 → 포즈가 여러 개면 그중 하나
    func animation(for action: PetAction, variant: Int = 0) -> Animation? {
        guard let list = Self.fallbacks(for: action).lazy.compactMap({ self.animations[$0] }).first,
              !list.isEmpty else { return nil }
        return list[abs(variant) % list.count]
    }

    /// 이 동작의 포즈 개수 (대체 동작 포함)
    func variantCount(for action: PetAction) -> Int {
        Self.fallbacks(for: action).lazy.compactMap { self.animations[$0]?.count }.first ?? 0
    }

    /// 없는 동작을 무엇으로 대신할지 (벽 오르기 그림이 없으면 잡힌 그림 → 가만히, 물기 → 화남)
    static func fallbacks(for action: PetAction) -> [PetAction] {
        switch action {
        case .climb: return [.climb, .dragged, .idle]
        case .bite: return [.bite, .angry, .idle]      // 물기 그림이 없으면 화난 얼굴
        case .idle: return [.idle]
        default: return [action, .idle]
        }
    }

    func frame(for action: PetAction, variant: Int = 0, elapsed: TimeInterval) -> CGImage? {
        guard let anim = animation(for: action, variant: variant), !anim.frames.isEmpty else { return nil }
        return anim.frames[anim.timing.frameIndex(at: elapsed)]
    }

    /// 스프라이트 그림이 바라보는 방향: "right"(기본) / "left" / "front"(좌우 반전 안 함)
    var spriteFacing: String { pack.facing ?? "right" }
    var pixelArt: Bool { pack.pixelArt ?? false }
}
