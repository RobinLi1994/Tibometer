import AppKit
import CoreText
import TibometerCore

struct MenuBarRenderer: Equatable {
    let style: MenuBarStyle
    let items: [MenuBarPresentation.Item]
    let stale: Bool

    init(style: MenuBarStyle, bucket: RateBucket?, scope: MenuBarScope = .both, stale: Bool = false) {
        self.style = style
        items = MenuBarPresentation.items(in: bucket, scope: scope)
        self.stale = stale
    }

    func image() -> NSImage? {
        guard let layout = MenuBarLayout(itemCount: items.count, style: style) else { return nil }
        let font = NSFont.monospacedDigitSystemFont(ofSize: layout.fontSize, weight: .bold)
        let labelFont = style.usesRings
            ? NSFont.monospacedDigitSystemFont(ofSize: layout.ringLabelFontSize, weight: .bold)
            : font
        let labels = items.map { TextRun($0.window.shortTitle, font: labelFont) }
        let values = items.map { TextRun($0.percentageText, font: font) }
        let warning = TextRun("!", font: .systemFont(ofSize: 12, weight: .bold))
        let labelWidth = ceil(labels.map(\.width).max() ?? 0)
        let valueWidth = ceil((values + [TextRun("100%", font: font), TextRun("<1%", font: font)]).map(\.width).max() ?? 0)
        let graphicWidth: CGFloat = style.usesBars ? 32 : 0
        let gap: CGFloat = 5
        let warningWidth: CGFloat = stale ? 10 : 0
        let contentWidth: CGFloat
        if style.usesRings {
            contentWidth = layout.ringsWidth(percentageWidth: valueWidth)
        } else {
            contentWidth = labelWidth + (style.usesBars ? gap + graphicWidth : 0)
                + (style.showsPercentage ? gap + valueWidth : 0)
        }
        let size = NSSize(width: warningWidth + contentWidth + 2, height: layout.height)
        let image = NSImage(size: size, flipped: false) { bounds in
            if stale {
                warning.draw(left: 0, centerY: bounds.height / 2)
            }
            for (index, item) in items.enumerated() {
                let centerY = layout.centerY(forItem: index)
                let label = labels[index]
                let value = values[index]
                let startX = warningWidth + 1
                if style.usesRings {
                    let center = NSPoint(x: startX + layout.centerX(forRing: index, percentageWidth: valueWidth), y: centerY)
                    Self.drawRing(at: center, remainingPercent: item.remainingPercent, layout: layout)
                    label.draw(left: center.x - label.width / 2, centerY: centerY)
                    if style.showsPercentage {
                        let rightX = center.x + layout.ringDiameter / 2 + layout.ringPercentageSpacing + valueWidth
                        value.draw(left: rightX - value.width, centerY: centerY)
                    }
                    continue
                }
                label.draw(left: startX, centerY: centerY)
                if style.showsPercentage {
                    value.draw(left: startX + contentWidth - value.width, centerY: centerY)
                }
                if style.usesBars {
                    let rect = NSRect(x: startX + labelWidth + gap, y: centerY - layout.barHeight / 2,
                                      width: graphicWidth, height: layout.barHeight)
                    let track = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
                    NSColor.black.withAlphaComponent(0.25).setFill()
                    track.fill()
                    if item.remainingPercent > 0 {
                        NSGraphicsContext.saveGraphicsState()
                        track.addClip()
                        NSColor.black.setFill()
                        NSRect(x: rect.minX, y: rect.minY, width: rect.width * item.remainingPercent / 100, height: rect.height).fill()
                        NSGraphicsContext.restoreGraphicsState()
                    }
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private struct TextRun {
        let line: CTLine
        let bounds: CGRect
        var width: CGFloat { bounds.width }

        init(_ text: String, font: NSFont) {
            line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                .font: font, .foregroundColor: NSColor.black
            ]))
            bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        }

        func draw(left x: CGFloat, centerY: CGFloat) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.saveGState()
            context.textMatrix = .identity
            // Align using glyph bounds to fit the menu bar row.
            context.textPosition = CGPoint(x: x - bounds.minX, y: centerY - bounds.midY)
            CTLineDraw(line, context)
            context.restoreGState()
        }
    }

    private static func drawRing(at center: NSPoint, remainingPercent: Double, layout: MenuBarLayout) {
        let diameter = layout.ringDiameter
        let lineWidth = layout.ringLineWidth
        let rect = NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
            .insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let track = NSBezierPath(ovalIn: rect)
        track.lineWidth = lineWidth
        NSColor.black.withAlphaComponent(0.25).setStroke()
        track.stroke()
        NSColor.black.setStroke()
        if remainingPercent >= 100 {
            track.stroke()
        } else if remainingPercent > 0 {
            let progress = NSBezierPath()
            progress.lineWidth = lineWidth
            progress.lineCapStyle = .round
            progress.appendArc(withCenter: center, radius: rect.width / 2,
                               startAngle: 90, endAngle: 90 - remainingPercent * 3.6, clockwise: true)
            progress.stroke()
        }
    }
}

struct MultiAccountMenuBarRenderer: Equatable {
    let values: [Int]
    let warning: Bool

    func image() -> NSImage? {
        guard !values.isEmpty else { return nil }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        let ringDiameter: CGFloat = 18
        let lineWidth: CGFloat = 2.5
        let gap: CGFloat = 5
        let valueWidths = values.map { NSString(string: "\($0)%").size(withAttributes: [.font: font]).width }
        let itemWidths: [CGFloat] = valueWidths.map { ringDiameter + 4 + $0 }
        let warningWidth: CGFloat = warning ? 12 : 0
        let itemWidthTotal = itemWidths.reduce(CGFloat.zero, +)
        let separatorWidth = CGFloat(max(0, values.count - 1)) * gap
        let width = warningWidth + itemWidthTotal + separatorWidth + 3
        let image = NSImage(size: NSSize(width: width, height: 22), flipped: false) { bounds in
            var x = warningWidth + 1
            for (index, value) in self.values.enumerated() {
                let center = NSPoint(x: x + ringDiameter / 2, y: bounds.midY)
                Self.drawRing(center: center, remainingPercent: Double(value), diameter: ringDiameter, lineWidth: lineWidth)
                let text = NSString(string: "\(value)%")
                text.draw(at: NSPoint(x: x + ringDiameter + 4, y: bounds.midY - 7),
                          withAttributes: [.font: font, .foregroundColor: NSColor.black])
                x += itemWidths[index] + gap
            }
            if self.warning {
                NSString(string: "!").draw(at: NSPoint(x: 0, y: bounds.midY - 7),
                                            withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .bold),
                                                              .foregroundColor: NSColor.black])
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawRing(center: NSPoint, remainingPercent: Double, diameter: CGFloat, lineWidth: CGFloat) {
        let rect = NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                          width: diameter, height: diameter).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let track = NSBezierPath(ovalIn: rect)
        track.lineWidth = lineWidth
        NSColor.black.withAlphaComponent(0.25).setStroke()
        track.stroke()
        guard remainingPercent > 0 else { return }
        if remainingPercent >= 100 {
            NSColor.black.setStroke()
            track.stroke()
            return
        }
        let progress = NSBezierPath()
        progress.lineWidth = lineWidth
        progress.lineCapStyle = .round
        progress.appendArc(withCenter: center, radius: rect.width / 2,
                           startAngle: 90, endAngle: 90 - remainingPercent * 3.6, clockwise: true)
        NSColor.black.setStroke()
        progress.stroke()
    }
}
