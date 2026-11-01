import XCTest
@testable import omux

final class SidebarSizingTests: XCTestCase {
    func testMoreWindowSpaceDoesNotExpandSidebar() {
        for available in [720.0, 1240, 1920] {
            XCTAssertEqual(SidebarSizing.visible(preferred: 300, available: available), 300)
        }
    }

    func testTemporaryConstraintDoesNotReplacePreference() {
        let saved = 410.0
        XCTAssertEqual(SidebarSizing.visible(preferred: saved, available: 720), 354)
        XCTAssertEqual(SidebarSizing.visible(preferred: saved, available: 1240), saved)
    }

    func testInvalidPreferencesAndBounds() {
        XCTAssertEqual(SidebarSizing.preferred(.nan), 320)
        XCTAssertEqual(SidebarSizing.preferred(0), 320)
        XCTAssertEqual(SidebarSizing.preferred(200), 280)
        XCTAssertEqual(SidebarSizing.preferred(900), 420)
    }
}
