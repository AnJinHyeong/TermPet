import ServiceManagement

/// 로그인 시 자동 실행 (시스템 설정 → 일반 → 로그인 항목에 "텀펫"으로 보임)
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
