import SwiftUI

/// 앱 진입점.
/// React 비유: `@main` ≈ `ReactDOM.createRoot(...).render(<App />)` — 여기서 앱이 시작된다.
/// `App` 프로토콜의 `body`는 컴포넌트의 JSX처럼 "어떤 창/씬을 띄울지"를 선언한다.
@main
struct TermPetApp: App {
    // AppKit 쪽 생명주기(펫 창 생성 등)는 AppDelegate가 담당. Phase 1부터 사용.
    // React 비유: useEffect(() => {...}, []) 로 마운트 시 초기화하는 곳.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // MenuBarExtra: 메뉴바(화면 우상단)에 아이콘 + 드롭다운 메뉴를 만든다.
        // LSUIElement=YES 이므로 Dock 아이콘 없이 이것만 보인다.
        MenuBarExtra("TermPet", systemImage: "pawprint.fill") {
            MenuBarContent()
        }
    }
}

/// 메뉴바 드롭다운 내용. Phase 3에서 확장 예정.
struct MenuBarContent: View {
    var body: some View {
        Text("TermPet \(AppInfo.version)")
        Divider()
        Button("종료") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
