import SwiftUI

/// 앱 진입점.
/// React 비유: `@main` ≈ `ReactDOM.createRoot(...).render(<App />)` — 여기서 앱이 시작된다.
/// `App` 프로토콜의 `body`는 컴포넌트의 JSX처럼 "어떤 창/씬을 띄울지"를 선언한다.
@main
struct TermPetApp: App {
    // AppKit 쪽 생명주기(펫 창 생성 등)는 AppDelegate가 담당.
    // React 비유: useEffect(() => {...}, []) 로 마운트 시 초기화하는 곳.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // MenuBarExtra: 메뉴바(화면 우상단)에 아이콘 + 패널을 만든다.
        // `.window` 스타일 = 일반 메뉴 대신 SwiftUI 화면을 그대로 띄우는 팝오버 패널.
        // LSUIElement=YES 이므로 Dock 아이콘 없이 이것만 보인다.
        MenuBarExtra {
            MenuPanelView(app: appDelegate)
        } label: {
            Image("MenuBarIcon") // 템플릿 이미지 → 메뉴바 밝기(라이트/다크)에 맞춰 자동으로 색이 바뀜
        }
        .menuBarExtraStyle(.window)
    }
}
