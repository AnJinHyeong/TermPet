import SwiftUI

/// 말풍선 표시 상태. `@Observable` ≈ Zustand 스토어.
@Observable
final class BubbleViewModel {
    var content = BubbleContent(title: "", body: "")
    var kind: PetEvent.Kind = .done
    var badge = 0
    var tailX: CGFloat = 60
    var tailOnTop = false
}

/// 말풍선 레이아웃 상수 (클릭 영역 계산에서도 같이 씀)
enum BubbleMetrics {
    /// 그림자용 바깥 여백
    static let outerPadding: CGFloat = 8
    static let tailHeight: CGFloat = 9
    static let maxWidth: CGFloat = 240
    static let closeSize: CGFloat = 22
}

struct BubbleView: View {
    let model: BubbleViewModel

    private var accent: Color {
        switch model.kind {
        case .done: return Color(red: 0.16, green: 0.62, blue: 0.36)
        case .error: return Color(red: 0.85, green: 0.25, blue: 0.22)
        case .ask: return Color(red: 0.22, green: 0.47, blue: 0.92)
        }
    }

    private var icon: String {
        switch model.kind {
        case .done: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .ask: return "hand.raised.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(model.content.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if model.badge > 0 {
                    Text("+\(model.badge)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(accent))
                }
                // 닫기 버튼 모양 (실제 클릭 판정은 BubbleController에서 좌표로 처리)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.35))
                    .frame(width: 14, height: 14)
            }
            .foregroundStyle(accent)

            Text(model.content.body)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.13, green: 0.12, blue: 0.11))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = model.content.detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.black.opacity(0.5))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(minWidth: 120, maxWidth: BubbleMetrics.maxWidth - BubbleMetrics.outerPadding * 2,
               alignment: .leading)
        .padding(.top, model.tailOnTop ? BubbleMetrics.tailHeight : 0)
        .padding(.bottom, model.tailOnTop ? 0 : BubbleMetrics.tailHeight)
        .background(
            BubbleShape(tailX: model.tailX - BubbleMetrics.outerPadding,
                        tailOnTop: model.tailOnTop, tailHeight: BubbleMetrics.tailHeight)
                .fill(Color.white)
                .overlay(
                    BubbleShape(tailX: model.tailX - BubbleMetrics.outerPadding,
                                tailOnTop: model.tailOnTop, tailHeight: BubbleMetrics.tailHeight)
                        .stroke(accent.opacity(0.55), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        )
        .padding(BubbleMetrics.outerPadding)
        .fixedSize()
    }
}

/// 둥근 사각형 + 꼬리 모양. `Shape` ≈ SVG path를 만드는 함수형 컴포넌트.
struct BubbleShape: Shape {
    var tailX: CGFloat
    var tailOnTop: Bool
    var tailHeight: CGFloat
    var radius: CGFloat = 12
    var tailHalfWidth: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        let body = tailOnTop
            ? CGRect(x: rect.minX, y: rect.minY + tailHeight, width: rect.width, height: rect.height - tailHeight)
            : CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tailHeight)
        let r = radius, hw = tailHalfWidth
        let tx = min(max(tailX, body.minX + r + hw), body.maxX - r - hw)

        // 외곽선을 한 붓으로 그려서 꼬리와 몸 사이에 선이 생기지 않게 한다 (시계 방향)
        var p = Path()
        p.move(to: CGPoint(x: body.minX + r, y: body.minY))
        if tailOnTop {
            p.addLine(to: CGPoint(x: tx - hw, y: body.minY))
            p.addLine(to: CGPoint(x: tx, y: rect.minY))
            p.addLine(to: CGPoint(x: tx + hw, y: body.minY))
        }
        p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY),
                 tangent2End: CGPoint(x: body.maxX, y: body.maxY), radius: r)
        p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY),
                 tangent2End: CGPoint(x: body.minX, y: body.maxY), radius: r)
        if !tailOnTop {
            p.addLine(to: CGPoint(x: tx + hw, y: body.maxY))
            p.addLine(to: CGPoint(x: tx, y: rect.maxY))
            p.addLine(to: CGPoint(x: tx - hw, y: body.maxY))
        }
        p.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY),
                 tangent2End: CGPoint(x: body.minX, y: body.minY), radius: r)
        p.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY),
                 tangent2End: CGPoint(x: body.maxX, y: body.minY), radius: r)
        p.closeSubpath()
        return p
    }
}
