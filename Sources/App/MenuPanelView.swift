import AppKit
import SwiftUI

/// 메뉴바 아이콘을 누르면 뜨는 패널 (MenuBarExtra `.window` 스타일).
/// 테마: 크림 바탕 + 버터 노랑·볼터치 분홍 (우사기·치이카와 친구들 느낌의 말랑한 파스텔)
/// 구성: 무대(지금 캐릭터 + 상태) → 진행 중 세션 → 최근 알림 → 빠른 칩 → 탭(친구·알림·연결·설정) → 하단
/// React 비유: 작은 컴포넌트(Card, Chip, Tile)를 조합한 하나의 화면 컴포넌트.
struct MenuPanelView: View {
    let app: AppDelegate
    @State private var launchAtLogin = LoginItem.isEnabled  // @State ≈ useState
    /// 마지막으로 연 탭 (@AppStorage ≈ localStorage와 묶인 useState)
    @AppStorage("panelTab") private var tab: PanelTab = .friends
    /// 슬라이더 값 (펫 컨트롤러는 관찰 대상이 아니라서 화면용 사본을 들고 있다가 바꿀 때 넘긴다)
    @State private var prefs = PetPreferences.load()
    /// 패널이 지금 화면에 떠 있는지. MenuBarExtra 패널은 닫혀도 화면이 메모리에 남아 있어서
    /// 무대의 미니 펫이 펫 시계를 따라 계속 다시 그려졌다(닫힌 패널 전체 레이아웃 → CPU 낭비) → 닫혀 있으면 멈춘다.
    @State private var panelOpen = true
    private var pet: PetController { app.petController }
    private var characters: CharacterLibrary { app.characters }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            stage
                .padding(.horizontal, 12)
                .padding(.top, 12)

