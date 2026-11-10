import SwiftUI

/// 커스텀 캐릭터 팩(스프라이트 시트) 렌더러.
/// 현재 상태의 프레임 이미지를 골라서 보여주기만 한다 (CSS sprite + background-position과 같은 원리).
struct SpriteCharacterView: View {
    let sprite: SpriteCharacter
    let action: PetAction
    var variant: Int = 0
    let facing: Direction
    let actionTime: TimeInterval

    var body: some View {
        if let anim = sprite.animation(for: action, variant: variant),
           let frame = sprite.frame(for: action, variant: variant, elapsed: actionTime) {
            // 그림이 바라보는 방향과 이동 방향이 다르면 좌우 반전 ("front"면 반전 안 함)
            let flip = anim.facing == "front" ? false : (facing == .left) != (anim.facing == "left")
            Image(decorative: frame, scale: 1)
                // pixelArt면 확대 시 보간 끔(nearest neighbor) → 도트가 흐려지지 않음
                .interpolation(sprite.pixelArt ? .none : .high)
                .resizable()
                .scaledToFit()
                .scaleEffect(x: flip ? -1 : 1, y: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        } else {
            Color.clear
        }
    }
}
