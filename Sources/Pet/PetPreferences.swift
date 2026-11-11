import CoreGraphics
import Foundation

/// 메뉴 패널 "설정" 탭의 값들 (펫 크기·걷기 속도·말풍선 유지 시간). UserDefaults에 저장.
/// 순수 값 타입 + 범위 보정만 담당 → 테스트 가능. 화면 반영은 PetController가 한다.
struct PetPreferences: Equatable {
    static let sizeRange: ClosedRange<Double> = 0.6...1.6
    static let speedRange: ClosedRange<Double> = 0.5...2.0
    static let bubbleRange: ClosedRange<Double> = 2...10

    /// 캐릭터 크기 배율 (1 = 원래 크기)
    var sizeScale: Double = 1 { didSet { sizeScale = Self.clamp(sizeScale, Self.sizeRange) } }
    /// 걷기 속도 배율
    var speedScale: Double = 1 { didSet { speedScale = Self.clamp(speedScale, Self.speedRange) } }
    /// 말풍선이 떠 있는 시간(초)
    var bubbleSeconds: Double = 3 { didSet { bubbleSeconds = Self.clamp(bubbleSeconds, Self.bubbleRange) } }

    static func clamp(_ v: Double, _ range: ClosedRange<Double>) -> Double {
        v.isFinite ? min(max(v, range.lowerBound), range.upperBound) : range.lowerBound
    }

    /// 캐릭터 원래 크기 × 배율 (반올림, 최소 24pt)
    func scaled(_ size: CGSize) -> CGSize {
        CGSize(width: max(24, (size.width * sizeScale).rounded()), height: max(24, (size.height * sizeScale).rounded()))
    }

    // MARK: - 저장 (UserDefaults ≈ localStorage)

    private static let sizeKey = "pref.sizeScale", speedKey = "pref.speedScale", bubbleKey = "pref.bubbleSeconds"

    static func load(_ defaults: UserDefaults = .standard) -> PetPreferences {
        var p = PetPreferences()
        if let v = defaults.object(forKey: sizeKey) as? Double { p.sizeScale = v }
        if let v = defaults.object(forKey: speedKey) as? Double { p.speedScale = v }
        if let v = defaults.object(forKey: bubbleKey) as? Double { p.bubbleSeconds = v }
        return p
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(sizeScale, forKey: Self.sizeKey)
        defaults.set(speedScale, forKey: Self.speedKey)
        defaults.set(bubbleSeconds, forKey: Self.bubbleKey)
    }
}
