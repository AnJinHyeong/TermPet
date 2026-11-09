import SwiftUI

/// 이미지 에셋 없이 코드로 그리는 기본 캐릭터 (둥근 몸 + 눈 + 상태별 표정/모션).
///
/// SwiftUI `Canvas` ≈ HTML `<canvas>`의 2D context: 클로저 안에서 path를 만들어 fill/stroke 한다.
/// 매 프레임 `time`이 바뀌면 다시 그려진다 (React에서 props가 바뀌면 재렌더되는 것과 같음).
struct DefaultCharacterView: View {
    let action: PetAction
    let facing: Direction
    let time: TimeInterval
    let actionTime: TimeInterval

    var body: some View {
        Canvas { context, size in
            DefaultCharacterRenderer(action: action, facing: facing,
                                     t: time, at: actionTime, size: size)
                .draw(in: &context)
        }
    }
}

/// 실제 그리기 로직. 좌표: 좌상단 원점, y 아래로 증가 (SwiftUI/웹과 동일).
private struct DefaultCharacterRenderer {
    let action: PetAction
    let facing: Direction
    let t: Double   // 전역 애니메이션 시간
    let at: Double  // 현재 상태 경과 시간
    let size: CGSize

    // 팔레트
    private let bodyTop = Color(red: 1.00, green: 0.86, blue: 0.58)
    private let bodyBase = Color(red: 0.98, green: 0.72, blue: 0.40)
    private let angryBase = Color(red: 0.97, green: 0.50, blue: 0.40)
    private let outline = Color(red: 0.55, green: 0.32, blue: 0.15)
    private let footColor = Color(red: 0.86, green: 0.55, blue: 0.28)
    private let ink = Color(red: 0.20, green: 0.13, blue: 0.10)

    /// 상태별 몸 모양/위치 파라미터
    private struct Pose {
        var offsetY: CGFloat = 0     // 음수 = 위로 (점프, 통통 튀기)
        var shakeX: CGFloat = 0
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
        var footLift: (CGFloat, CGFloat) = (0, 0)
        var feetDangle = false
        var arms: Arms = .sides
        var showShadow = true
        enum Arms { case sides, up, wave }
    }

    private enum Eyes { case normal, happy, closed, wide, angry }
    private enum Mouth { case smile, grin, o, talk, frown, sleep }

    private var pose: Pose {
        var p = Pose()
        let breathe = CGFloat(sin(t * 2)) * 0.025
        switch action {
        case .idle, .talk:
            p.scaleY = 1 + breathe
            p.scaleX = 1 - breathe * 0.5
        case .walk:
            let s = CGFloat(sin(t * 10))
            p.offsetY = -abs(s) * 3
            p.footLift = (max(0, s) * 3, max(0, -s) * 3)
        case .happy:
            let jump = abs(sin(at * 9))
            p.offsetY = -CGFloat(jump) * 10
            if jump < 0.25 { p.scaleY = 0.94; p.scaleX = 1.04 } // 착지 순간 찌그러짐
            p.arms = .up
        case .angry:
            p.shakeX = CGFloat(sin(t * 45)) * 1.5
            p.scaleY = 0.97
            p.scaleX = 1.03
        case .ask:
            p.offsetY = CGFloat(sin(t * 4)) * 1.5
            p.arms = .wave
        case .sleep:
            let slow = CGFloat(sin(t * 1.2)) * 0.04
            p.scaleY = 0.94 + slow
            p.scaleX = 1.04 - slow * 0.5
        case .dragged:
            p.scaleX = 0.92
            p.scaleY = 1.10
            p.feetDangle = true
            p.arms = .up
            p.showShadow = false
        case .fall:
            p.scaleX = 0.95
            p.scaleY = 1.06
            p.feetDangle = true
            p.arms = .up
            p.showShadow = false
        }
        return p
    }

    private var eyes: Eyes {
        switch action {
        case .happy: return .happy
        case .sleep: return .closed
        case .dragged, .fall: return .wide
        case .angry: return .angry
        default: return .normal
        }
    }

