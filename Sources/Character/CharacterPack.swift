import Foundation

/// `character.json` 모델 (SPEC 3-4).
/// `Codable` ≈ zod 스키마: JSON ↔ 구조체 자동 변환. `?` 필드는 없어도 디코딩 성공.
struct CharacterPack: Codable, Equatable {
    struct StateSpec: Codable, Equatable {
        var file: String
        /// 생략하면 이미지 너비 / frameWidth
        var frames: Int?
        var fps: Double?
        var loop: Bool?
        /// 이 동작 그림만 바라보는 방향이 다를 때 ("right"/"left"/"front"). 없으면 팩 전체 facing
        var facing: String?
    }

    struct Messages: Codable, Equatable {
        var done: [String]?
        var error: [String]?
        var ask: [String]?
    }

    var id: String
    var name: String?
    var frameWidth: Int
    var frameHeight: Int
    var scale: Double?
    var walkSpeed: Double?
    var pixelArt: Bool?
    /// 스프라이트가 바라보는 방향 ("right" 기본, "left", "front" = 좌우 반전 안 함)
    var facing: String?
    /// 상태별 그림. 키는 동작 이름(`idle`), 같은 동작의 다른 포즈는 `idle.2`, `idle.3` …
    /// (상태에 들어갈 때마다 하나를 골라 보여준다 → 같은 걷기라도 가끔 다른 모습)
    var states: [String: StateSpec]
    var messages: Messages?
    /// 캐릭터 목록 순서 (작을수록 앞)
    var order: Int?

    /// 상태 키 → (동작, 변형 번호). `idle` → (.idle, 1), `walk.2` → (.walk, 2). 모르는 이름은 nil
    static func parseStateKey(_ key: String) -> (PetAction, Int)? {
        let parts = key.split(separator: ".", maxSplits: 1).map(String.init)
        guard let action = PetAction(rawValue: parts[0]) else { return nil }
        guard parts.count == 2 else { return (action, 1) }
        guard let n = Int(parts[1]), n >= 1 else { return nil }
        return (action, n)
    }

    enum ValidationError: Error, Equatable, CustomStringConvertible {
        case invalidId
        case invalidFrameSize
        case invalidScale
        case missingIdleState
        case unsafeFilePath(String)

        var description: String {
            switch self {
            case .invalidId: return "id는 영문/숫자/-/_ 만 사용 가능 (1~64자)"
            case .invalidFrameSize: return "frameWidth/frameHeight는 1~1024"
            case .invalidScale: return "scale은 0.1~8"
            case .missingIdleState: return "states에 idle이 꼭 있어야 함"
            case .unsafeFilePath(let f): return "파일 경로가 팩 폴더 밖을 가리킴: \(f)"
            }
        }
    }

    var effectiveScale: Double { scale ?? 1 }

    /// 펫 창 크기 (pt). 너무 크면 512pt 이내로 축소.
    var displaySize: CGSize {
        let w = Double(frameWidth) * effectiveScale, h = Double(frameHeight) * effectiveScale
        let shrink = min(1, 512 / max(w, h))
        return CGSize(width: (w * shrink).rounded(), height: (h * shrink).rounded())
    }

    var bubbleMessages: BubbleMessages {
        let d = BubbleMessages.default
        func pick(_ list: [String]?, _ fallback: [String]) -> [String] {
            let cleaned = (list ?? []).filter { !$0.isEmpty }
            return cleaned.isEmpty ? fallback : cleaned
        }
        return BubbleMessages(done: pick(messages?.done, d.done),
                              error: pick(messages?.error, d.error),
                              ask: pick(messages?.ask, d.ask))
    }

    func validate() throws {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard (1...64).contains(id.count), id.unicodeScalars.allSatisfy({ allowed.contains($0) && $0.isASCII }) else {
            throw ValidationError.invalidId
        }
        guard (1...1024).contains(frameWidth), (1...1024).contains(frameHeight) else {
            throw ValidationError.invalidFrameSize
        }
        if let scale, !(0.1...8).contains(scale) { throw ValidationError.invalidScale }
        guard states["idle"] != nil else { throw ValidationError.missingIdleState }
        for spec in states.values where spec.file.contains("..") || spec.file.hasPrefix("/") {
            throw ValidationError.unsafeFilePath(spec.file)
        }
    }

    static func decode(_ data: Data) throws -> CharacterPack {
        let pack = try JSONDecoder().decode(CharacterPack.self, from: data)
        try pack.validate()
        return pack
    }
}

/// 한 상태의 애니메이션 타이밍 계산 (순수 로직)
struct SpriteTiming: Equatable {
    var frameCount: Int
    var fps: Double
    var loop: Bool

    /// 상태 진입 후 `elapsed`초일 때 보여줄 프레임 번호
    func frameIndex(at elapsed: TimeInterval) -> Int {
        guard frameCount > 1, fps > 0, elapsed > 0 else { return 0 }
        let raw = Int(elapsed * fps)
        return loop ? raw % frameCount : min(raw, frameCount - 1)
    }
}
