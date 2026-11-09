import AppKit
import Testing
@testable import TallyMic

@Suite("Panel placement")
struct PanelPlacementTests {
    private let screen = NSRect(x: 0, y: 0, width: 1512, height: 944)

    @Test func linesUpWithTheIconsRightEdge() {
        let icon = NSRect(x: 1000, y: 944, width: 30, height: 24)
        let origin = PanelPlacement.topLeft(below: icon, panelWidth: 320, in: screen)
        // The icon's right edge is at 1030, so a 320-point panel starts at 710.
        #expect(origin.x == 710)
        #expect(origin.y == 944 - PanelPlacement.gapBelowMenuBar)
    }

    @Test func staysOnScreenNearTheRightEdge() {
        let icon = NSRect(x: 1480, y: 944, width: 30, height: 24)
        let origin = PanelPlacement.topLeft(below: icon, panelWidth: 320, in: screen)
        #expect(origin.x + 320 == screen.maxX - PanelPlacement.screenMargin)
    }

    @Test func staysOnScreenNearTheLeftEdge() {
        let icon = NSRect(x: 10, y: 944, width: 30, height: 24)
        let origin = PanelPlacement.topLeft(below: icon, panelWidth: 320, in: screen)
        #expect(origin.x == PanelPlacement.screenMargin)
    }

    @Test func worksOnASecondScreenToTheLeft() {
        let second = NSRect(x: -1920, y: 0, width: 1920, height: 1055)
        let icon = NSRect(x: -100, y: 1055, width: 30, height: 24)
        let origin = PanelPlacement.topLeft(below: icon, panelWidth: 320, in: second)
        #expect(origin.x + 320 <= second.maxX - PanelPlacement.screenMargin)
        #expect(origin.x >= second.minX)
    }
}
