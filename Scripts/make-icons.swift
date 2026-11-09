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

let cream = Color(red: 1.00, green: 0.87, blue: 0.60)
let amber = Color(red: 0.99, green: 0.70, blue: 0.38)
let outline = Color(red: 0.42, green: 0.24, blue: 0.11)
let mint = Color(red: 0.47, green: 0.89, blue: 0.72)
let check = Color(red: 0.16, green: 0.62, blue: 0.36)

struct AppIconView: View {
    var body: some View {
        ZStack {
            // 그림자 + 배경 (Apple 아이콘 격자: 1024 캔버스 안에 824 크기 둥근 사각형)
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.24, green: 0.27, blue: 0.37),
                                              Color(red: 0.12, green: 0.13, blue: 0.20)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
            // 위쪽 은은한 하이라이트
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.0)],
                                             startPoint: .top, endPoint: .center), lineWidth: 6)
                .frame(width: 824, height: 824)

            // 터미널 프롬프트 ›_
            HStack(spacing: 10) {
                Text("›").font(.system(size: 150, weight: .heavy, design: .monospaced))
                RoundedRectangle(cornerRadius: 8).frame(width: 86, height: 22).offset(y: 46)
            }
            .foregroundStyle(mint)
            .position(x: 265, y: 255)

            // 바닥 그림자
            Ellipse().fill(.black.opacity(0.35)).frame(width: 470, height: 54).position(x: 512, y: 812)

            // 발
            ForEach([-1.0, 1.0], id: \.self) { side in
                Capsule().fill(Color(red: 0.86, green: 0.55, blue: 0.28))
                    .overlay(Capsule().stroke(outline, lineWidth: 14))
                    .frame(width: 110, height: 64)
                    .position(x: 512 + side * 120, y: 790)
            }

            // 몸
            BlobShape()
                .fill(LinearGradient(colors: [cream, amber], startPoint: .top, endPoint: .bottom))
                .overlay(BlobShape().stroke(outline, style: StrokeStyle(lineWidth: 18, lineJoin: .round)))
                .frame(width: 500, height: 410)
                .position(x: 512, y: 580)
            // 몸 광택
            Ellipse().fill(.white.opacity(0.45)).frame(width: 110, height: 60)
                .rotationEffect(.degrees(-25)).position(x: 380, y: 450)

            // 눈
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack {
                    Ellipse().fill(Color(red: 0.16, green: 0.10, blue: 0.07)).frame(width: 58, height: 78)
                    Circle().fill(.white).frame(width: 22, height: 22).offset(x: -9, y: -16)
                }
                .position(x: 512 + side * 92, y: 585)
            }
            // 볼
            ForEach([-1.0, 1.0], id: \.self) { side in
                Ellipse().fill(Color(red: 1.0, green: 0.45, blue: 0.55).opacity(0.55))
                    .frame(width: 78, height: 42).position(x: 512 + side * 170, y: 650)
            }
            // 입
            Path { p in
                p.move(to: CGPoint(x: 487, y: 640))
                p.addQuadCurve(to: CGPoint(x: 512, y: 652), control: CGPoint(x: 498, y: 656))
                p.addQuadCurve(to: CGPoint(x: 537, y: 640), control: CGPoint(x: 526, y: 656))
            }
            .stroke(outline, style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))

            // 말풍선 + 체크 (작업 끝났어!)
            ZStack {
                BubbleShape().fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                Image(systemName: "checkmark")
                    .font(.system(size: 120, weight: .black))
                    .foregroundStyle(check)
                    .offset(y: -22)
            }
            .frame(width: 270, height: 230)
            .position(x: 700, y: 300)
        }
        .frame(width: 1024, height: 1024)
    }
}

// MARK: - 메뉴바 아이콘 (18pt 템플릿: 검정 실루엣 + 눈은 뚫기)

struct MenuBarIconView: View {
    var body: some View {
        ZStack {
            BlobShape().fill(.black).frame(width: 16, height: 13).position(x: 9, y: 9.5)
            ForEach([-1.0, 1.0], id: \.self) { side in
                Capsule().fill(.black).frame(width: 4.2, height: 2.6).position(x: 9 + side * 4, y: 16.2)
            }
            ForEach([-1.0, 1.0], id: \.self) { side in
                Ellipse().frame(width: 2.4, height: 3.4).position(x: 9 + side * 3.2, y: 10)
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
            try writePNG(render(AppIconView(), scale: CGFloat(px) / 1024), appIcon.appendingPathComponent(name))
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
