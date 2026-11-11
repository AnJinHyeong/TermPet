import AppKit

/// 텀펫은 한 번에 하나만 떠 있어야 한다 (펫 둘, 메뉴바 아이콘 둘, 알림 서버 포트 충돌 방지).
///
/// 두 개가 뜨는 경우 (실제로 겪음):
/// - 업데이트 때 brew가 앱을 "번들 ID로" 다시 켜는데, 같은 번들 ID의 다른 TermPet.app(개발 빌드·예전 복사본)이 켜짐
///   + 업데이트 스크립트가 /Applications 앱을 또 연다 → 버전이 다른 둘이 동시에 뜸
/// - 두 곳에서 거의 동시에 켜는 경우
///
/// 규칙: 새로 켜진 앱이 다른 텀펫을 보면 "누가 남을지"를 정한다. 모두 같은 규칙을 쓰므로 어느 쪽이 먼저 검사해도 결과가 같다.
///   1) 버전이 높은 쪽  2) /Applications 에 있는 쪽  3) 먼저 켜진 쪽  4) pid 가 작은 쪽
/// 진 쪽이 나 자신이면 조용히 종료, 다른 쪽이면 그 앱들을 종료시킨다.
/// React 비유: 탭 여러 개 중 하나만 "리더"가 되는 BroadcastChannel 리더 선출과 비슷.
enum SingleInstance {
    struct Instance: Equatable {
        var pid: Int32
        var version: String?
        var path: String
        var launchDate: Date?
    }

    enum Decision: Equatable {
        /// 내가 남는다. 이 pid 들은 종료시킨다 (비어 있으면 혼자)
        case keep(terminate: [Int32])
        /// 다른 앱이 남는다 → 나는 종료
        case quit(winner: Int32)
    }

    // MARK: - 순수 로직 (테스트용)

    static func decide(me: Instance, others: [Instance]) -> Decision {
        guard !others.isEmpty else { return .keep(terminate: []) }
        let all = [me] + others
        let winner = all.max { a, b in !wins(a, over: b) }!
        if winner.pid == me.pid { return .keep(terminate: others.map(\.pid)) }
        return .quit(winner: winner.pid)
    }

    /// a 가 b 보다 남을 자격이 있는지
    static func wins(_ a: Instance, over b: Instance) -> Bool {
        let va = a.version ?? "", vb = b.version ?? ""
        // 버전을 못 읽은 쪽은 진다 (읽을 수 있는 쪽이 정식 앱)
        let okA = AppUpdater.isNewer(va, than: "0"), okB = AppUpdater.isNewer(vb, than: "0")
        if okA != okB { return okA }
        if AppUpdater.isNewer(va, than: vb) { return true }
        if AppUpdater.isNewer(vb, than: va) { return false }
        let ia = isInstalled(a.path), ib = isInstalled(b.path)
        if ia != ib { return ia }
        let da = a.launchDate ?? .distantFuture, db = b.launchDate ?? .distantFuture
        if da != db { return da < db }
        return a.pid < b.pid
    }

    /// 정식 설치 위치(/Applications 또는 ~/Applications)에 있는 앱인지
    static func isInstalled(_ path: String) -> Bool {
        path.hasSuffix("/Applications/TermPet.app")
    }

    // MARK: - 실행

    /// 앱 시작 직후 호출. 내가 지면 false (호출한 쪽에서 바로 종료).
    /// 다른 텀펫을 종료시켰으면 그 앱이 알림 서버 포트를 놓을 때까지 `ready` 를 늦게 부른다.
    static func claim(ready: @escaping () -> Void) -> Bool {
        let current = NSRunningApplication.current
        guard let bundleId = Bundle.main.bundleIdentifier else { ready(); return true }
        // MCP 모드(`TermPet --mcp`)로 떠 있는 프로세스는 화면이 없어 activationPolicy 가 .prohibited → 건드리지 않는다
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .filter { $0.processIdentifier != current.processIdentifier && !$0.isTerminated && $0.activationPolicy != .prohibited }
        let me = Instance(pid: current.processIdentifier, version: AppInfo.version,
                          path: Bundle.main.bundlePath, launchDate: current.launchDate)
        let infos = others.map { app in
            Instance(pid: app.processIdentifier,
                     version: app.bundleURL.flatMap { AppUpdater.installedVersion(at: $0) },
                     path: app.bundleURL?.path ?? "", launchDate: app.launchDate)
        }
        switch decide(me: me, others: infos) {
        case .quit(let winner):
            NSLog("[TermPet] another TermPet (pid \(winner)) wins — quitting \(me.version ?? "?") at \(me.path)")
            return false
        case .keep(let losers):
            guard !losers.isEmpty else { ready(); return true }
            NSLog("[TermPet] closing older/duplicate TermPet pids \(losers)")
            let apps = others.filter { losers.contains($0.processIdentifier) }
            apps.forEach { $0.terminate() }
            // 정상 종료를 최대 3초 기다리고, 그래도 남아 있으면 강제 종료 → 그다음 서버 시작
            func wait(_ tries: Int) {
                let alive = apps.filter { !$0.isTerminated }
                if alive.isEmpty || tries == 0 {
                    alive.forEach { $0.forceTerminate() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + (alive.isEmpty ? 0 : 0.5), execute: ready)
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { wait(tries - 1) }
            }
            wait(12)
            return true
        }
    }
}
