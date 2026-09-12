import Foundation
import CoreGraphics

public enum PanelPlacement {
    /// AppKit screen coordinates, in points. Screens may have negative origins.
    public static func frame(anchor: CGRect?, visibleFrame: CGRect, contentSize: CGSize,
                             margin: CGFloat = 8, gap: CGFloat = 6) -> CGRect {
        let safe = visibleFrame.insetBy(dx: margin, dy: margin)
        let width = min(max(1, contentSize.width), max(1, safe.width))
        let height = min(max(1, contentSize.height), max(1, safe.height))
        let proposedX = anchor.map { $0.midX - width / 2 } ?? (safe.maxX - width)
        let top = min(anchor.map { $0.minY - gap } ?? safe.maxY, safe.maxY)
        let x = min(max(proposedX, safe.minX), safe.maxX - width)
        let y = min(max(top - height, safe.minY), safe.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
