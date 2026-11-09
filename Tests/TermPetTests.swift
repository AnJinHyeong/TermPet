import XCTest
@testable import TermPet

/// XCTest ≈ Jest. `test`로 시작하는 메서드가 각각 하나의 테스트 케이스.
final class TermPetTests: XCTestCase {
    func testAppVersionIsNotEmpty() {
        XCTAssertFalse(AppInfo.version.isEmpty)
    }
}
