import AppKit
import SwiftUI

/// 메뉴바 아이콘을 누르면 뜨는 패널 (MenuBarExtra `.window` 스타일).
/// 구성: 헤더 → 진행 중 세션 → 캐릭터(가로 아이콘) → AI 연결 → 알림·놀기 칩 → 표시 위치 세그먼트 → 하단
/// React 비유: 작은 컴포넌트(Row, Tile)를 조합한 하나의 화면 컴포넌트.
struct MenuPanelView: View {
    let app: AppDelegate
    @State private var launchAtLogin = LoginItem.isEnabled  // @State ≈ useState
    private var pet: PetController { app.petController }
    private var characters: CharacterLibrary { app.characters }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            todayLine
            PanelDivider()

            // 진행 중인 AI 세션이 있을 때만 (누르면 그 프로젝트 창으로 이동)
            let sessions = pet.sessions.tracker.ordered
            if !sessions.isEmpty {
                SectionLabel("진행 중")
                // TimelineView: 30초마다 다시 그려 "3분" 같은 시간을 갱신 (≈ setInterval로 리렌더)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(spacing: 0) {
                        ForEach(sessions) { session in
                            SessionRow(session: session, now: context.date) {
                                closePanelThen { ProjectFocuser.focus(session.focusEvent) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            SectionLabel("캐릭터")
            characterPicker

            SectionLabel("AI 연결")
            VStack(spacing: 0) {
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
            .padding(.horizontal, 8)

            SectionLabel("알림")
            ChipRow {
                let quiet = pet.quiet
                Chip(symbol: "moon.zzz.fill", title: "1시간 조용히", on: quiet.manualOn) { quiet.toggleManual() }
                    .hint("1시간 동안 알림을 모아뒀다 보여줘요")
                Chip(symbol: "video.fill", title: "회의 중 조용히", on: quiet.duringMeetings) { quiet.duringMeetings.toggle() }
                    .hint("마이크 사용 중(회의)엔 알림을 모아둬요")
                Chip(symbol: quiet.soundOnAsk ? "speaker.wave.2.fill" : "speaker.slash.fill", title: "권한 소리",
                     on: quiet.soundOnAsk) { quiet.soundOnAsk.toggle() }
                    .hint("Claude가 권한을 물으면 소리로 알려줘요")
            }
            if pet.quiet.isQuiet {
                Text(pet.quiet.manualOn ? "조용한 시간 · 알림은 펫 머리 위 !에 모여요"
                                        : "회의 중이라 조용히 · 알림은 펫 머리 위 !에 모여요")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.top, 5)
            }

            SectionLabel("표시 위치")
            // 라디오 버튼처럼 하나만 선택 (다른 칩과 같은 모양)
            ChipRow {
                ForEach(PetWindowLayer.allCases) { layer in
                    Chip(symbol: layer.symbol, title: layer.shortTitle, on: pet.model.layer == layer) { pet.setLayer(layer) }
                        .hint(layer.title)
                }
            }

            SectionLabel("놀기")
            ChipRow {
                let sleeping = pet.model.action == .sleep
                Chip(symbol: sleeping ? "sun.max.fill" : "moon.fill", title: sleeping ? "깨우기" : "재우기",
                     on: sleeping) { pet.toggleSleep() }
                Chip(symbol: "arrow.down.to.line", title: "떨어뜨리기") { pet.dropFromTop() }
                Chip(symbol: "bubble.left.fill", title: "알림 테스트") {
                    pet.receive(PetEvent(source: .shell, kind: .done, message: "알림이 잘 보이나요?"))
                }
            }

            #if DEBUG
            SectionLabel("개발용")
            ChipRow {
                Chip(symbol: "face.smiling", title: "신남") { pet.react(.happy) }
                Chip(symbol: "flame.fill", title: "화남") { pet.react(.angry) }
                Chip(symbol: "hand.raised.fill", title: "확인 요청") { pet.receive(.debugSample(.ask)) }
            }
            #endif

            PanelDivider().padding(.top, 12)
            footer
        }
        .frame(width: 300)
        .padding(.top, 2)
        // 아이콘 안내 말풍선은 맨 위층에 (다른 영역에 가려지지 않게)
        .overlayPreferenceValue(HintPreference.self) { HintLayer(info: $0) }
        .onAppear {
            app.integrations.refresh() // 터미널에서 직접 고쳤을 수도 있으니 열 때마다 다시 확인
            launchAtLogin = LoginItem.isEnabled
        }
    }

    /// 캐릭터: 가로 한 줄 아이콘 + 아래에 선택된 이름과 (내 캐릭터면) 작은 편집 버튼
    private var characterPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(characters.entries) { entry in
                    Button { app.selectCharacter(entry.id) } label: {
                        CharacterThumbnail(entry: entry, size: 40)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(entry.id == characters.selectedId ? Color.accent : .clear, lineWidth: 2)
                                    .padding(-3)
                            )
                    }
                    .buttonStyle(.plain)
                    .hint(entry.name)
                }
                if characters.custom == nil {
                    Button { closePanelThen { app.makeCharacterFromImage() } } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.accent)
                        }
                        .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .hint(characters.problem ?? "이미지로 캐릭터 만들기")
                }
            }
            .padding(.top, 3)

            HStack(spacing: 5) {
                Text(selectedName).font(.system(size: 12, weight: .semibold))
                if characters.selectedId == CharacterLibrary.customId {
                    Text("· 내 캐릭터").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if characters.custom != nil {
                    IconButton(symbol: "photo.badge.plus", help: "새 이미지로 바꾸기") {
                        closePanelThen { app.makeCharacterFromImage() }
                    }
                    // 동작별 그림: 여러 장을 고르면 진짜 프레임 애니메이션 (Menu ≈ 드롭다운)
                    Menu {
                        ForEach(PetAction.allCases, id: \.self) { action in
                            Button(action.title + "…") { closePanelThen { app.pickStateFrames(action) } }
                        }
                        Divider()
                        Button("모든 동작 원래대로") { app.resetCustomStates() }
                    } label: {
                        Image(systemName: "figure.walk").font(.system(size: 11, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 28, height: 24)
                    .modifier(ControlSurface(radius: 7))
                    .hint("동작별 그림 (여러 장 = 애니메이션)")
                    IconButton(symbol: "arrow.left.and.right", help: "방향 바꾸기") { app.flipCustomCharacter() }
                    IconButton(symbol: "trash", help: "내 캐릭터 지우기") { app.removeCustomCharacter() }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    /// 오늘 기록 한 줄 + 기분 (기록이 없으면 숨김)
    @ViewBuilder private var todayLine: some View {
        let stats = pet.stats.today
        if let line = stats.summaryLine {
            HStack(spacing: 6) {
                Text("오늘").font(.system(size: 11, weight: .semibold))
                Text(line).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                switch pet.model.mood {
                case .cheerful: Text("✨ 신남").font(.system(size: 11)).hint("최근 계속 성공했어요")
                case .gloomy: Text("🌧 시무룩").font(.system(size: 11)).hint("최근 에러가 많았어요")
                case .normal: EmptyView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private var selectedName: String {
        characters.entries.first { $0.id == characters.selectedId }?.name ?? ""
    }

    // MARK: - 헤더 / 푸터

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("텀펫").font(.system(size: 14, weight: .bold))
                    Text("v\(AppInfo.version)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(serverColor).frame(width: 6, height: 6)
                    Text(serverText).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            // Toggle ≈ <input type="checkbox">, isOn은 제어 컴포넌트처럼 Binding으로 연결
            Toggle("", isOn: Binding(get: { pet.model.isVisible }, set: { pet.setVisible($0) }))
                .toggleStyle(.switch)
                .tint(Color.accent)
                .labelsHidden()
                .hint(pet.model.isVisible ? "펫 숨기기" : "펫 보이기")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Toggle("로그인할 때 자동으로 실행", isOn: Binding(
                get: { launchAtLogin },
                set: { on in
                    do { try LoginItem.set(on) } catch { NSLog("[TermPet] login item: \(error)") }
                    launchAtLogin = LoginItem.isEnabled // 실패하면 실제 상태로 되돌아감
                }))
                .toggleStyle(.checkbox)
                .tint(Color.accent)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
            footerLine
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var footerLine: some View {
        HStack {
            Text("펫을 누르면 놓친 알림을 다시 보여줘요")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("종료") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
        }
    }

    private var serverColor: Color {
        switch app.appState.serverState {
        case .listening: return .green
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

// MARK: - 작은 구성 요소들

private struct PanelDivider: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1).padding(.horizontal, 12)
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 5)
    }
}

/// 마우스를 올리면 살짝 밝아지는 버튼 배경 (CSS :hover)
private struct HoverBackground: ViewModifier {
    var selected: Bool
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.accent.opacity(0.22)
                          : hovering ? Color.primary.opacity(0.07) : .clear)
            )
            // 선택된 항목은 주황 테두리까지 둘러서 한눈에 보이게
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.accent : .clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

private extension Color {
    /// 강조색: 앱 아이콘 말랑이의 주황빛 (상단 스위치와 같은 색)
    static let accent = Color(red: 0.98, green: 0.65, blue: 0.30)
    /// 켜진 버튼의 아이콘 색 (연한 바탕 위에서 잘 보이는 진한 주황)
    static let accentStrong = Color(red: 0.93, green: 0.50, blue: 0.16)
}

/// 목록 왼쪽의 둥근 사각 아이콘 (기본 캐릭터는 코드로 그리고, 내 캐릭터는 원본 그림)
private struct CharacterThumbnail: View {
    let entry: CharacterLibrary.Entry
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(background)
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
            content
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private var content: some View {
        switch entry.source {
        case .builtIn(let style):
            // 기본 캐릭터는 80pt 펫 창 크기로 그려지므로 그 크기로 그린 뒤 축소 (CSS transform: scale)
            DefaultCharacterView(style: style, action: .idle, facing: .right, time: 1.3, actionTime: 1.3)
                .frame(width: LoadedCharacter.defaultSize.width, height: LoadedCharacter.defaultSize.height)
                .scaleEffect(0.46 * size / 38)
                .frame(width: size, height: size)
        case .pack(let folder):
            if let image = NSImage(contentsOf: folder.appendingPathComponent("source.png")) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(4)
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
    }

    private var background: Color {
        switch entry.source {
        case .builtIn(let style): return style.palette.bodyTop.opacity(0.35)
        case .pack: return Color.white.opacity(0.7)
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
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.gradient)
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 24, height: 24)
            .hint("\(kind.subtitle) 알림")
            Text(kind.title).font(.system(size: 13, weight: .medium))
            Spacer()
            if !available {
                Text("설치 안 됨").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                // 상태가 글자로 바로 보이는 버튼: 켜짐(✓ 연결됨) = 진한 주황, 꺼짐(연결) = 회색 — 다른 칩과 같은 규칙
                Button { needsUpdate ? onUpdate() : onToggle(!installed) } label: {
                    HStack(spacing: 3) {
                        Image(systemName: needsUpdate ? "arrow.triangle.2.circlepath" : installed ? "checkmark" : "link")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(installed ? Color.accentStrong : Color.primary.opacity(0.75))
                        Text(needsUpdate ? "업데이트" : installed ? "연결됨" : "연결")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(width: 74, height: 24)
                    .modifier(ControlSurface(on: installed, radius: 7))
                }
                .buttonStyle(.plain)
                .hint(needsUpdate ? "작업 중 표시용 항목 추가 (백업 후)"
                      : installed ? "누르면 연결 해제 (설정 파일 백업 후)" : "누르면 연결 (설정 파일 백업 후)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .opacity(available ? 1 : 0.5)
    }

    private var symbol: String {
        switch kind {
        case .claude: return "sparkles"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .zsh: return "terminal.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .claude: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: return Color(red: 0.25, green: 0.25, blue: 0.28)
        case .zsh: return Color(red: 0.20, green: 0.62, blue: 0.45)
        }
    }
}

/// 3칸 균등 칩 줄 (CSS grid-template-columns: repeat(3, 1fr))
private struct ChipRow<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        HStack(spacing: 6) { content }.padding(.horizontal, 16)
    }
}

/// 패널의 모든 버튼이 쓰는 공통 모양 (CSS로 치면 .btn / .btn.is-on 클래스)
/// - 기본: 회색 둥근 사각, 마우스 올리면 살짝 진하게
/// - 켜짐/선택: 연한 주황으로 채운 바탕 + 진한 글씨, 아이콘만 주황 (눈이 편하면서도 글씨는 또렷하게)
private struct ControlSurface: ViewModifier {
    var on = false
    var radius: CGFloat = 8
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(Color.primary.opacity(on ? 0.9 : 0.75))
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(on ? Color.accent.opacity(hovering ? 0.36 : 0.28)
                         : Color.primary.opacity(hovering ? 0.10 : 0.055)))
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
                    .foregroundStyle(on ? Color.accentStrong : Color.primary.opacity(0.75)) // 켜지면 아이콘만 주황
                Text(title).font(.system(size: 11, weight: on ? .semibold : .medium)).lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .modifier(ControlSurface(on: on))
        }
        .buttonStyle(.plain)
    }
}

/// 글자 없는 작은 아이콘 버튼 (내 캐릭터 편집용)
private struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 28, height: 24)
                .modifier(ControlSurface(radius: 7))
        }
        .buttonStyle(.plain)
        .hint(help)
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
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
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
        case .working: return .blue
        case .waiting: return Color(red: 0.92, green: 0.33, blue: 0.25)
        case .done: return .green
        case .error: return .orange
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
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.85)))
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
