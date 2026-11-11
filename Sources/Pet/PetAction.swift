import CoreGraphics

/// 펫의 현재 행동(=애니메이션 상태).
/// Swift `enum` ≈ TS의 문자열 유니온 타입(`'idle' | 'walk' | ...`)인데, `switch`에서 모든 케이스를
/// 처리하지 않으면 컴파일 에러가 나서 빠뜨릴 걱정이 없다.
/// `: String`을 붙이면 각 케이스가 "idle" 같은 문자열 값을 갖는다(캐릭터 팩 JSON 키와 매칭용).
enum PetAction: String, CaseIterable {
    case idle      // 가만히
    case walk      // 걷기
    case talk      // 말풍선 표시 중
    case happy     // 신남 (작업 완료)
    case angry     // 화남 (에러)
    case ask       // 확인 요청 / 손 흔들기
    case sleep     // 졸기
    case dragged   // 마우스로 잡혀 있음
    case fall      // 떨어지는 중 (점프·던져짐 포함)
    case climb     // 창/화면 벽을 기어오르는 중
    case bite      // 장난꾸러기 모드: 포인터를 물고 흔드는 중 (그림이 없으면 angry)
    case toss = "throw" // 장난꾸러기 모드: 포인터를 던진 직후 (그림이 없으면 happy). `throw`는 Swift 예약어라 이름만 toss

    /// 이벤트로 잠깐 표시되고 시간이 지나면 idle로 돌아가는 상태들
    var isReaction: Bool {
        switch self {
        case .talk, .happy, .angry, .ask: return true
        default: return false
        }
    }

    /// 메뉴에 보일 이름
    var title: String {
        switch self {
        case .idle: return "가만히 있을 때"
        case .walk: return "걸을 때"
        case .talk: return "말할 때"
        case .happy: return "신날 때 (작업 완료)"
        case .angry: return "화날 때 (에러)"
        case .ask: return "권한 요청할 때"
        case .sleep: return "잘 때"
        case .dragged: return "잡혔을 때"
        case .fall: return "떨어질 때"
        case .climb: return "벽 오를 때"
        case .bite: return "포인터 물 때"
        case .toss: return "포인터 던질 때"
        }
    }

    /// 사용자가 잡고 있거나 떨어지는 중 → 다른 입력으로 끊으면 안 되는 상태
    var isPhysicsControlled: Bool {
        self == .dragged || self == .fall || self == .climb
    }
}

/// 걷는 방향 / 바라보는 방향
enum Direction: Equatable {
    case left, right

    /// x 이동에 곱할 부호 (left = -1, right = +1)
    var sign: CGFloat { self == .left ? -1 : 1 }

    var flipped: Direction { self == .left ? .right : .left }
}