            // 새 버전이 있을 때만: [업데이트] 버튼 (누르면 brew로 바로 업데이트 후 다시 켜짐)
            if let version = app.updater.availableVersion {
                updateBanner(version: version)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            } else if app.updater.state == .updating {
                updateBanner(version: nil)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            // 진행 중인 AI 세션이 있을 때만 (누르면 그 프로젝트 창으로 이동)
            let sessions = pet.sessions.tracker.ordered
            if !sessions.isEmpty {
                SectionLabel("진행 중", symbol: "sparkle")
                // TimelineView: 30초마다 다시 그려 "3분" 같은 시간을 갱신 (≈ setInterval로 리렌더)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Card {
                        VStack(spacing: 0) {
                            ForEach(sessions) { session in
                                SessionRow(session: session, now: context.date) {
                                    closePanelThen { ProjectFocuser.focus(session.focusEvent) }
                                }
                            }
                        }
                    }
                }
            }

            // 최근 알림: 말풍선을 놓쳤어도 여기서 다시 보고 그 창으로 이동
            if !pet.history.entries.isEmpty {
                recentSection
            }

            // 자주 쓰는 것만 한 줄로
            quickChips
                .padding(.top, 12)

            // 나머지는 탭 안으로 (React 비유: 탭 상태 하나로 아래 내용을 조건부 렌더링)
            tabBar
                .padding(.horizontal, 12)
                .padding(.top, 12)
            Group {
                switch tab {
                case .friends: friendsTab
                case .alerts: alertsTab
                case .connect: connectTab
                case .settings: settingsTab
                }
            }
            .padding(.top, 8)

            footer
                .padding(.top, 12)
        }
        .frame(width: 312)
        .background(Theme.panelBackground)
        // 파스텔 테마는 다크 모드에서도 그대로 (크림 바탕 + 코코아 글씨)
        .environment(\.colorScheme, .light)
        .tint(Theme.blush)
        // 아이콘 안내 말풍선은 맨 위층에 (다른 영역에 가려지지 않게)
        .overlayPreferenceValue(HintPreference.self) { HintLayer(info: $0) }
        // 창이 보이는지 감시 (≈ document.visibilitychange)
        .background(WindowVisibilityReader { panelOpen = $0 })
        .onAppear {
            panelOpen = true
            app.integrations.refresh() // 터미널에서 직접 고쳤을 수도 있으니 열 때마다 다시 확인
            characters.reload() // Friends 폴더에 새로 만든 친구(캐릭터 만들기 스킬)가 바로 보이게
            launchAtLogin = LoginItem.isEnabled
            prefs = pet.preferences
        }
    }

    // MARK: - 무대 (지금 캐릭터)

    /// 지금 캐릭터가 통통 움직이는 작은 무대 + 이름·상태·오늘 기록 + 보이기 스위치
    private var stage: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle().fill(Theme.butter.opacity(0.55))
                Circle().strokeBorder(.white, lineWidth: 3)
                StagePetView(model: pet.model, live: panelOpen)
                    .frame(width: 58, height: 58)
                    .offset(y: 4)
                    .clipShape(Circle())
            }
            .frame(width: 66, height: 66)
            .shadow(color: Theme.cocoa.opacity(0.15), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(selectedName.isEmpty ? "텀펫" : selectedName)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.cocoa)
                    Text("텀펫 v\(AppInfo.version)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.cocoa.opacity(0.45))
                }
                HStack(spacing: 4) {
                    Circle().fill(serverColor).frame(width: 6, height: 6)
                    Text(serverText).font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.cocoa.opacity(0.65))
                    switch pet.model.mood {
                    case .cheerful: Text("· ✨ 신남").font(.system(size: 11, design: .rounded)).hint("최근 계속 성공했어요")
                    case .gloomy: Text("· 🌧 시무룩").font(.system(size: 11, design: .rounded)).hint("최근 에러가 많았어요")
                    case .normal: EmptyView()
                    }
                }
                if let line = pet.stats.today.summaryLine {
                    Text("오늘 " + line)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.cocoa.opacity(0.75))
                        .lineLimit(1)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(.white.opacity(0.75)))
                }
            }
            Spacer(minLength: 0)
            // Toggle ≈ <input type="checkbox">, isOn은 제어 컴포넌트처럼 Binding으로 연결
            Toggle("", isOn: Binding(get: { pet.model.isVisible }, set: { pet.setVisible($0) }))
                .toggleStyle(BunnySwitchStyle())
                .hint(pet.model.isVisible ? "펫 숨기기" : "펫 보이기")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Theme.butter, Theme.peach], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(alignment: .topTrailing) {
            // 장식: 작은 하트·별 (패널이 덜 딱딱해 보이게)
            HStack(spacing: 3) {
                Image(systemName: "heart.fill").font(.system(size: 7)).foregroundStyle(Theme.blush)
                Image(systemName: "sparkle").font(.system(size: 9)).foregroundStyle(.white)
            }
            .padding(.top, 7).padding(.trailing, 58)
            .allowsHitTesting(false)
        }
    }

    // MARK: - 최근 알림

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel("최근 알림", symbol: "clock.fill")
                Spacer()
                Button { pet.history.clear() } label: {
                    Text("지우기").font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.cocoa.opacity(0.5))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 18).padding(.top, 7)
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Card {
                    VStack(spacing: 0) {
                        ForEach(pet.history.entries.prefix(4)) { entry in
                            RecentRow(entry: entry, now: context.date) {
                                closePanelThen { ProjectFocuser.focus(entry.event) }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 빠른 칩

    private var quickChips: some View {
        ChipRow {
            let sleeping = pet.model.action == .sleep
            Chip(symbol: sleeping ? "sun.max.fill" : "moon.fill", title: sleeping ? "깨우기" : "재우기",
                 on: sleeping) { pet.toggleSleep() }
                .hint(sleeping ? "깨워서 다시 놀게 해요" : "쿨쿨 재워요")
            Chip(symbol: "moon.zzz.fill", title: "1시간 조용히", on: pet.quiet.manualOn) { pet.quiet.toggleManual() }
                .hint("1시간 동안 알림을 모아뒀다 보여줘요")
            Chip(symbol: "cloud.fill", title: "떨어뜨리기") { pet.dropFromTop() }
                .hint("하늘에서 뚝! 창 위에 떨어지면 거기서 놀아요")
        }
    }

    // MARK: - 탭

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(PanelTab.allCases) { t in
                Button { tab = t } label: {
                    HStack(spacing: 4) {
                        Image(systemName: t.symbol).font(.system(size: 10, weight: .bold))
                        Text(t.title).font(.system(size: 11.5, weight: tab == t ? .bold : .medium, design: .rounded))
                    }
                    .foregroundStyle(Theme.cocoa.opacity(tab == t ? 1 : 0.55))
                    .frame(maxWidth: .infinity).frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tab == t ? Color.white : .clear)
                        .shadow(color: Theme.cocoa.opacity(tab == t ? 0.12 : 0), radius: 2, y: 1))
                    .overlay(alignment: .topTrailing) {
                        // 연결 탭: 업데이트가 필요한 연결이 있으면 빨간 점
                        if t == .connect, app.integrations.needsUpdate.values.contains(true) {
                            Circle().fill(Theme.blushStrong).frame(width: 6, height: 6).offset(x: -6, y: 4)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cocoa.opacity(0.07)))
    }

    private var friendsTab: some View {
        Card { characterPicker }
    }

    private var alertsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            ChipRow {
                let quiet = pet.quiet
                Chip(symbol: "video.fill", title: "회의 중", on: quiet.duringMeetings) { quiet.duringMeetings.toggle() }
                    .hint("마이크 사용 중(회의)엔 알림을 모아둬요")
                Chip(symbol: quiet.soundOnAsk ? "speaker.wave.2.fill" : "speaker.slash.fill", title: "권한 소리",
                     on: quiet.soundOnAsk) { quiet.soundOnAsk.toggle() }
                    .hint("Claude가 권한을 물으면 소리로 알려줘요")
                Chip(symbol: "bubble.left.fill", title: "알림 테스트") {
                    pet.receive(PetEvent(source: .shell, kind: .done, message: "알림이 잘 보이나요?"))
                }
                .hint("말풍선을 한 번 띄워 봐요")
            }
            if pet.quiet.isQuiet {
                Text(pet.quiet.manualOn ? "조용한 시간 · 알림은 펫 머리 위 !에 모여요"
                                        : "회의 중이라 조용히 · 알림은 펫 머리 위 !에 모여요")
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.cocoa.opacity(0.6))
                    .padding(.horizontal, 18).padding(.top, 6)
            }
            Card {
                PrefSlider(title: "말풍선 유지", symbol: "timer", value: $prefs.bubbleSeconds,
                           range: PetPreferences.bubbleRange, step: 1, defaultValue: PetPreferences().bubbleSeconds, label: { "\(Int($0))초" }) {
                    pet.preferences = prefs
                }
            }
            .padding(.top, 8)
        }
    }

    private var connectTab: some View {
        Card {
            VStack(spacing: 2) {
                ForEach(IntegrationManager.Kind.allCases) { kind in
                    IntegrationRow(kind: kind,
                                   installed: app.integrations.installed[kind] == true,
                                   needsUpdate: app.integrations.needsUpdate[kind] == true,
                                   available: app.integrations.isAvailable(kind),
                                   onUpdate: { app.toggleIntegration(kind) }) { on in
                        app.toggleIntegration(kind, remove: !on)
                    }
                }
            }
        }
    }

    private var settingsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            Card {
                VStack(spacing: 10) {
                    PrefSlider(title: "크기", symbol: "arrow.up.left.and.arrow.down.right", value: $prefs.sizeScale,
                               range: PetPreferences.sizeRange, step: 0.1, label: { "\(Int(($0 * 100).rounded()))%" }) {
                        pet.preferences = prefs
                    }
                    PrefSlider(title: "걷기 속도", symbol: "hare.fill", value: $prefs.speedScale,
                               range: PetPreferences.speedRange, step: 0.1, label: { String(format: "×%.1f", $0) }) {
                        pet.preferences = prefs
                    }
                }
            }

            SectionLabel("표시 위치", symbol: "macwindow")
            // 라디오 버튼처럼 하나만 선택 (다른 칩과 같은 모양)
            ChipRow {
                ForEach(PetWindowLayer.allCases) { layer in
                    Chip(symbol: layer.symbol, title: layer.shortTitle, on: pet.model.layer == layer) { pet.setLayer(layer) }
                        .hint(layer.title)
                }
            }

            SectionLabel("움직임", symbol: "figure.walk")
            ChipGrid {
                Chip(symbol: "figure.climbing", title: "창 위 산책", on: pet.model.walkOnWindows) {
                    pet.walkOnWindows.toggle()
                }
                .hint(pet.model.layer == .aboveApps ? "창 위를 걷고, 창을 기어올라요"
                                                     : "'항상 위' 표시일 때만 창 위로 다녀요")
                let exactDock = WindowScanner.canReadDockExactly
                Chip(symbol: "dock.rectangle", title: "Dock 정확히", on: exactDock) {
                    if !exactDock { closePanelThen { WindowScanner.requestDockAccess() } }
                }
                .hint(exactDock ? "Dock 끝을 정확히 알고 있어요"
                                : "손쉬운 사용 권한을 켜면 Dock 끝을 정확히 알아서 뒤로 숨지 않아요")
                Chip(symbol: "cursorarrow.motionlines", title: "장난꾸러기", on: pet.model.mischief) {
                    pet.mischiefEnabled.toggle()
                }
                .hint("마우스 포인터를 계속 쫓아다니다가 잡으면 물고 휙 던져요 (물렸을 때 클릭하면 놓아줘요)")
            }
            Text("펫을 잡아서 휙 던져 보세요")
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(Theme.cocoa.opacity(0.55))
                .padding(.horizontal, 18).padding(.top, 6)

            #if DEBUG
            SectionLabel("개발용", symbol: "hammer.fill")
            ChipRow {
                Chip(symbol: "face.smiling", title: "신남") { pet.react(.happy) }
                Chip(symbol: "flame.fill", title: "화남") { pet.react(.angry) }
                Chip(symbol: "hand.raised.fill", title: "확인 요청") { pet.receive(.debugSample(.ask)) }
            }
            #endif
        }
    }

    // MARK: - 친구 고르기

    /// 친구들을 동그란 타일 격자로. 선택된 타일은 분홍 테두리 + 이름
    private var characterPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            // LazyVGrid ≈ CSS grid (5칸)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(48), spacing: 8), count: 5), alignment: .leading, spacing: 8) {
                ForEach(characters.entries) { entry in
                    let selected = entry.id == characters.selectedId
                    let removable = characters.canRemove(entry)
                    Button { app.selectCharacter(entry.id) } label: {
                        CharacterThumbnail(entry: entry, selected: selected)
                    }
                    .buttonStyle(PressableStyle())
                    .hint(removable ? "\(entry.name) · 우클릭하면 삭제" : entry.name)
                    // 우클릭 메뉴 (.contextMenu ≈ onContextMenu 로 띄우는 메뉴)
                    .contextMenu {
                        if removable {
                            Button("'\(entry.name)' 지우기…", role: .destructive) {
                                closePanelThen { app.deleteCharacter(entry.id) }
                            }
                        }
                    }
                }
                // 친구 추가하기: zip을 골라 캐릭터 팩 설치
                Button { closePanelThen { app.importFriends() } } label: {
                    ZStack {
                        Circle().strokeBorder(Theme.cocoa.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.cocoa.opacity(0.6))
                    }
                    .frame(width: 46, height: 46)
                }
                .buttonStyle(PressableStyle())
                .hint("친구 추가하기 (zip 파일 고르기)")
            }

            HStack(spacing: 5) {
                Image(systemName: "heart.fill").font(.system(size: 9)).foregroundStyle(Theme.blush)
                Text(selectedName).font(.system(size: 12.5, weight: .bold, design: .rounded)).foregroundStyle(Theme.cocoa)
                Spacer()
            }
        }
    }

    private var selectedName: String {
        characters.entries.first { $0.id == characters.selectedId }?.name ?? ""
    }

    // MARK: - 푸터

    private var footer: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { launchAtLogin },
                set: { on in
                    do { try LoginItem.set(on) } catch { NSLog("[TermPet] login item: \(error)") }
                    launchAtLogin = LoginItem.isEnabled // 실패하면 실제 상태로 되돌아감
                })) {
                Text("로그인 시 실행").font(.system(size: 11.5, design: .rounded)).foregroundStyle(Theme.cocoa.opacity(0.8))
            }
            .toggleStyle(.checkbox)
            Spacer()
            // 버전 · 누르면 새 버전 확인
            Button { Task { await app.updater.check() } } label: {
                Text(versionLabel)
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(Theme.cocoa.opacity(0.55))
            }
            .buttonStyle(.plain)
            .hint(versionHint)
            Button { NSApplication.shared.terminate(nil) } label: {
                HStack(spacing: 3) {
                    Image(systemName: "power").font(.system(size: 9, weight: .bold))
                    Text("종료").font(.system(size: 11.5, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 10).frame(height: 24)
                .modifier(ControlSurface(radius: 12))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.cream.opacity(0.9))
        .overlay(alignment: .top) { Rectangle().fill(Theme.cocoa.opacity(0.08)).frame(height: 1) }
    }

    /// 새 버전 안내 띠 (version == nil 이면 업데이트 중 표시)
    private func updateBanner(version: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.blushStrong)
            VStack(alignment: .leading, spacing: 1) {
                Text(version.map { "새 버전 v\($0)이 나왔어요" } ?? "업데이트 중…")
                    .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Theme.cocoa)
                Text(version == nil ? "잠시 꺼졌다가 다시 켜져요" : "지금 버전 v\(app.updater.current)")
                    .font(.system(size: 10.5, design: .rounded)).foregroundStyle(Theme.cocoa.opacity(0.6))
            }
            Spacer()
            if version != nil {
                Button { app.updater.update() } label: {
                    Text("업데이트")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        .padding(.horizontal, 12).frame(height: 24)
                        .background(Capsule().fill(Theme.blush))
                }
                .buttonStyle(PressableStyle())
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.butter.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.blush.opacity(0.5), lineWidth: 1))
    }

    /// 푸터 버전 글씨: 확인 결과를 짧게 보여 준다
    private var versionLabel: String {
        switch app.updater.state {
        case .checking: return "확인 중…"
        case .upToDate: return "v\(app.updater.current) · 최신"
        // 확인이 실패해도 지금 버전은 항상 보여 준다 (이유는 마우스를 올리면)
        case .failed: return "v\(app.updater.current) · 확인 실패"
        default: return "v\(app.updater.current)"
        }
    }

    private var versionHint: String {
        if case .failed(let message) = app.updater.state { return message + " · 눌러서 다시 확인" }
        return "눌러서 새 버전 확인"
    }

    private var serverColor: Color {
        switch app.appState.serverState {
        case .listening: return Color(red: 0.45, green: 0.78, blue: 0.5)
        case .stopped: return .gray
        case .failed: return .red
        }
    }

    private var serverText: String {
        switch app.appState.serverState {
        case .listening: return "알림 받는 중"
        case .stopped: return "알림 꺼짐"
        case .failed(let message): return "오류: \(message)"
        }
    }

    /// 파일 선택 창을 띄우기 전에 패널을 닫는다 (패널이 떠 있으면 선택 창 뒤로 가려짐)
    private func closePanelThen(_ action: @escaping () -> Void) {
        NSApp.keyWindow?.close()
        DispatchQueue.main.async(execute: action)
    }
}

