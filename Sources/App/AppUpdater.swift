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
            var request = URLRequest(url: Self.latestReleaseURL, timeoutInterval: 10)
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
        let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".termpet/update.log").path
        // 앱이 brew에 의해 종료돼도 계속 돌도록 nohup + 백그라운드. 성공·실패와 상관없이 마지막에 앱을 다시 연다.
        let script = """
        export PATH="\((brew as NSString).deletingLastPathComponent):/usr/bin:/bin:/usr/sbin:/sbin"
        export HOMEBREW_NO_ENV_HINTS=1
        { date; '\(brew)' update --quiet; '\(brew)' upgrade --cask termpet; echo "exit $?"; } >> '\(log)' 2>&1
        sleep 1
        open -a TermPet
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "nohup /bin/sh -c \(Self.shellQuote(script)) >/dev/null 2>&1 &"]
        do {
            try p.run()
        } catch {
            state = .failed("업데이트를 시작하지 못했어요")
        }
    }

    // MARK: - 순수 함수 (테스트용)

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
