import Foundation

/// 앱 메타 정보. `enum`을 케이스 없이 쓰면 인스턴스화 불가한 네임스페이스가 된다
/// (TS의 `export const AppInfo = { ... } as const` 같은 용도).
enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