// MARK: - 테마

/// 패널 색 모음 (CSS 변수 :root { --butter: ... } 같은 역할)
enum Theme {
    static let cream = Color(red: 1.00, green: 0.975, blue: 0.93)
    static let butter = Color(red: 1.00, green: 0.91, blue: 0.66)     // 우사기 몸 색
    static let peach = Color(red: 1.00, green: 0.84, blue: 0.80)
    static let blush = Color(red: 0.96, green: 0.56, blue: 0.66)      // 볼터치 분홍 (강조색)
    static let blushStrong = Color(red: 0.88, green: 0.38, blue: 0.52)
    static let sky = Color(red: 0.70, green: 0.85, blue: 0.95)        // 하치와레·모몬가 하늘색
    static let cocoa = Color(red: 0.36, green: 0.25, blue: 0.20)      // 글씨·테두리

    static var panelBackground: some View {
        LinearGradient(colors: [cream, Color(red: 1.0, green: 0.95, blue: 0.94)], startPoint: .top, endPoint: .bottom)
    }
}

/// 말랑한 분홍 스위치 (macOS 기본 스위치는 색을 바꿔도 잘 안 보여서 직접 그림)
/// ToggleStyle ≈ 체크박스 input의 모양만 CSS로 바꾸는 것
private struct BunnySwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? Theme.blush : Theme.cocoa.opacity(0.18))
                Circle().fill(.white).padding(2.5)
                    .shadow(color: Theme.cocoa.opacity(0.25), radius: 1.5, y: 1)
                    .overlay(
                        Image(systemName: configuration.isOn ? "eye.fill" : "eye.slash.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(configuration.isOn ? Theme.blushStrong : Theme.cocoa.opacity(0.4))
                    )
            }
            .frame(width: 44, height: 26)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isOn)
        }
        .buttonStyle(.plain)
    }
}

