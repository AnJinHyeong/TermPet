import SwiftUI

/// 코드로 그리는 기본 캐릭터 종류. 몸 모양·표정 로직은 같고 색과 장식(귀, 꼬리, 새싹)만 다르다.
enum BuiltInStyle: String, CaseIterable, Identifiable {
    case mallang, cat, bunny, sprout

    var id: String { "builtin.\(rawValue)" }

    var name: String {
        switch self {
        case .mallang: return "말랑이"
        case .cat: return "냥이"
        case .bunny: return "토끼"
        case .sprout: return "새싹이"
        }
    }

    enum Accessory { case none, catEars, bunnyEars, sprout }

    struct Palette {
        var bodyTop: Color
        var bodyBase: Color
        var outline: Color
        var foot: Color
        var cheek: Color
    }

    var accessory: Accessory {
        switch self {
        case .mallang: return .none
        case .cat: return .catEars
        case .bunny: return .bunnyEars
        case .sprout: return .sprout
        }
    }

    var palette: Palette {
        switch self {
        case .mallang:
            return Palette(bodyTop: Color(red: 1.00, green: 0.86, blue: 0.58),
                           bodyBase: Color(red: 0.98, green: 0.72, blue: 0.40),
                           outline: Color(red: 0.55, green: 0.32, blue: 0.15),
                           foot: Color(red: 0.86, green: 0.55, blue: 0.28),
                           cheek: .pink)
        case .cat:
            return Palette(bodyTop: Color(red: 0.90, green: 0.90, blue: 0.92),
                           bodyBase: Color(red: 0.68, green: 0.69, blue: 0.73),
                           outline: Color(red: 0.30, green: 0.31, blue: 0.36),
                           foot: Color(red: 0.97, green: 0.97, blue: 0.98),
                           cheek: Color(red: 1.0, green: 0.55, blue: 0.65))
        case .bunny:
            return Palette(bodyTop: Color(red: 1.00, green: 0.98, blue: 0.98),
                           bodyBase: Color(red: 0.98, green: 0.86, blue: 0.89),
                           outline: Color(red: 0.58, green: 0.36, blue: 0.43),
                           foot: Color(red: 0.96, green: 0.76, blue: 0.81),
                           cheek: Color(red: 1.0, green: 0.5, blue: 0.6))
        case .sprout:
            return Palette(bodyTop: Color(red: 0.84, green: 0.96, blue: 0.74),
                           bodyBase: Color(red: 0.56, green: 0.82, blue: 0.45),
                           outline: Color(red: 0.24, green: 0.44, blue: 0.19),
                           foot: Color(red: 0.44, green: 0.68, blue: 0.33),
                           cheek: Color(red: 1.0, green: 0.55, blue: 0.5))
        }
    }

    static func from(id: String) -> BuiltInStyle? {
        allCases.first { $0.id == id }
    }
}
