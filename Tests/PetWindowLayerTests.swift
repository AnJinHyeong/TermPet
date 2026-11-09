import XCTest
@testable import TermPet

final class PetWindowLayerTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "PetWindowLayerTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testDefaultsToAboveApps() {
        XCTAssertEqual(PetWindowLayer.load(from: defaults), .aboveApps)
    }

    func testSaveAndLoadRoundTrip() {
        PetWindowLayer.desktop.save(to: defaults)
        XCTAssertEqual(PetWindowLayer.load(from: defaults), .desktop)
    }

    func testInvalidStoredValueFallsBackToDefault() {
        defaults.set("bogus", forKey: PetWindowLayer.defaultsKey)
        XCTAssertEqual(PetWindowLayer.load(from: defaults), .aboveApps)
    }

    func testDesktopLayerIsBelowNormalWindowsAndAboveIcons() {
        let desktop = PetWindowLayer.desktop.windowLevel.rawValue
        XCTAssertLessThan(desktop, NSWindow.Level.normal.rawValue)
        XCTAssertGreaterThan(desktop, Int(CGWindowLevelForKey(.desktopIconWindow)))
        XCTAssertGreaterThan(PetWindowLayer.aboveApps.windowLevel.rawValue, NSWindow.Level.normal.rawValue)
    }
}