/// 누르면 살짝 작아지는 버튼 (CSS :active { transform: scale(.94) })
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// 무대 위 미니 펫: 실제 펫과 같은 상태를 작게 그린다 (말풍선·배지 없이)
private struct StagePetView: View {
    let model: PetViewModel
    /// false(패널 닫힘)면 펫 시계를 읽지 않는 정지 그림 → 펫이 움직여도 패널을 다시 그리지 않는다
    var live = true

    var body: some View {
        if !live {
            still
        } else {
            moving
        }
    }

    @ViewBuilder
    private var still: some View {
        switch model.character {
        case .builtIn(let style):
            DefaultCharacterView(style: style, action: .idle, facing: .right, time: 0, actionTime: 0)
                .frame(width: LoadedCharacter.defaultSize.width, height: LoadedCharacter.defaultSize.height)
                .scaleEffect(0.72)
        case .sprite(let sprite):
            SpriteCharacterView(sprite: sprite, action: .idle, facing: .right, actionTime: 0)
        }
    }

    @ViewBuilder
    private var moving: some View {
        switch model.character {
        case .builtIn(let style):
            DefaultCharacterView(style: style, action: model.action, facing: .right,
                                 time: model.time, actionTime: model.actionTime)
                .frame(width: LoadedCharacter.defaultSize.width, height: LoadedCharacter.defaultSize.height)
                .scaleEffect(0.72)
        case .sprite(let sprite):
            // 무대에선 늘 정면/오른쪽, 잡히거나 떨어지는 중이어도 가만히 있는 모습
            let action: PetAction = model.action.isPhysicsControlled ? .idle : model.action
            SpriteCharacterView(sprite: sprite, action: action, variant: model.variant,
                                facing: .right, actionTime: model.time)
        }
    }
}

