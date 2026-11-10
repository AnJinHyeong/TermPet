import SwiftUI

/// 그림 한 장을 "인형극"처럼 움직이는 포즈 계산 (순수 로직).
/// 프레임 i/n 의 위상(phase)으로 계산해서 반복 재생 시 끊김 없이 이어지게 한다.
struct PuppetPose: Equatable {
    struct Overlay: Equatable {
        var text: String
        /// 캔버스 좌표 (좌상단 원점, pt)
        var center: CGPoint
        var fontSize: CGFloat
        var color: Color
        var opacity: Double
    }

    var lift: CGFloat = 0          // 위로 띄우기 (pt)
    var offsetX: CGFloat = 0
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var rotation: Double = 0       // 도
    var anchorTop = false          // true면 머리 쪽을 축으로 (잡혀서 대롱대롱)
    var tint: Color = .white       // colorMultiply 색 (흰색 = 원본 그대로)
    var shadow = true
    var overlays: [Overlay] = []
}

enum PuppetAnimator {
    /// 상태별 (프레임 수, fps)
    static let plan: [(PetAction, Int, Double)] = [
        (.idle, 8, 6), (.walk, 8, 10), (.talk, 6, 8), (.happy, 8, 12),
        (.angry, 6, 12), (.ask, 8, 8), (.sleep, 8, 4), (.dragged, 6, 8), (.fall, 4, 10), (.climb, 6, 8),
    ]

    struct Geometry: Equatable {
        var canvas: CGSize       // 프레임 크기 (pt)
        var character: CGSize    // 캐릭터 그림 표시 크기 (pt)
        var bottomMargin: CGFloat

        /// 캐릭터 그림 높이를 기준으로 위쪽 여유(점프·장식)와 옆 여유를 둔 캔버스
        static func make(imageSize: CGSize, characterHeight h: CGFloat = 72) -> Geometry {
            let w = (imageSize.width / max(imageSize.height, 1)) * h
            let canvasH = (h / 0.72).rounded()
            let canvasW = max(w * 1.8, canvasH * 0.7).rounded()
            return Geometry(canvas: CGSize(width: canvasW, height: canvasH),
                            character: CGSize(width: w, height: h),
                            bottomMargin: (canvasH * 0.04).rounded())
        }

        /// 가만히 있을 때 머리 꼭대기 y
        var headTop: CGFloat { canvas.height - bottomMargin - character.height }
        var centerX: CGFloat { canvas.width / 2 }
    }

    static func pose(for action: PetAction, frame i: Int, of n: Int, geometry g: Geometry) -> PuppetPose {
        let p = Double(i) / Double(max(n, 1))   // 0..<1
        let a = p * 2 * .pi
        let w = g.character.width, h = g.character.height
        var pose = PuppetPose()

        switch action {
        case .idle:
            pose.scaleY = 1 + 0.025 * sin(a)
            pose.scaleX = 1 - 0.012 * sin(a)

        case .walk:
            pose.lift = abs(sin(a)) * h * 0.05
            pose.rotation = sin(a) * 3

        case .talk:
            pose.lift = abs(sin(a * 2)) * h * 0.02
            let dots = String(repeating: "•", count: 1 + i % 3)
            pose.overlays = [.init(text: dots, center: CGPoint(x: g.centerX + w * 0.6, y: g.headTop + h * 0.05),
                                   fontSize: h * 0.16, color: .gray, opacity: 0.9)]

        case .happy:
            let j = abs(sin(a))
            pose.lift = j * h * 0.16
            if j < 0.2 { pose.scaleY = 0.94; pose.scaleX = 1.05 }
            pose.overlays = [(-1.0, 0), (1.0, 1)].map { side, k in
                .init(text: "✦", center: CGPoint(x: g.centerX + side * w * 0.62, y: g.headTop + h * 0.12),
                      fontSize: h * 0.14, color: .yellow, opacity: 0.4 + 0.6 * abs(sin(a + Double(k))))
            }

        case .angry:
            pose.offsetX = sin(a * 2) * w * 0.04
            pose.tint = Color(red: 1, green: 0.72, blue: 0.72)
            pose.overlays = [.init(text: "💢", center: CGPoint(x: g.centerX + w * 0.45, y: g.headTop + h * 0.08),
                                   fontSize: h * (0.15 + 0.02 * sin(a * 2)), color: .red, opacity: 1)]

        case .ask:
            pose.rotation = sin(a) * 5
            pose.overlays = [.init(text: "?", center: CGPoint(x: g.centerX - w * 0.6, y: g.headTop + sin(a) * h * 0.03),
                                   fontSize: h * 0.2, color: Color(red: 0.25, green: 0.5, blue: 0.95), opacity: 1)]

        case .sleep:
            pose.scaleY = 0.98 + 0.02 * sin(a)
            pose.rotation = 4
            pose.tint = Color(red: 0.88, green: 0.88, blue: 0.96)
            pose.overlays = (0..<3).map { k in
                let q = (p + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                return .init(text: "z", center: CGPoint(x: g.centerX + w * 0.45 + q * w * 0.35,
                                                        y: g.headTop + h * 0.12 - q * h * 0.22),
                             fontSize: h * (0.09 + 0.07 * q), color: Color(white: 0.25), opacity: sin(q * .pi))
            }

        case .dragged:
            pose.anchorTop = true
            pose.rotation = sin(a) * 8
            pose.scaleY = 1.04
            pose.scaleX = 0.97
            pose.lift = h * 0.08
            pose.shadow = false

        case .fall:
            pose.scaleY = 1.06
            pose.scaleX = 0.96
            pose.rotation = sin(a) * 2
            pose.shadow = false

        case .climb:
            // 벽에 붙어 영차영차 (위아래로 들썩 + 좌우 기울기)
            pose.lift = h * 0.05 * (sin(a) + 1) / 2
            pose.rotation = sin(a) * 5
            pose.scaleX = 0.97 - 0.03 * sin(a)
            pose.shadow = false
        }
        return pose
    }
}

/// 포즈 하나를 그리는 SwiftUI 뷰 (ImageRenderer로 PNG 프레임이 된다)
struct PuppetFrameView: View {
    let image: CGImage
    let geometry: PuppetAnimator.Geometry
    let pose: PuppetPose

    var body: some View {
        let g = geometry
        let anchor: UnitPoint = pose.anchorTop ? .top : .bottom
        ZStack(alignment: .topLeading) {
            if pose.shadow {
                Ellipse()
                    .fill(Color.black.opacity(0.16))
                    .frame(width: g.character.width * 0.9, height: max(4, g.character.height * 0.06))
                    .position(x: g.centerX, y: g.canvas.height - g.bottomMargin)
            }
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: g.character.width, height: g.character.height)
                .colorMultiply(pose.tint)
                .scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: anchor)
                .rotationEffect(.degrees(pose.rotation), anchor: anchor)
                .position(x: g.centerX + pose.offsetX,
                          y: g.headTop + g.character.height / 2 - pose.lift)
            ForEach(Array(pose.overlays.enumerated()), id: \.offset) { _, o in
                Text(o.text)
                    .font(.system(size: o.fontSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(o.color)
                    .opacity(o.opacity)
                    .position(o.center)
            }
        }
        .frame(width: g.canvas.width, height: g.canvas.height)
    }
}
