import AppKit

/// 펫이 어느 "층"에 보일지.
/// macOS 창은 level(층) 값이 클수록 위에 그려진다 — CSS의 z-index와 같은 개념.
enum PetWindowLayer: String, CaseIterable, Identifiable {
    /// 모든 앱 창 위에 항상 보임 (전체화면 앱 위 포함)
    case aboveApps
    /// 바탕화면 아이콘 바로 위, 일반 앱 창 아래 → 창이 없는 바탕화면에서만 보임
    case desktop

    static let defaultsKey = "petWindowLayer"
    static let `default`: PetWindowLayer = .aboveApps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aboveApps: return "프로그램 위에 표시"
        case .desktop: return "바탕화면에만 표시"
        }
    }

    var windowLevel: NSWindow.Level {
        switch self {
        case .aboveApps:
            return .floating
        case .desktop:
            // 바탕화면 아이콘 층 + 1 → 아이콘보다는 위, 일반 창(.normal)보다는 아래
            return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        }
    }

    /// UserDefaults(≈ localStorage)에서 저장된 값 읽기
    static func load(from defaults: UserDefaults = .standard) -> PetWindowLayer {
        defaults.string(forKey: defaultsKey).flatMap(PetWindowLayer.init(rawValue:)) ?? .default
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