    private var mouth: Mouth {
        switch action {
        case .idle, .walk: return .smile
        case .happy: return .grin
        case .talk: return .talk
        case .angry: return .frown
        case .ask, .dragged, .fall: return .o
        case .sleep: return .sleep
        }
    }

    // MARK: - draw

    func draw(in ctx: inout GraphicsContext) {
        let w = size.width, h = size.height
        let p = pose

        // 몸 영역 계산 (하단 정렬, 발 공간 10pt)
        let bw = 54 * p.scaleX, bh = 46 * p.scaleY
        let baseY = h - 10 + p.offsetY
        let body = CGRect(x: w / 2 - bw / 2 + p.shakeX, y: baseY - bh, width: bw, height: bh)

        if p.showShadow {
            let shrink = min(1, max(0.5, 1 + p.offsetY / 20))
            let sw = 40 * shrink
            ctx.fill(Path(ellipseIn: CGRect(x: w / 2 - sw / 2, y: h - 6, width: sw, height: 5)),
                     with: .color(.black.opacity(0.18)))
        }

        // 바라보는 방향으로 좌우 반전 (텍스트 오버레이는 반전하지 않으려고 사본 context에서 그림)
        var c = ctx
        if facing == .left {
            c.translateBy(x: w, y: 0)
            c.scaleBy(x: -1, y: 1)
        }
        let bodyRect = facing == .left
            ? CGRect(x: w - body.maxX, y: body.minY, width: body.width, height: body.height)
            : body

        drawFeet(&c, body: bodyRect, pose: p, h: h)
        drawBody(&c, body: bodyRect)
        drawArms(&c, body: bodyRect, pose: p)
        drawFace(&c, body: bodyRect)

        drawOverlays(&ctx, body: body)
    }

    private func drawFeet(_ c: inout GraphicsContext, body: CGRect, pose p: Pose, h: CGFloat) {
        for (i, dx) in [-11.0, 11.0].enumerated() {
            var y = h - 11 - (i == 0 ? p.footLift.0 : p.footLift.1)
            var x = body.midX + dx - 6.5
            if p.feetDangle {
                y = body.maxY - 3 + CGFloat(sin(t * 6 + Double(i) * .pi)) * 2
                x += CGFloat(i == 0 ? 2 : -2)
            }
            let foot = Path(roundedRect: CGRect(x: x, y: y, width: 13, height: 8), cornerRadius: 4)
            c.fill(foot, with: .color(footColor))
            c.stroke(foot, with: .color(outline), lineWidth: 1.5)
        }
    }

    private func drawBody(_ c: inout GraphicsContext, body: CGRect) {
        let shape = Path(roundedRect: body, cornerRadius: min(body.width, body.height) * 0.45)
        let base = action == .angry ? angryBase : bodyBase
        c.fill(shape, with: .linearGradient(
            Gradient(colors: [bodyTop, base]),
            startPoint: CGPoint(x: body.midX, y: body.minY),
            endPoint: CGPoint(x: body.midX, y: body.maxY)))
        c.stroke(shape, with: .color(outline), lineWidth: 2)
    }

    private func drawArms(_ c: inout GraphicsContext, body: CGRect, pose p: Pose) {
        let r: CGFloat = 5.5
        var hands: [CGPoint]
        switch p.arms {
        case .sides:
            hands = [CGPoint(x: body.minX + 1, y: body.midY + 8),
                     CGPoint(x: body.maxX - 1, y: body.midY + 8)]
        case .up:
            let wiggle = CGFloat(sin(t * 14)) * 1.5
            hands = [CGPoint(x: body.minX + 2, y: body.minY - 3 + wiggle),
                     CGPoint(x: body.maxX - 2, y: body.minY - 3 - wiggle)]
        case .wave:
            let a = sin(t * 12)
            hands = [CGPoint(x: body.minX + 1, y: body.midY + 8),
                     CGPoint(x: body.maxX + 3 + CGFloat(cos(t * 12)) * 2,
                             y: body.minY - 2 + CGFloat(a) * 4)]
        }
        for hand in hands {
            let path = Path(ellipseIn: CGRect(x: hand.x - r, y: hand.y - r, width: r * 2, height: r * 2))
            c.fill(path, with: .color(footColor))
            c.stroke(path, with: .color(outline), lineWidth: 1.5)
        }
    }