// MARK: - 작은 구성 요소들

/// 흰 카드 (둥근 모서리 + 아주 옅은 그림자)
private struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cocoa.opacity(0.06)))
            .shadow(color: Theme.cocoa.opacity(0.06), radius: 3, y: 1)
            .padding(.horizontal, 12)
    }
}

private struct SectionLabel: View {
    let text: String
    let symbol: String
    init(_ text: String, symbol: String) { self.text = text; self.symbol = symbol }
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.blush)
            Text(text).font(.system(size: 11.5, weight: .bold, design: .rounded)).foregroundStyle(Theme.cocoa.opacity(0.7))
        }
        .padding(.horizontal, 18)
        .padding(.top, 13)
        .padding(.bottom, 6)
    }
}

/// 마우스를 올리면 살짝 밝아지는 줄 배경 (CSS :hover)
private struct HoverBackground: ViewModifier {
    var selected: Bool
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Theme.butter.opacity(0.6)
                          : hovering ? Theme.butter.opacity(0.35) : .clear)
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

/// 동그란 캐릭터 타일 (기본 캐릭터는 코드로 그리고, 그림 팩은 대표 그림)
private struct CharacterThumbnail: View {
    let entry: CharacterLibrary.Entry
    var selected = false
    @State private var hovering = false

