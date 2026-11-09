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

final class PetWindowLayerEffectiveTests: XCTestCase {
    func testPopUpModeRaisesOnlyWhileBubbleShowing() {
        XCTAssertEqual(PetWindowLayer.effective(.desktopPopUp, bubbleShowing: true), .aboveApps)
        XCTAssertEqual(PetWindowLayer.effective(.desktopPopUp, bubbleShowing: false), .desktopPopUp)
    }

    func testPlainDesktopNeverRaises() {
        XCTAssertEqual(PetWindowLayer.effective(.desktop, bubbleShowing: true), .desktop)
    }

    func testAboveAppsUnchanged() {
        XCTAssertEqual(PetWindowLayer.effective(.aboveApps, bubbleShowing: true), .aboveApps)
        XCTAssertEqual(PetWindowLayer.effective(.aboveApps, bubbleShowing: false), .aboveApps)
    }

    func testPopUpUsesDesktopLevelAtRest() {
        XCTAssertEqual(PetWindowLayer.desktopPopUp.windowLevel, PetWindowLayer.desktop.windowLevel)
        XCTAssertEqual(PetWindowLayer(rawValue: "desktopPopUp"), .desktopPopUp)
    }
}