    private func drawFace(_ c: inout GraphicsContext, body: CGRect) {
        // 걷거나 서 있을 때 시선을 진행 방향으로 살짝 (좌우 반전은 context가 처리)
        let look: CGFloat = (action == .walk || action == .idle) ? 3 : 0
        let fx = body.midX + look
        let fy = body.minY + body.height * 0.45

        for side in [-1.0, 1.0] {
            drawEye(&c, center: CGPoint(x: fx + 9 * side, y: fy), side: side)
        }

        if action == .happy || action == .ask {
            for side in [-1.0, 1.0] {
                c.fill(Path(ellipseIn: CGRect(x: fx + 15 * side - 4, y: fy + 5, width: 8, height: 4)),
                       with: .color(.pink.opacity(0.55)))
            }
        }

        drawMouth(&c, center: CGPoint(x: fx, y: fy + 10))
    }

    private func drawEye(_ c: inout GraphicsContext, center e: CGPoint, side: Double) {
        let stroke = StrokeStyle(lineWidth: 2.2, lineCap: .round)
        switch eyes {
        case .normal:
            let blinking = t.truncatingRemainder(dividingBy: 3.7) < 0.12
            let eh: CGFloat = blinking ? 1.5 : 9
            c.fill(Path(ellipseIn: CGRect(x: e.x - 3, y: e.y - eh / 2, width: 6, height: eh)),
                   with: .color(ink))
            if !blinking {
                c.fill(Path(ellipseIn: CGRect(x: e.x - 0.5, y: e.y - 3, width: 2, height: 2)),
                       with: .color(.white))
            }
        case .happy: // ^ ^
            var path = Path()
            path.move(to: CGPoint(x: e.x - 4, y: e.y + 2))
            path.addQuadCurve(to: CGPoint(x: e.x + 4, y: e.y + 2), control: CGPoint(x: e.x, y: e.y - 5))
            c.stroke(path, with: .color(ink), style: stroke)
        case .closed: // ‿ ‿
            var path = Path()
            path.move(to: CGPoint(x: e.x - 4, y: e.y))
            path.addQuadCurve(to: CGPoint(x: e.x + 4, y: e.y), control: CGPoint(x: e.x, y: e.y + 4))
            c.stroke(path, with: .color(ink), style: stroke)
        case .wide:
            c.fill(Path(ellipseIn: CGRect(x: e.x - 5, y: e.y - 5, width: 10, height: 10)), with: .color(.white))
            c.stroke(Path(ellipseIn: CGRect(x: e.x - 5, y: e.y - 5, width: 10, height: 10)),
                     with: .color(ink), lineWidth: 1.5)
            c.fill(Path(ellipseIn: CGRect(x: e.x - 2, y: e.y - 2, width: 4, height: 4)), with: .color(ink))
        case .angry:
            c.fill(Path(ellipseIn: CGRect(x: e.x - 3, y: e.y - 2, width: 6, height: 6)), with: .color(ink))
            // 안쪽으로 내려가는 눈썹
            var brow = Path()
            brow.move(to: CGPoint(x: e.x + 5 * side, y: e.y - 8))
            brow.addLine(to: CGPoint(x: e.x - 4 * side, y: e.y - 4))
            c.stroke(brow, with: .color(ink), style: stroke)
        }
    }

