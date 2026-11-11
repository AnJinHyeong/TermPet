import AppKit

/// FocusAction을 실제로 실행 (NSWorkspace로 앱/폴더 열기).
@MainActor
enum ProjectFocuser {
    static func focus(_ event: PetEvent) {
        let action = FocusAction.plan(for: event) { ProjectRootFinder.find(from: $0) }
        perform(action)
    }

    static func perform(_ action: FocusAction) {
        let bundleId: String
        var folder: URL?
        var link: URL?
        switch action {
        case .none:
            return
        case .activate(let id):
            bundleId = id
        case .openURL(let url, let id):
            bundleId = id
            link = URL(string: url)
        case .openFolder(let id, let path):
            bundleId = id
            folder = URL(fileURLWithPath: path, isDirectory: true)
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            NSLog("[TermPet] app not found: \(bundleId)")
            return
        }

        // macOS 14+의 "협조적 활성화": 비활성 앱이 다른 앱을 앞으로 가져오려 하면 거부될 수 있다.
        // 사용자가 방금 클릭했으므로 TermPet을 잠깐 활성화한 뒤 대상 앱에 활성화를 양보한다.
        NSApp.activate()
        NSApp.yieldActivation(toApplicationWithBundleIdentifier: bundleId)

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if let link {
            // 앱 딥링크 → 그 대화로 바로 이동. 실패하면 앱만 앞으로
            NSWorkspace.shared.open(link, configuration: config) { _, error in
                guard let error else { return }
                NSLog("[TermPet] open link failed: \(error)")
                Task { @MainActor in perform(.activate(bundleId: bundleId)) }
            }
        } else if let folder {
            NSWorkspace.shared.open([folder], withApplicationAt: appURL, configuration: config) { _, error in
                if let error { NSLog("[TermPet] open folder failed: \(error)") }
            }
        } else {
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
                if let error { NSLog("[TermPet] activate failed: \(error)") }
            }
        }
    }
}