    var body: some View {
        ZStack {
            Circle().fill(background)
            content.clipShape(Circle())
            Circle().strokeBorder(selected ? Theme.blush : Theme.cocoa.opacity(hovering ? 0.25 : 0.1),
                                  lineWidth: selected ? 3 : 1)
        }
        .frame(width: 46, height: 46)
        .overlay(alignment: .topTrailing) {
            if selected {
                Image(systemName: "heart.fill")
                    .font(.system(size: 9)).foregroundStyle(.white)
                    .padding(3).background(Circle().fill(Theme.blush))
                    .offset(x: 3, y: -3)
            }
        }
        .scaleEffect(hovering && !selected ? 1.06 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hovering)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var content: some View {
        switch entry.source {
        case .builtIn(let style):
            // 기본 캐릭터는 80pt 펫 창 크기로 그려지므로 그 크기로 그린 뒤 축소 (CSS transform: scale)
            DefaultCharacterView(style: style, action: .idle, facing: .right, time: 1.3, actionTime: 1.3)
                .frame(width: LoadedCharacter.defaultSize.width, height: LoadedCharacter.defaultSize.height)
                .scaleEffect(0.52)
                .frame(width: 46, height: 46)
                .offset(y: 2)
        case .pack(let folder):
            if let image = NSImage(contentsOf: folder.appendingPathComponent("source.png")) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(5).offset(y: 2)
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
    }

    private var background: Color {
        switch entry.source {
        case .builtIn(let style): return style.palette.bodyTop.opacity(0.4)
        case .pack: return entry.id.hasPrefix(CharacterLibrary.friendPrefix) ? Theme.butter.opacity(0.45) : Theme.sky.opacity(0.35)
        }
    }
}

/// AI 연결 한 줄: 작은 아이콘 · 이름 · [연결] / [연결됨 ✓] / [업데이트]
private struct IntegrationRow: View {
    let kind: IntegrationManager.Kind
    let installed: Bool
    var needsUpdate = false
    let available: Bool
    let onUpdate: () -> Void
    /// 연결(true) / 해제(false)
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(color.gradient)
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 24, height: 24)
            .hint("\(kind.subtitle) 알림")
            Text(kind.title).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Theme.cocoa)
            Spacer()
            if !available {
                Text("설치 안 됨").font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.cocoa.opacity(0.5))
            } else {
                // 상태가 글자로 바로 보이는 버튼: 켜짐(✓ 연결됨) = 진한 주황, 꺼짐(연결) = 회색 — 다른 칩과 같은 규칙
                Button { needsUpdate ? onUpdate() : onToggle(!installed) } label: {
                    HStack(spacing: 3) {
                        Image(systemName: needsUpdate ? "arrow.triangle.2.circlepath" : installed ? "checkmark" : "link")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(installed ? Theme.blushStrong : Theme.cocoa.opacity(0.6))
                        Text(needsUpdate ? "업데이트" : installed ? "연결됨" : "연결")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .frame(width: 74, height: 24)
                    .modifier(ControlSurface(on: installed, radius: 12))
                }
                .buttonStyle(PressableStyle())
                .hint(needsUpdate ? "새 형식으로 다시 연결 (백업 후)"
                      : installed ? "누르면 연결 해제 (설정 파일 백업 후)" : "누르면 연결 (설정 파일 백업 후)")
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .opacity(available ? 1 : 0.5)
    }

    private var symbol: String {
        switch kind {
        case .claude: return "sparkles"
        case .claudeApp: return "bubble.left.and.text.bubble.right.fill"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .chatgptApp: return "bubble.left.fill"
        case .zsh: return "terminal.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .claude: return Color(red: 0.93, green: 0.58, blue: 0.45)
        case .claudeApp: return Color(red: 0.85, green: 0.52, blue: 0.62)
        case .codex: return Color(red: 0.50, green: 0.62, blue: 0.80)
        case .chatgptApp: return Color(red: 0.42, green: 0.72, blue: 0.70)
        case .zsh: return Color(red: 0.50, green: 0.78, blue: 0.62)
        }
    }
}

/// 3칸 균등 칩 줄 (CSS grid-template-columns: repeat(3, 1fr))
private struct ChipRow<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        HStack(spacing: 6) { content }.padding(.horizontal, 12)
    }
}

