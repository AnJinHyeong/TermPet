import AppKit

/// 펫이 어느 "층"에 보일지.
/// macOS 창은 level(층) 값이 클수록 위에 그려진다 — CSS의 z-index와 같은 개념.
enum PetWindowLayer: String, CaseIterable, Identifiable {
    /// 모든 앱 창 위에 항상 보임 (전체화면 앱 위 포함)
    case aboveApps
    /// 바탕화면 아이콘 바로 위, 일반 앱 창 아래 → 창이 없는 바탕화면에서만 보임 (알림이 와도 그대로)
    case desktop
    /// 평소엔 바탕화면에만, 알림(말풍선)이 떠 있는 동안만 앱 창 위로 올라왔다가 다시 숨음
    case desktopPopUp

    static let defaultsKey = "petWindowLayer"
    static let `default`: PetWindowLayer = .aboveApps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aboveApps: return "프로그램 위에 표시"
        case .desktop: return "바탕화면에만 표시"
        case .desktopPopUp: return "바탕화면에만 + 알림 시 앞으로"
        }
    }

    /// 메뉴 패널 타일용 짧은 이름
    var shortTitle: String {
        switch self {
        case .aboveApps: return "항상 위"
        case .desktop: return "바탕화면"
        case .desktopPopUp: return "알림 때만 위"
        }
    }

    /// SF Symbol 이름 (Apple 기본 아이콘 세트 — 웹의 아이콘 폰트 같은 것)
    var symbol: String {
        switch self {
        case .aboveApps: return "macwindow.on.rectangle"
        case .desktop: return "menubar.dock.rectangle"
        case .desktopPopUp: return "bell.badge.fill"
        }
    }

    var windowLevel: NSWindow.Level {
        switch self {
        case .aboveApps:
            return .floating
        case .desktop, .desktopPopUp:
            // 바탕화면 아이콘 층 + 1 → 아이콘보다는 위, 일반 창(.normal)보다는 아래
            return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        }
    }

    /// 설정값 + 말풍선 표시 여부 → 실제 창에 적용할 층 (순수 함수)
    static func effective(_ setting: PetWindowLayer, bubbleShowing: Bool) -> PetWindowLayer {
        bubbleShowing && setting.raisesForNotifications ? .aboveApps : setting
    }

    /// 알림(말풍선)이 떠 있는 동안 앱 창 위로 올라오는지
    var raisesForNotifications: Bool { self == .desktopPopUp }

    /// UserDefaults(≈ localStorage)에서 저장된 값 읽기
    static func load(from defaults: UserDefaults = .standard) -> PetWindowLayer {
        defaults.string(forKey: defaultsKey).flatMap(PetWindowLayer.init(rawValue:)) ?? .default
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