    private func drawMouth(_ c: inout GraphicsContext, center m: CGPoint) {
        let stroke = StrokeStyle(lineWidth: 2, lineCap: .round)
        let mouthFill = Color(red: 0.75, green: 0.25, blue: 0.25)
        switch mouth {
        case .smile:
            var p = Path()
            p.move(to: CGPoint(x: m.x - 4, y: m.y))
            p.addQuadCurve(to: CGPoint(x: m.x + 4, y: m.y), control: CGPoint(x: m.x, y: m.y + 4))
            c.stroke(p, with: .color(ink), style: stroke)
        case .grin:
            var p = Path()
            p.move(to: CGPoint(x: m.x - 6, y: m.y - 1))
            p.addQuadCurve(to: CGPoint(x: m.x + 6, y: m.y - 1), control: CGPoint(x: m.x, y: m.y + 10))
            p.closeSubpath()
            c.fill(p, with: .color(mouthFill))
            c.stroke(p, with: .color(ink), lineWidth: 1.5)
        case .o:
            c.fill(Path(ellipseIn: CGRect(x: m.x - 2.5, y: m.y - 2, width: 5, height: 6)), with: .color(ink))
        case .talk:
            let open = 2 + 5 * CGFloat(abs(sin(t * 12)))
            c.fill(Path(ellipseIn: CGRect(x: m.x - 3, y: m.y - 1, width: 6, height: open)),
                   with: .color(mouthFill))
        case .frown:
            var p = Path()
            p.move(to: CGPoint(x: m.x - 4, y: m.y + 3))
            p.addQuadCurve(to: CGPoint(x: m.x + 4, y: m.y + 3), control: CGPoint(x: m.x, y: m.y - 2))
            c.stroke(p, with: .color(ink), style: stroke)
        case .sleep:
            let s = 2.5 + CGFloat(sin(t * 1.2)) * 0.8
            c.fill(Path(ellipseIn: CGRect(x: m.x - s / 2, y: m.y, width: s, height: s)), with: .color(ink))
        }
    }

    /// 몸 바깥 장식 (z z z, ?, 💢, 반짝이). 좌우 반전하지 않은 context에 그린다.
    private func drawOverlays(_ ctx: inout GraphicsContext, body: CGRect) {
        let sideX: CGFloat = facing == .right ? 1 : -1
        switch action {
        case .sleep:
            for i in 0..<3 {
                let phase = (t * 0.45 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let x = body.midX + sideX * (14 + CGFloat(phase) * 12)
                let y = body.minY - CGFloat(phase) * 20
                let text = Text("z").font(.system(size: 9 + CGFloat(phase) * 6, weight: .bold, design: .rounded))
                    .foregroundColor(ink.opacity(sin(phase * .pi)))
                ctx.draw(text, at: CGPoint(x: x, y: y))
            }
        case .ask:
            let bob = CGFloat(sin(t * 5)) * 2
            ctx.draw(Text("?").font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(red: 0.25, green: 0.5, blue: 0.95)),
                     at: CGPoint(x: body.midX - sideX * 14, y: body.minY - 10 + bob))
        case .angry:
            let pulse = 1 + 0.15 * sin(t * 10)
            ctx.draw(Text("💢").font(.system(size: 14 * pulse)),
                     at: CGPoint(x: body.midX + sideX * (body.width / 2 - 4), y: body.minY + 2))
        case .happy:
            for (i, pos) in [CGPoint(x: -24, y: -6), CGPoint(x: 24, y: -12)].enumerated() {
                let a = (sin(t * 8 + Double(i) * 2) + 1) / 2
                ctx.draw(Text("✦").font(.system(size: 10))
                            .foregroundColor(Color.yellow.opacity(0.4 + 0.6 * a)),
                         at: CGPoint(x: body.midX + pos.x, y: body.minY + pos.y))
            }
        default:
            break
        }
    }
}

#Preview {
    // Xcode 캔버스 미리보기 (Storybook 비슷). 실제 앱 동작과는 무관.
    HStack {
        ForEach(PetAction.allCases, id: \.self) { a in
            DefaultCharacterView(action: a, facing: .right, time: 1, actionTime: 0.1)
                .frame(width: 80, height: 80)
        }
    }
    .padding()
}
