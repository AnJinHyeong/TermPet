import AppKit
import Observation

/// 새 버전 확인 + Homebrew로 바로 업데이트.
/// - 확인: GitHub 최신 릴리스(tag "v0.3.1")와 지금 버전 비교. 앱 시작 때 + 6시간마다 + 메뉴의 버전 버튼.
/// - 업데이트: 앱과 따로 도는 쉘에서 `brew update && brew upgrade --cask termpet` → 끝나면 앱을 다시 연다.
///   (brew가 업그레이드하면서 이 앱을 종료하므로, 앱이 꺼져도 계속 돌 수 있게 nohup으로 떼어 놓는다)
/// React 비유: 폴링하는 커스텀 훅 + 상태 스토어(@Observable ≈ Zustand).
@MainActor
@Observable
final class AppUpdater {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)   // 새 버전 (예: "0.3.2")
        case updating
        case failed(String)
    }

    static let latestReleaseURL = URL(string: "https://api.github.com/repos/AnJinHyeong/TermPet/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/AnJinHyeong/TermPet/releases/latest")!

    private(set) var state: State = .idle
    let current: String
    private var timer: Timer?
    private var watchTask: Task<Void, Never>?

    init(current: String = AppInfo.version) {
        self.current = current
    }

    var availableVersion: String? {
        if case .available(let v) = state { return v }
        return nil
    }

    /// 앱 시작 후 조용히 확인하고, 6시간마다 다시
    func startPeriodicChecks() {
        Task { await check() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
    }

    func check() async {
        guard state != .updating, state != .checking else { return }
        state = .checking
        do {
            // 캐시 무시: 새 릴리스 직후에도 바로 보이게 (URLSession 기본 캐시가 예전 응답을 돌려줄 수 있음)
            var request = URLRequest(url: Self.latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("TermPet", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let tag = Self.tagName(from: data) else { state = .failed("버전 정보를 읽지 못했어요"); return }
            state = Self.isNewer(tag, than: current) ? .available(Self.normalized(tag)) : .upToDate
        } catch {
            state = .failed("인터넷 연결을 확인해 주세요")
        }
    }

    /// 업데이트 실행: brew가 있으면 brew로, 없으면 릴리스 페이지 열기
    func update() {
        guard let brew = Self.brewPath() else {
            NSWorkspace.shared.open(Self.releasesPage)
            return
        }
        state = .updating
        let home = FileManager.default.homeDirectoryForCurrentUser
        let log = home.appendingPathComponent(".termpet/update.log").path
        // 끝 표시 파일: brew가 끝나면 종료 코드를 적는다. 앱이 아직 살아 있으면(= brew가 앱을 끄지 않았으면) 이걸 보고 마무리
        let done = home.appendingPathComponent(".termpet/update.done")
        try? FileManager.default.removeItem(at: done)
        // 다시 열 앱: 이름("open -a TermPet")이 아니라 지금 실행 중인 앱의 경로로.
        // 이름으로 열면 같은 Mac에 있는 다른 TermPet.app(개발 빌드 등)이 열려서 예전 버전이 뜰 수 있다 (실제로 겪은 버그).
        // brew는 같은 자리(/Applications)에 새 버전을 넣으므로 이 경로가 곧 새 버전이다.
        let appPath = Bundle.main.bundlePath
        // 앱이 brew에 의해 종료돼도 계속 돌도록 nohup + 백그라운드. 성공·실패와 상관없이 마지막에 앱을 다시 연다.
        let script = """
        export PATH="\((brew as NSString).deletingLastPathComponent):/usr/bin:/bin:/usr/sbin:/sbin"
        export HOMEBREW_NO_ENV_HINTS=1
        { date; '\(brew)' update --quiet; '\(brew)' upgrade --cask termpet; rc=$?; echo "exit $rc"; } >> '\(log)' 2>&1
        echo "$rc" > '\(done.path)'
        sleep 1
        open \(Self.shellQuote(appPath))
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "nohup /bin/sh -c \(Self.shellQuote(script)) >/dev/null 2>&1 &"]
        do {
            try p.run()
        } catch {
            state = .failed("업데이트를 시작하지 못했어요")
            return
        }
        watchForFinish(done)
    }

    /// brew가 앱을 끄고 새 버전을 켜면 이 감시는 앱과 함께 사라진다.
    /// 앱이 계속 살아 있는 채로 brew가 끝났으면(이미 최신·실패·다른 앱이 켜짐 등) 여기서 결과를 정리한다.
    /// → "업데이트 중" 표시가 영원히 남지 않게. (Task 반복 ≈ setInterval 폴링)
    private func watchForFinish(_ done: URL) {
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            for _ in 0..<450 { // 2초 × 450 = 15분
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                if let text = try? String(contentsOf: done, encoding: .utf8),
                   let code = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    self.finish(exitCode: code)
                    return
                }
            }
            self?.state = .failed("업데이트가 끝나지 않았어요")
        }
    }

    private func finish(exitCode: Int32) {
        let installed = Self.installedVersion(at: Bundle.main.bundleURL)
        switch Self.outcome(exitCode: exitCode, running: current, installed: installed) {
        case .restart:
            relaunch()
        case .failed:
            state = .failed("업데이트하지 못했어요 (~/.termpet/update.log)")
        case .recheck:
            state = .idle
            Task { await check() }
        }
    }

    /// 디스크의 앱은 새 버전인데 지금 도는 건 예전 것 → 스스로 껐다 켜기 (켜는 쉘은 앱과 떨어져서 계속 돈다)
    private func relaunch() {
        let inner = "sleep 1; open " + Self.shellQuote(Bundle.main.bundlePath)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "nohup /bin/sh -c \(Self.shellQuote(inner)) >/dev/null 2>&1 &"]
        try? p.run()
        NSApp.terminate(nil)
    }

    // MARK: - 순수 함수 (테스트용)

    enum Outcome: Equatable {
        case restart   // 디스크에 새 버전이 깔렸는데 예전 것이 돌고 있음 → 다시 켜기
        case failed    // brew 실패
        case recheck   // 바뀐 게 없음 (이미 최신 등) → 다시 확인해서 표시를 맞춘다
    }

    /// brew가 끝났는데 앱이 아직 살아 있을 때 할 일
    nonisolated static func outcome(exitCode: Int32, running: String, installed: String?) -> Outcome {
        if let installed, isNewer(installed, than: running) { return .restart }
        return exitCode == 0 ? .recheck : .failed
    }

    /// 디스크에 있는 앱의 버전 (Bundle.main은 처음 읽은 값을 캐시하므로 Info.plist를 직접 읽는다)
    nonisolated static func installedVersion(at bundleURL: URL) -> String? {
        let plist = bundleURL.appendingPathComponent("Contents/Info.plist")
        return (NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"]) as? String
    }

    /// GitHub 응답 JSON에서 tag_name
    nonisolated static func tagName(from data: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["tag_name"] as? String
    }

    /// "v0.3.1" → "0.3.1"
    nonisolated static func normalized(_ version: String) -> String {
        version.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    /// 숫자 단위로 비교 ("0.10.0" > "0.9.9"). 개발 빌드("dev")는 업데이트 안내 안 함.
    nonisolated static func isNewer(_ latest: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int]? {
            let comps = normalized(s).split(separator: ".").map { Int($0) }
            return comps.contains(nil) || comps.isEmpty ? nil : comps.compactMap { $0 }
        }
        guard let a = parts(latest), let b = parts(current) else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    nonisolated static func brewPath() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    nonisolated static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
