// 앱 아이콘 + 메뉴바 아이콘 생성기.  실행: swift Scripts/make-icons.swift
// 결과: Resources/Assets.xcassets/{AppIcon.appiconset, MenuBarIcon.imageset}
// 그림은 전부 코드(SwiftUI 도형)로 그린다 — 외부 이미지 없음.
import AppKit
import SwiftUI

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Resources/Assets.xcassets")

// MARK: - 앱 아이콘 (1024 기준 좌표)

/// 말랑이: 아래가 평평하고 위가 둥근 젤리 몸
struct BlobShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: r.minX + w * 0.10, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.55),
                   control1: CGPoint(x: r.minX + w * 0.01, y: r.maxY),
                   control2: CGPoint(x: r.minX, y: r.minY + h * 0.80))
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY),
                   control1: CGPoint(x: r.minX, y: r.minY + h * 0.18),
                   control2: CGPoint(x: r.minX + w * 0.22, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + h * 0.55),
                   control1: CGPoint(x: r.maxX - w * 0.22, y: r.minY),
                   control2: CGPoint(x: r.maxX, y: r.minY + h * 0.18))
        p.addCurve(to: CGPoint(x: r.maxX - w * 0.10, y: r.maxY),
                   control1: CGPoint(x: r.maxX, y: r.minY + h * 0.80),
                   control2: CGPoint(x: r.maxX - w * 0.01, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// 말풍선: 둥근 사각형 + 왼쪽 아래 꼬리
struct BubbleShape: Shape {
    func path(in r: CGRect) -> Path {
        let body = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.80)
        var p = Path(roundedRect: body, cornerRadius: body.height * 0.34, style: .continuous)
        var tail = Path()
        tail.move(to: CGPoint(x: body.minX + body.width * 0.22, y: body.maxY - 4))
        tail.addLine(to: CGPoint(x: body.minX + body.width * 0.10, y: r.maxY))
        tail.addLine(to: CGPoint(x: body.minX + body.width * 0.44, y: body.maxY - 4))
        tail.closeSubpath()
        p.addPath(tail)
        return p
    }
}

// 파스텔 팔레트 (메뉴 패널 Theme와 같은 색)
let butter = Color(red: 1.00, green: 0.91, blue: 0.66)
let peach = Color(red: 1.00, green: 0.80, blue: 0.80)
let bunnyFur = Color(red: 1.00, green: 0.96, blue: 0.84)
let blush = Color(red: 0.96, green: 0.56, blue: 0.66)
let cocoa = Color(red: 0.36, green: 0.25, blue: 0.20)
let mint = Color(red: 0.62, green: 0.92, blue: 0.78)

/// 귀 하나: 바깥 털 + 안쪽 분홍
struct Ear: View {
    var line: CGFloat = 16
    var body: some View {
        ZStack {
            Capsule().fill(bunnyFur)
                .overlay(Capsule().stroke(cocoa, lineWidth: line))
            Capsule().fill(blush.opacity(0.55)).padding(.horizontal, 26).padding(.vertical, 40).offset(y: 18)
        }
        .frame(width: 104, height: 280)
    }
}

/// 앱 아이콘: 터미널 창 위에 올라앉은 말랑 토끼 (창 위를 걸어 다니는 펫)
/// simple: 16·32px용 — 장식(반짝이·하트·광택·창 단추) 빼고 선을 굵게, 그림을 크게 (작으면 뭉개지므로)
struct AppIconView: View {
    var simple = false
    private var line: CGFloat { simple ? 34 : 18 }

    var body: some View {
        ZStack {
            content
        }
        .scaleEffect(simple ? 1.17 : 1)
        .frame(width: 1024, height: 1024)
    }

    @ViewBuilder private var content: some View {
        ZStack {
            // 배경 (Apple 아이콘 격자: 1024 캔버스 안에 824 크기 둥근 사각형)
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [butter, peach], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 824, height: 824)
                .shadow(color: cocoa.opacity(0.28), radius: 18, y: 10)
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0)],
                                             startPoint: .top, endPoint: .center), lineWidth: 8)
                .frame(width: 824, height: 824)
            // 반짝이 장식
            if !simple {
            ForEach(Array([(250.0, 250.0, 64.0), (790.0, 300.0, 44.0), (800.0, 470.0, 28.0)].enumerated()), id: \.offset) { _, p in
                Image(systemName: "sparkle").font(.system(size: p.2, weight: .bold))
                    .foregroundStyle(.white).position(x: p.0, y: p.1)
            }
            Image(systemName: "heart.fill").font(.system(size: 50)).foregroundStyle(blush)
                .rotationEffect(.degrees(-14)).position(x: 238, y: 470)
            }

            // 귀 (몸 뒤)
            Ear(line: simple ? 30 : 16).rotationEffect(.degrees(-9)).position(x: 445, y: 270)
            Ear(line: simple ? 30 : 16).rotationEffect(.degrees(11)).position(x: 590, y: 272)

            // 터미널 창
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 56, style: .continuous).fill(cocoa)
                if !simple {
                HStack(spacing: 16) {
                    Circle().fill(blush).frame(width: 30, height: 30)
                    Circle().fill(butter).frame(width: 30, height: 30)
                    Circle().fill(mint).frame(width: 30, height: 30)
                }
                .padding(.leading, 44).padding(.top, 108)
                }
                HStack(spacing: 14) {
                    Text("›").font(.system(size: 130, weight: .heavy, design: .rounded))
                    RoundedRectangle(cornerRadius: 9).frame(width: 84, height: 22).offset(y: 44)
                }
                .foregroundStyle(mint)
                .padding(.leading, 60).padding(.top, 150)
            }
            .frame(width: 600, height: 330)
            .position(x: 512, y: 718)

            // 몸 (창 윗변에 앉음)
            Ellipse().fill(bunnyFur)
                .overlay(Ellipse().stroke(cocoa, lineWidth: line))
                .frame(width: 400, height: 320)
                .position(x: 517, y: 432)
            // 몸 광택
            if !simple {
                Ellipse().fill(.white.opacity(0.7)).frame(width: 90, height: 48)
                    .rotationEffect(.degrees(-25)).position(x: 405, y: 345)
            }
            // 눈
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack {
                    Ellipse().fill(cocoa).frame(width: simple ? 60 : 40, height: simple ? 72 : 50)
                    if !simple { Circle().fill(.white).frame(width: 15, height: 15).offset(x: -6, y: -10) }
                }
                .position(x: 517 + side * 70, y: 430)
            }
            // 볼
            ForEach([-1.0, 1.0], id: \.self) { side in
                Ellipse().fill(blush.opacity(0.7)).frame(width: 74, height: 40).position(x: 517 + side * 128, y: 478)
            }
            // 입 (ω)
            Path { p in
                p.move(to: CGPoint(x: 489, y: 466))
                p.addQuadCurve(to: CGPoint(x: 517, y: 470), control: CGPoint(x: 500, y: 488))
                p.addQuadCurve(to: CGPoint(x: 545, y: 466), control: CGPoint(x: 534, y: 488))
            }
            .stroke(cocoa, style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
            // 창 모서리에 걸친 앞발
            ForEach([-1.0, 1.0], id: \.self) { side in
                Ellipse().fill(bunnyFur)
                    .overlay(Ellipse().stroke(cocoa, lineWidth: simple ? 26 : 14))
                    .frame(width: 92, height: 70)
                    .position(x: 517 + side * 92, y: 572)
            }
        }
        .frame(width: 1024, height: 1024)
    }
}

