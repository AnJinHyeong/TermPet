import Foundation
import CoreAudio
import Observation

/// "조용한 시간": 이 동안 알림은 말풍선을 띄우지 않고 쌓아두기만 한다 (펫 머리 위 "!"는 표시).
/// - 직접 켜기: 1시간 동안
/// - 회의 중 자동: 마이크를 어떤 앱이든 쓰고 있으면 (Zoom, Meet, Slack 허들 등)
/// `@Observable` ≈ Zustand 스토어. 메뉴 패널이 이 값을 읽어 타일 선택 상태를 그린다.
@Observable
final class QuietMode {
    /// 직접 켠 조용한 시간이 끝나는 시각 (nil = 꺼짐)
    private(set) var manualUntil: Date?
    /// 회의 중(마이크 사용 중) 자동으로 조용히
    var duringMeetings: Bool {
        didSet { defaults.set(duringMeetings, forKey: Self.meetingsKey); refresh() }
    }
    /// 권한 요청 알림에 소리 내기
    var soundOnAsk: Bool {
        didSet { defaults.set(soundOnAsk, forKey: Self.soundKey) }
    }
    private(set) var micInUse = false
    private(set) var isQuiet = false

    /// 조용한 시간이 켜지거나 꺼질 때 (꺼지면 쌓인 알림을 보여주기 위해)
    @ObservationIgnored var onChange: ((Bool) -> Void)?
    /// 테스트에서 가짜 마이크 상태를 넣기 위한 주입점
    @ObservationIgnored var micProbe: () -> Bool = QuietMode.isDefaultInputRunning
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let defaults: UserDefaults

    static let meetingsKey = "quietDuringMeetings"
    static let soundKey = "soundOnAsk"
    static let manualDuration: TimeInterval = 60 * 60

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        duringMeetings = defaults.object(forKey: Self.meetingsKey) as? Bool ?? false
        soundOnAsk = defaults.object(forKey: Self.soundKey) as? Bool ?? true
    }

    /// 순수 판단 로직 (테스트 대상)
    static func isQuiet(now: Date, manualUntil: Date?, duringMeetings: Bool, micInUse: Bool) -> Bool {
        if let until = manualUntil, now < until { return true }
        return duringMeetings && micInUse
    }

    var manualOn: Bool { manualUntil.map { Date() < $0 } ?? false }

    func toggleManual(now: Date = Date()) {
        manualUntil = manualOn ? nil : now.addingTimeInterval(Self.manualDuration)
        refresh(now: now)
    }

    /// 5초마다 마이크 상태와 1시간 만료를 확인 (CoreAudio 조회는 가벼움)
    func start() {
        refresh()
        timer?.invalidate()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 2 // 정확할 필요 없음 → 시스템이 다른 작업과 묶어 깨워 배터리 절약
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh(now: Date = Date()) {
        if let until = manualUntil, now >= until { manualUntil = nil }
        let mic = duringMeetings ? micProbe() : false
        if micInUse != mic { micInUse = mic }
        let quiet = Self.isQuiet(now: now, manualUntil: manualUntil, duringMeetings: duringMeetings, micInUse: mic)
        if quiet != isQuiet {
            isQuiet = quiet
            onChange?(quiet)
        }
    }

    /// 기본 입력 장치(마이크)를 지금 어떤 앱이든 쓰고 있는지.
    /// 소리를 녹음하는 게 아니라 장치 상태만 묻는 것이라 마이크 권한이 필요 없다.
    static func isDefaultInputRunning() -> Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return false }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }
}