/// 2칸 칩 격자 (놀기 버튼 4개)
private struct ChipGrid<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) { content }
            .padding(.horizontal, 12)
    }
}

/// 패널의 모든 버튼이 쓰는 공통 모양 (CSS로 치면 .btn / .btn.is-on 클래스)
/// - 기본: 흰 말랑 버튼 + 옅은 테두리, 마우스 올리면 버터색
/// - 켜짐/선택: 버터 노랑 바탕 + 분홍 테두리 + 진한 코코아 글씨
private struct ControlSurface: ViewModifier {
    var on = false
    var radius: CGFloat = 12
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(Theme.cocoa.opacity(on ? 1 : 0.8))
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(on ? Theme.butter.opacity(hovering ? 1 : 0.85)
                         : hovering ? Theme.butter.opacity(0.35) : Color.white.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(on ? Theme.blush.opacity(0.9) : Theme.cocoa.opacity(0.1), lineWidth: on ? 1.5 : 1))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

/// 작은 버튼/토글 칩: 아이콘 + 짧은 글자
private struct Chip: View {
    let symbol: String
    let title: String
    var on = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(on ? Theme.blushStrong : Theme.cocoa.opacity(0.6)) // 켜지면 아이콘만 분홍
                Text(title).font(.system(size: 11.5, weight: on ? .bold : .medium, design: .rounded)).lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .modifier(ControlSurface(on: on))
        }
        .buttonStyle(PressableStyle())
    }
}

/// 패널 아래쪽 탭 (String rawValue라 @AppStorage에 그대로 저장됨)
enum PanelTab: String, CaseIterable, Identifiable {
    case friends, alerts, connect, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .friends: return "친구"
        case .alerts: return "알림"
        case .connect: return "연결"
        case .settings: return "설정"
        }
    }
    var symbol: String {
        switch self {
        case .friends: return "heart.fill"
        case .alerts: return "bell.fill"
        case .connect: return "link"
        case .settings: return "slider.horizontal.3"
        }
    }
}

/// 설정 슬라이더 한 줄: 아이콘 · 이름 · 값 / 슬라이더
/// onCommit: 손을 뗐을 때 한 번 (크기처럼 바꿀 때마다 창을 다시 맞추는 값은 끌 때마다 반영하면 덜컹거림)
private struct PrefSlider: View {
    let title: String
    let symbol: String
    @Binding var value: Double   // @Binding ≈ 부모가 내려준 [value, setValue] 쌍
    let range: ClosedRange<Double>
    let step: Double
    var defaultValue: Double = 1
    let label: (Double) -> String
    let onCommit: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.blush)
                    .frame(width: 14)
                Text(title).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.cocoa)
                Spacer()
                Text(label(value)).font(.system(size: 11.5, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.cocoa.opacity(0.7))
                // 기본값으로
                Button { value = defaultValue; onCommit() } label: {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.cocoa.opacity(0.4))
                }
                .buttonStyle(.plain)
                .hint("기본값으로")
            }
            // step을 주면 눈금이 촘촘히 그려져 지저분해서, 연속 슬라이더 + 값만 step 단위로 반올림
            Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range) { editing in
                if !editing { onCommit() }
            }
            .controlSize(.small)
        }
    }
}

/// 최근 알림 한 줄: 종류 아이콘 · 프로젝트 · 문구 · "3분 전"
private struct RecentRow: View {
    let entry: NotificationHistory.Entry
    let now: Date
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.title)
                        .font(.system(size: 12.5, weight: .bold, design: .rounded)).foregroundStyle(Theme.cocoa).lineLimit(1)
                    Text(entry.body)
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(ago).font(.system(size: 10.5, design: .rounded)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .modifier(HoverBackground(selected: false))
        }
        .buttonStyle(.plain)
        .hint(entry.event.cwd == nil ? entry.body : "이 프로젝트 창으로 이동")
    }

    private var ago: String {
        let s = max(0, now.timeIntervalSince(entry.date))
        if s < 60 { return "방금" }
        if s < 3600 { return "\(Int(s / 60))분 전" }
        return "\(Int(s / 3600))시간 전"
    }

    private var symbol: String {
        switch entry.event.kind {
        case .error: return "exclamationmark.triangle.fill"
        case .ask: return "hand.raised.fill"
        default: return "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch entry.event.kind {
        case .error: return Color(red: 0.95, green: 0.6, blue: 0.3)
        case .ask: return Theme.blushStrong
        default: return Color(red: 0.45, green: 0.75, blue: 0.5)
        }
    }
}

