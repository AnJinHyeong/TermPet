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