// MARK: - 메뉴바 아이콘 (18pt 템플릿: 토끼 얼굴 실루엣 + 눈은 뚫기)

struct MenuBarIconView: View {
    var body: some View {
        ZStack {
            Capsule().fill(.black).frame(width: 3.6, height: 8.5).rotationEffect(.degrees(-10)).position(x: 6.6, y: 5.2)
            Capsule().fill(.black).frame(width: 3.6, height: 8.5).rotationEffect(.degrees(10)).position(x: 11.4, y: 5.2)
            Ellipse().fill(.black).frame(width: 15.5, height: 11.5).position(x: 9, y: 11.8)
            ForEach([-1.0, 1.0], id: \.self) { side in
                Ellipse().frame(width: 2.2, height: 2.8).position(x: 9 + side * 3, y: 11.6)
                    .blendMode(.destinationOut) // 눈 부분을 투명하게 뚫는다
            }
        }
        .compositingGroup()
        .frame(width: 18, height: 18)
    }
}

// MARK: - 저장

@MainActor
func render<V: View>(_ view: V, scale: CGFloat) -> CGImage {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    return renderer.cgImage!
}

func writePNG(_ image: CGImage, _ url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

@MainActor
func main() throws {
    let fm = FileManager.default
    let appIcon = assets.appendingPathComponent("AppIcon.appiconset")
    let menuIcon = assets.appendingPathComponent("MenuBarIcon.imageset")
    for d in [appIcon, menuIcon] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
    try #"{"info":{"author":"xcode","version":1}}"#.write(to: assets.appendingPathComponent("Contents.json"),
                                                        atomically: true, encoding: .utf8)

    var images: [String] = []
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let px = size * scale
            let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
            try writePNG(render(AppIconView(simple: px <= 32), scale: CGFloat(px) / 1024), appIcon.appendingPathComponent(name))
            images.append(#"{"idiom":"mac","size":"\#(size)x\#(size)","scale":"\#(scale)x","filename":"\#(name)"}"#)
        }
    }
    try #"{"images":[\#(images.joined(separator: ","))],"info":{"author":"xcode","version":1}}"#
        .write(to: appIcon.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

    var menuImages: [String] = []
    for scale in [1, 2, 3] {
        let name = "menubar\(scale == 1 ? "" : "@\(scale)x").png"
        try writePNG(render(MenuBarIconView(), scale: CGFloat(scale)), menuIcon.appendingPathComponent(name))
        menuImages.append(#"{"idiom":"universal","scale":"\#(scale)x","filename":"\#(name)"}"#)
    }
    try #"{"images":[\#(menuImages.joined(separator: ","))],"info":{"author":"xcode","version":1},"properties":{"template-rendering-intent":"template"}}"#
        .write(to: menuIcon.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

    // 미리보기 (확인용, 저장소엔 안 넣음)
    if let preview = ProcessInfo.processInfo.environment["ICON_PREVIEW_DIR"] {
        try writePNG(render(AppIconView(), scale: 0.5), URL(fileURLWithPath: preview).appendingPathComponent("appicon.png"))
        try writePNG(render(MenuBarIconView().background(Color.white), scale: 8),
                     URL(fileURLWithPath: preview).appendingPathComponent("menubar.png"))
    }
    print("ok")
}

try MainActor.assumeIsolated { try main() }
