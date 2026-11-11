import XCTest
@testable import TermPet

final class SingleInstanceTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1000)
    private func app(_ pid: Int32, _ version: String?, _ path: String = "/Applications/TermPet.app", launched: Double = 0) -> SingleInstance.Instance {
        .init(pid: pid, version: version, path: path, launchDate: t0.addingTimeInterval(launched))
    }

    func testAloneKeeps() {
        XCTAssertEqual(SingleInstance.decide(me: app(1, "0.5.3"), others: []), .keep(terminate: []))
    }

    func testNewVersionClosesOldOne() {
        // 업데이트 직후: 새 0.5.3 이 켜졌는데 예전 0.5.2 (다른 복사본) 가 살아 있음
        let old = app(10, "0.5.2", "/private/tmp/x/TermPet.app")
        XCTAssertEqual(SingleInstance.decide(me: app(20, "0.5.3", launched: 5), others: [old]), .keep(terminate: [10]))
        // 반대로 예전 것이 늦게 켜져도 예전 것이 물러난다
        XCTAssertEqual(SingleInstance.decide(me: old, others: [app(20, "0.5.3", launched: -5)]), .quit(winner: 20))
    }

    func testSameVersionPrefersInstalledThenEarliest() {
        let dev = app(30, "0.5.3", "/Users/me/TermPet/build/Build/Products/Debug/TermPet.app", launched: -100)
        let installed = app(40, "0.5.3", launched: 0)
        XCTAssertEqual(SingleInstance.decide(me: installed, others: [dev]), .keep(terminate: [30]))
        XCTAssertEqual(SingleInstance.decide(me: dev, others: [installed]), .quit(winner: 40))
        // 같은 자리·같은 버전이 거의 동시에 둘: 먼저 켜진 쪽이 남는다 (양쪽 판단이 같아야 둘 다 꺼지거나 둘 다 남지 않음)
        let a = app(50, "0.5.3", launched: 0), b = app(51, "0.5.3", launched: 0.2)
        XCTAssertEqual(SingleInstance.decide(me: a, others: [b]), .keep(terminate: [51]))
        XCTAssertEqual(SingleInstance.decide(me: b, others: [a]), .quit(winner: 50))
    }

    func testUnknownVersionLoses() {
        XCTAssertEqual(SingleInstance.decide(me: app(1, nil), others: [app(2, "0.5.2")]), .quit(winner: 2))
    }
}
