import Foundation
import CoreGraphics
import TibometerCore

final class PanelPlacementTests {
    func testPanelStaysBelowMenuBarWhenContentHeightChanges() {
        let visible = CGRect(x: 0, y: 50, width: 1512, height: 895)
        let anchor = CGRect(x: 1050, y: 945, width: 180, height: 37)
        let short = PanelPlacement.frame(anchor: anchor, visibleFrame: visible, contentSize: CGSize(width: 372, height: 490))
        let tall = PanelPlacement.frame(anchor: anchor, visibleFrame: visible, contentSize: CGSize(width: 372, height: 610))
        expectEqual(short.maxY, tall.maxY)
        expect(visible.contains(short))
        expect(visible.contains(tall))
        expectLess(tall.maxY, anchor.minY)
    }

    func testOversizedContentIsLimitedToScreen() {
        let visible = CGRect(x: 0, y: 40, width: 800, height: 510)
        let frame = PanelPlacement.frame(anchor: CGRect(x: 750, y: 550, width: 50, height: 24), visibleFrame: visible,
                                         contentSize: CGSize(width: 372, height: 900))
        expect(visible.contains(frame))
        expectEqual(frame.height, visible.height - 16)
        expectEqual(frame.maxX, visible.maxX - 8)
    }

    func testSecondaryDisplayUsesItsOwnOriginAndEdges() {
        for visible in [CGRect(x: -1920, y: 80, width: 1920, height: 970), CGRect(x: 200, y: -1080, width: 1600, height: 1010)] {
            for x in [visible.minX, visible.maxX - 50] {
                let anchor = CGRect(x: x, y: visible.maxY, width: 50, height: 24)
                let frame = PanelPlacement.frame(anchor: anchor, visibleFrame: visible, contentSize: CGSize(width: 372, height: 560))
                expect(visible.contains(frame))
                expectLess(frame.maxY, anchor.minY)
            }
        }
    }

    func testHiddenStatusItemCanStillOpenAtSafeScreenCorner() {
        let visible = CGRect(x: 0, y: 60, width: 1440, height: 800)
        let frame = PanelPlacement.frame(anchor: nil, visibleFrame: visible, contentSize: CGSize(width: 372, height: 560))
        expect(visible.contains(frame))
        expectEqual(frame.maxX, visible.maxX - 8)
        expectEqual(frame.maxY, visible.maxY - 8)
    }
}
