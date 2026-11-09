import AppKit

/// AppKit 생명주기 훅. SwiftUI만으로 어려운 창(NSPanel) 관리를 여기서 한다.
/// React 비유: 최상위 컴포넌트의 마운트/언마운트 effect.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Phase 1: PetController 생성 및 펫 창 표시 예정.
    }
}
