import CoreGraphics

/// 말풍선 창 위치 계산 (순수 함수). AppKit 좌표계(좌하단 원점, y 위로 증가).
enum BubblePlacement {
    struct Result: Equatable {
        /// 말풍선 창의 좌하단 좌표
        var origin: CGPoint
        /// 꼬리 끝의 x (말풍선 창 기준 좌표)
        var tailX: CGFloat
        /// true면 펫 아래에 표시 (꼬리가 위쪽)
        var below: Bool
    }

    static let screenMargin: CGFloat = 4
    /// 펫 창 위쪽은 장식(zzz, ?)용 빈 공간이라 말풍선을 살짝 겹쳐 올린다
    static let overlap: CGFloat = 14
    /// 꼬리가 말풍선 모서리에 너무 붙지 않게
    static let tailInset: CGFloat = 24

    static func place(bubbleSize size: CGSize, petFrame pet: CGRect, screen: CGRect) -> Result {
        var x = pet.midX - size.width / 2
        x = min(max(x, screen.minX + screenMargin), screen.maxX - size.width - screenMargin)

        var y = pet.maxY - overlap
        var below = false
        if y + size.height > screen.maxY - screenMargin {
            // 위에 공간이 없으면(펫을 화면 꼭대기로 끌어올린 경우) 아래에
            below = true
            y = pet.minY - size.height + overlap / 2
        }

        let tailX = min(max(pet.midX - x, tailInset), size.width - tailInset)
        return Result(origin: CGPoint(x: x, y: y), tailX: tailX, below: below)
    }
}
