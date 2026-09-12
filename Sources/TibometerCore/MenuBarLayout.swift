import Foundation

public struct MenuBarLayout: Equatable, Sendable {
    public let itemCount: Int
    public let style: MenuBarStyle
    public let height: Double = 22
    public var rowCount: Int { style.usesRings ? 1 : itemCount }
    public var rowHeight: Double { height / Double(rowCount) }
    public let fontSize: Double = 11.5
    public let barHeight: Double = 4
    public let ringDiameter: Double = 20
    public let ringLineWidth: Double = 2.5
    public let ringLabelFontSize: Double = 9.5
    public var ringSpacing: Double { style.showsPercentage ? 8 : 4 }
    public let ringPercentageSpacing: Double = 4

    public init?(itemCount: Int, style: MenuBarStyle) {
        guard (1...2).contains(itemCount) else { return nil }
        self.itemCount = itemCount
        self.style = style
    }

    public func centerY(forItem index: Int) -> Double {
        style.usesRings ? height / 2 : height - rowHeight * (Double(index) + 0.5)
    }

    public func ringItemWidth(percentageWidth: Double = 0) -> Double {
        ringDiameter + (style.showsPercentage ? ringPercentageSpacing + percentageWidth : 0)
    }

    public func ringsWidth(percentageWidth: Double = 0) -> Double {
        Double(itemCount) * ringItemWidth(percentageWidth: percentageWidth) + Double(itemCount - 1) * ringSpacing
    }

    public func centerX(forRing index: Int, percentageWidth: Double = 0) -> Double {
        ringDiameter / 2 + Double(index) * (ringItemWidth(percentageWidth: percentageWidth) + ringSpacing)
    }
}
