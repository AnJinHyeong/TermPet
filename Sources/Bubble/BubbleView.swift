import AppKit
import SwiftUI

/// 말풍선 표시 상태. `@Observable` ≈ Zustand 스토어.
@Observable
final class BubbleViewModel {
    var content = BubbleContent(title: "", body: "")
    var kind: PetEvent.Kind = .done
    var badge = 0
    var tailX: CGFloat = 60
    var tailOnTop = false
    /// 말풍선 몸통 너비 (BubbleMetrics.bodyWidth로 계산해 고정)
    var width: CGFloat = 160

    /// 같은 값을 가진 독립 복사본 (높이 측정용)
    func snapshot() -> BubbleViewModel {
        let copy = BubbleViewModel()
        copy.content = content; copy.kind = kind; copy.badge = badge
        copy.tailX = tailX; copy.tailOnTop = tailOnTop; copy.width = width
        return copy
    }
}

/// 말풍선 레이아웃 상수 (클릭 영역 계산에서도 같이 씀)
enum BubbleMetrics {
    /// 그림자용 바깥 여백
    static let outerPadding: CGFloat = 8
    static let tailHeight: CGFloat = 9
    static let closeSize: CGFloat = 22
    /// 말풍선 몸통 너비 범위 (그림자 여백 제외)
    static let minBodyWidth: CGFloat = 140
    static let maxBodyWidth: CGFloat = 260
    static let horizontalPadding: CGFloat = 11

    static let titleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    static let bodyFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let detailFont = NSFont.systemFont(ofSize: 11, weight: .regular)

    /// 내용 길이에 맞춘 말풍선 너비. 짧으면 좁게, 길면 최대 너비에서 줄바꿈(최대 2줄 후 "…").
    /// SwiftUI에 "알아서" 맡기면 긴 텍스트의 이상적 너비가 창보다 커져 잘리므로 직접 정한다.
    static func bodyWidth(for content: BubbleContent, badge: Int,
                          measure: (String, NSFont) -> CGFloat = textWidth) -> CGFloat {
        // 제목 줄: 아이콘(10) + 간격 + 제목 + 간격 + [배지] + 닫기(14)
        let badgeWidth: CGFloat = badge > 0 ? measure("+\(badge)", .systemFont(ofSize: 10, weight: .bold)) + 10 + 4 : 0
        let titleLine = 12 + 4 + measure(content.title, titleFont) + 8 + badgeWidth + 14
        let bodyLine = measure(content.body, bodyFont)
        let detailLine = content.detail.map { measure($0, detailFont) } ?? 0
        let inner = max(titleLine, bodyLine, detailLine) + horizontalPadding * 2 + 2
        return min(max(inner.rounded(.up), minBodyWidth), maxBodyWidth)
    }

    static func textWidth(_ text: String, _ font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
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
                    .font(Font(BubbleMetrics.titleFont))
                    .lineLimit(1)
                    .truncationMode(.tail)
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

            // 길면 최대 2줄까지 보여주고 끝을 "…"로 자른다
            Text(model.content.body)
                .font(Font(BubbleMetrics.bodyFont))
                .foregroundStyle(Color(red: 0.13, green: 0.12, blue: 0.11))
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = model.content.detail {
                Text(detail)
                    .font(Font(BubbleMetrics.detailFont))
                    .foregroundStyle(Color.black.opacity(0.5))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, BubbleMetrics.horizontalPadding)
        .padding(.vertical, 8)
        // 너비를 고정 → 높이는 그 너비 기준으로 계산되어 창 크기와 내용이 항상 일치
        .frame(width: model.width, alignment: .leading)
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
        .fixedSize(horizontal: false, vertical: true)
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
