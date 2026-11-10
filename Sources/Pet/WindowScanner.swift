import AppKit
import CoreGraphics

/// 지금 화면에 보이는 다른 앱 창들의 위치를 읽는다 (펫이 올라서고 기어오를 지형).
/// `CGWindowListCopyWindowInfo`는 창 위치·크기만 읽을 땐 화면 기록 권한이 필요 없다.
/// (창 제목은 권한이 필요하지만 쓰지 않는다)
enum WindowScanner {
    /// 앞 → 뒤 순서의 창 목록 (AppKit 좌표)
    static func scan() -> [WindowBox] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return boxes(from: infos, ownPID: ProcessInfo.processInfo.processIdentifier, primaryHeight: primaryHeight)
    }

    /// 창 정보 사전 → WindowBox (순수 함수, 테스트용으로 분리)
    /// - 일반 앱 창 층(layer 0)만, 투명/아주 작은 창·내 앱 창은 제외
    /// - CG 좌표(주 화면 좌상단 원점, y 아래로) → AppKit 좌표(좌하단 원점, y 위로)
    static func boxes(from infos: [[String: Any]], ownPID: Int32, primaryHeight: CGFloat) -> [WindowBox] {
        infos.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32).map({ $0 != ownPID }) ?? true,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let id = info[kCGWindowNumber as String] as? Int,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cg = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  cg.width >= 120, cg.height >= 60 else { return nil }
            let frame = CGRect(x: cg.minX, y: primaryHeight - cg.maxY, width: cg.width, height: cg.height)
            return WindowBox(id: id, frame: frame)
        }
    }
}

extension WindowScanner {
    /// 아래 Dock 폭(pt). 접근성 권한이 있으면 실제 값, 없으면 Dock 설정으로 추정.
    static func dockWidth() -> CGFloat? {
        if AXIsProcessTrusted(), let w = axDockWidth() { return w }
        guard let dock = UserDefaults(suiteName: "com.apple.dock") else { return nil }
        let tile = CGFloat(dock.object(forKey: "tilesize") as? Double ?? 48)
        let apps = (dock.array(forKey: "persistent-apps") as? [[String: Any]]) ?? []
        let others = (dock.array(forKey: "persistent-others") as? [[String: Any]]) ?? []
        let pinned = Set(apps.compactMap { ($0["tile-data"] as? [String: Any])?["bundle-identifier"] as? String })
        // 고정 안 된 실행 중 앱도 Dock에 뜬다 (최근 앱 영역)
        let extra = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !pinned.contains($0.bundleIdentifier ?? "")
        }.count
        // 최근 사용 앱 칸(실행 중이 아닌 것, 최대 3개)과 그 앞 구분선
        let showsRecents = dock.object(forKey: "show-recents") as? Bool ?? true
        let recents = showsRecents ? min(3, (dock.array(forKey: "recent-apps") ?? []).count) : 0
        let items = apps.count + extra + recents + others.count + 1 // +1 휴지통
        let separators = 1 + (recents > 0 ? 1 : 0)
        return ScreenFloor.estimatedDockWidth(tileSize: tile, items: items, separators: separators)
    }

    /// 손쉬운 사용 권한이 있는지 (있으면 Dock 폭을 정확히 읽는다)
    static var canReadDockExactly: Bool { AXIsProcessTrusted() }

    /// 손쉬운 사용 권한 요청 (시스템 대화상자 + 설정 화면). 메뉴 버튼을 눌렀을 때만 호출한다.
    static func requestDockAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        if !AXIsProcessTrustedWithOptions([key: true] as CFDictionary),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Dock 앱의 접근성 트리에서 아이콘 목록(AXList) 폭을 읽는다
    private static func axDockWidth() -> CGFloat? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXChildrenAttribute as CFString, &children) == .success,
              let list = (children as? [AXUIElement])?.first else { return nil }
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(list, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let value = sizeRef, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        AXValueGetValue(value as! AXValue, .cgSize, &size)
        return size.width > 0 ? size.width : nil
    }
}
