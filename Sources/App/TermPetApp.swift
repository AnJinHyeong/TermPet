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
        // MenuBarExtra: 메뉴바(화면 우상단)에 아이콘 + 드롭다운 메뉴를 만든다.
        // LSUIElement=YES 이므로 Dock 아이콘 없이 이것만 보인다.
        MenuBarExtra("TermPet", systemImage: "pawprint.fill") {
            MenuBarContent(pet: appDelegate.petController, appState: appDelegate.appState)
        }
    }
}

/// 메뉴바 드롭다운 내용. Phase 3에서 확장 예정.
struct MenuBarContent: View {
    let pet: PetController
    let appState: AppState

    var body: some View {
        Text("TermPet \(AppInfo.version)")
        Text(appState.serverStatusText)
        Divider()

        // pet.model은 @Observable이라 값이 바뀌면 메뉴 라벨도 자동 갱신된다
        Button(pet.model.isVisible ? "캐릭터 숨기기" : "캐릭터 보이기") {
            pet.setVisible(!pet.model.isVisible)
        }
        Button(pet.model.action == .sleep ? "깨우기" : "재우기") {
            pet.toggleSleep()
        }

        // 메뉴 안의 Picker는 체크 표시가 붙는 하위 메뉴로 렌더링된다.
        // Binding(get:set:) ≈ React의 제어 컴포넌트 (value + onChange)
        Picker("표시 위치", selection: Binding(
            get: { pet.model.layer },
            set: { pet.setLayer($0) }
        )) {
            ForEach(PetWindowLayer.allCases) { layer in
                Text(layer.title).tag(layer)
            }
        }

        #if DEBUG
        // 개발용: 상태별 모션 확인 (Release 빌드에는 포함되지 않음)
        Menu("디버그") {
            Button("신남 (happy)") { pet.react(.happy) }
            Button("화남 (angry)") { pet.react(.angry) }
            Button("확인 요청 (ask)") { pet.react(.ask) }
            Button("말하기 (talk)") { pet.react(.talk) }
            Button("위에서 떨어뜨리기") { pet.dropFromTop() }
            Divider()
            Button("테스트 알림: 완료 (Cursor로 이동)") { pet.receive(.debugSample(.done)) }
            Button("테스트 알림: 에러") { pet.receive(.debugSample(.error)) }
            Button("테스트 알림: 확인 요청") { pet.receive(.debugSample(.ask)) }
        }
        #endif

        Divider()
        Button("종료") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
