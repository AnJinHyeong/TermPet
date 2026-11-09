import AppKit
import SwiftUI

/// 메뉴바 아이콘을 누르면 뜨는 패널 (MenuBarExtra `.window` 스타일).
/// 구성: 헤더(앱 아이콘·이름·보이기 스위치) → 캐릭터 목록 → 표시 위치 타일 → 동작 타일 → 하단 안내·종료
/// React 비유: 작은 컴포넌트(Row, Tile)를 조합한 하나의 화면 컴포넌트.
struct MenuPanelView: View {
    let app: AppDelegate
    private var pet: PetController { app.petController }
    private var characters: CharacterLibrary { app.characters }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            PanelDivider()

            SectionLabel("캐릭터")
            VStack(spacing: 2) {
                ForEach(characters.entries) { entry in
                    CharacterRow(entry: entry, selected: entry.id == characters.selectedId) {
                        app.selectCharacter(entry.id)
                    }
                }
                if characters.custom == nil {
                    AddCharacterRow(title: "이미지로 캐릭터 만들기", subtitle: characters.problem ?? "그림 한 장이면 움직이는 펫이 돼요") {
                        closePanelThen { app.makeCharacterFromImage() }
                    }
                } else {
                    CustomActionsRow(
                        onReplace: { closePanelThen { app.makeCharacterFromImage() } },
                        onFlip: { app.flipCustomCharacter() },
                        onRemove: { app.removeCustomCharacter() })
                }
            }
            .padding(.horizontal, 8)

            SectionLabel("표시 위치")
            TileGrid {
                ForEach(PetWindowLayer.allCases) { layer in
                    Tile(symbol: layer.symbol, color: layerColor(layer), title: layer.shortTitle,
                         selected: pet.model.layer == layer) { pet.setLayer(layer) }
                        .help(layer.title)
                }
            }

            SectionLabel("놀기")
            TileGrid {
                let sleeping = pet.model.action == .sleep
                Tile(symbol: sleeping ? "sun.max.fill" : "moon.fill", color: .indigo,
                     title: sleeping ? "깨우기" : "재우기", selected: sleeping) { pet.toggleSleep() }
                Tile(symbol: "arrow.down.to.line", color: .green, title: "떨어뜨리기") { pet.dropFromTop() }
                Tile(symbol: "bubble.left.fill", color: .orange, title: "알림 테스트") {
                    pet.receive(PetEvent(source: .shell, kind: .done, message: "알림이 잘 보이나요?"))
                }
            }

            #if DEBUG
            SectionLabel("개발용")
            TileGrid {
                Tile(symbol: "face.smiling", color: .pink, title: "신남") { pet.react(.happy) }
                Tile(symbol: "flame.fill", color: .red, title: "화남") { pet.react(.angry) }
                Tile(symbol: "hand.raised.fill", color: .blue, title: "확인 요청") { pet.receive(.debugSample(.ask)) }
            }
            #endif

            PanelDivider().padding(.top, 6)
            footer
        }
        .frame(width: 300)
        .padding(.top, 4)
    }

    // MARK: - 헤더 / 푸터

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("텀펫").font(.system(size: 15, weight: .bold))
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
                .help(pet.model.isVisible ? "펫 숨기기" : "펫 보이기")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var footer: some View {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

    private func layerColor(_ layer: PetWindowLayer) -> Color {
        switch layer {
        case .aboveApps: return .blue
        case .desktop: return Color(red: 0.36, green: 0.62, blue: 0.62)
        case .desktopPopUp: return .orange
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
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)
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
}

private struct CharacterRow: View {
    let entry: CharacterLibrary.Entry
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CharacterThumbnail(entry: entry)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name).font(.system(size: 14, weight: .semibold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white, Color.accent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .modifier(HoverBackground(selected: selected))
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        switch entry.source {
        case .builtIn(let style):
            switch style {
            case .mallang: return "기본 · 말랑말랑 젤리"
            case .cat: return "기본 · 회색 고양이"
            case .bunny: return "기본 · 분홍 토끼"
            case .sprout: return "기본 · 새싹 친구"
            }
        case .pack: return "내 캐릭터 · 이미지로 만듦"
        }
    }
}

/// 목록 왼쪽의 둥근 사각 아이콘 (기본 캐릭터는 코드로 그리고, 내 캐릭터는 원본 그림)
private struct CharacterThumbnail: View {
    let entry: CharacterLibrary.Entry

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(background)
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
            content
        }
        .frame(width: 38, height: 38)
    }

    @ViewBuilder private var content: some View {
        switch entry.source {
        case .builtIn(let style):
            // 기본 캐릭터는 80pt 펫 창 크기로 그려지므로 그 크기로 그린 뒤 축소 (CSS transform: scale)
            DefaultCharacterView(style: style, action: .idle, facing: .right, time: 1.3, actionTime: 1.3)
                .frame(width: LoadedCharacter.defaultSize.width, height: LoadedCharacter.defaultSize.height)
                .scaleEffect(0.46)
                .frame(width: 38, height: 38)
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

private struct AddCharacterRow: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    Image(systemName: "plus").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.accent)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .modifier(HoverBackground(selected: false))
        }
        .buttonStyle(.plain)
    }
}

/// 내 캐릭터가 있을 때: 새 이미지로 바꾸기 / 방향 뒤집기 / 지우기
private struct CustomActionsRow: View {
    let onReplace: () -> Void
    let onFlip: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            pill("photo.badge.plus", "새 이미지로", action: onReplace)
            pill("arrow.left.and.right", "방향 바꾸기", action: onFlip)
            pill("trash", "지우기", action: onRemove)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private func pill(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .foregroundStyle(.primary.opacity(0.8))
            .modifier(HoverBackground(selected: false))
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }
}

/// 3열 타일 그리드 (CSS grid-template-columns: repeat(3, 1fr))
private struct TileGrid<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
            content
        }
        .padding(.horizontal, 8)
    }
}

private struct Tile: View {
    let symbol: String
    let color: Color
    let title: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color.gradient)
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)
                .shadow(color: color.opacity(0.3), radius: 2, y: 1)
                Text(title).font(.system(size: 12, weight: selected ? .bold : .medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .modifier(HoverBackground(selected: selected))
        }
        .buttonStyle(.plain)
    }
}