/// 진행 중 세션 한 줄: 상태 아이콘 · 프로젝트 · "작업 중 · 3분"
private struct SessionRow: View {
    let session: SessionTracker.Session
    let now: Date
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.projectName ?? BubbleContent.sourceLabel(session.source))
                        .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.cocoa).lineLimit(1)
                    Text("\(BubbleContent.sourceLabel(session.source)) · \(stateText) · \(elapsed)")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                    .hint("이 프로젝트 창으로 이동")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .modifier(HoverBackground(selected: false))
        }
        .buttonStyle(.plain)

    }

    private var stateText: String {
        switch session.state {
        case .working: return "작업 중"
        case .waiting: return "권한 대기"
        case .done: return "끝남"
        case .error: return "에러"
        }
    }

    private var elapsed: String {
        let s = max(0, now.timeIntervalSince(session.since))
        return s < 60 ? "방금" : BubbleContent.formatDuration((s / 60).rounded(.down) * 60)
    }

    private var symbol: String {
        switch session.state {
        case .working: return "ellipsis.circle.fill"
        case .waiting: return "hand.raised.fill"
        case .done: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch session.state {
        case .working: return Color(red: 0.45, green: 0.65, blue: 0.88)
        case .waiting: return Theme.blushStrong
        case .done: return Color(red: 0.45, green: 0.75, blue: 0.5)
        case .error: return Color(red: 0.95, green: 0.6, blue: 0.3)
        }
    }
}

// MARK: - 마우스 올리면 뜨는 안내

/// 메뉴바 패널은 앱이 활성 상태가 아니라 macOS 기본 툴팁(.help)이 잘 안 뜬다 → 직접 그리는 작은 안내 말풍선.
/// 각 아이콘은 "지금 안내를 띄워줘(문구 + 내 위치)"만 위로 알리고, 실제 그리기는 패널 맨 위층(HintLayer)에서 한다.
/// 그래야 다른 영역 밑에 깔리지 않는다. React 비유: 툴팁을 portal로 body 맨 위에 렌더링하는 것.
/// PreferenceKey ≈ 자식 → 부모로 값을 올려보내는 Context의 반대 방향 통로.
private struct HintInfo {
    let text: String
    let anchor: Anchor<CGRect>   // 아이콘의 위치 (부모 좌표로 변환 가능한 핸들)
}

private struct HintPreference: PreferenceKey {
    static var defaultValue: HintInfo? = nil
    static func reduce(value: inout HintInfo?, nextValue: () -> HintInfo?) {
        value = value ?? nextValue()
    }
}

private struct HoverHint: ViewModifier {
    let text: String
    @State private var hovering = false
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                hovering = inside
                if inside {
                    // 0.3초 머물러야 뜬다 (스쳐 지나갈 땐 안 보임)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { if hovering { visible = true } }
                } else {
                    visible = false
                }
            }
            .anchorPreference(key: HintPreference.self, value: .bounds) { visible ? HintInfo(text: text, anchor: $0) : nil }
    }
}

/// 패널 맨 위층에 안내 말풍선을 그린다: 아이콘 위(공간이 없으면 아래), 패널 밖으로 안 나가게 좌우를 맞춤
private struct HintLayer: View {
    let info: HintInfo?

    var body: some View {
        GeometryReader { proxy in
            if let info {
                let rect = proxy[info.anchor]
                let width = BubbleMetrics.textWidth(info.text, .systemFont(ofSize: 11, weight: .medium)).rounded(.up) + 16
                let height: CGFloat = 22
                let x = min(max(rect.midX, width / 2 + 6), proxy.size.width - width / 2 - 6)
                let aboveY = rect.minY - 6 - height / 2
                let y = aboveY - height / 2 < 2 ? rect.maxY + 6 + height / 2 : aboveY
                Text(info.text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(width: width, height: height)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.cocoa.opacity(0.92)))
                    .position(x: x, y: y)
                    .allowsHitTesting(false)
            }
        }
    }
}

private extension View {
    func hint(_ text: String) -> some View {
        modifier(HoverHint(text: text))
    }
}

/// 이 뷰가 들어 있는 창이 지금 화면에 보이는지 알려 준다 (≈ document.visibilityState / IntersectionObserver).
/// NSViewRepresentable ≈ React에서 ref로 DOM 노드를 직접 다루는 것: AppKit 뷰를 SwiftUI 안에 끼워 넣는다.
private struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.onChange = onChange
    }

    final class ReaderView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observer: NSObjectProtocol?
        private var last: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { report(false); return }
            // 창이 화면에 나타나거나(패널 열림) 사라질 때(패널 닫힘) 오는 알림
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.report(self.window?.occlusionState.contains(.visible) ?? false)
            }
            report(window.occlusionState.contains(.visible))
        }

        private func report(_ visible: Bool) {
            guard visible != last else { return }
            last = visible
            // 화면 갱신 도중에 상태를 바꾸지 않도록 다음 차례에
            DispatchQueue.main.async { [weak self] in self?.onChange?(visible) }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
