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
                    Self.drawRing(at: center, remainingPercent: item.remainingPercent,
                                  diameter: layout.ringDiameter, lineWidth: layout.ringLineWidth)
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

    fileprivate struct TextRun {
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

    fileprivate static func drawRing(at center: NSPoint, remainingPercent: Double, diameter: CGFloat,
                                     lineWidth: CGFloat, color: NSColor = .black, showsTrack: Bool = true) {
        let rect = NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
            .insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let track = NSBezierPath(ovalIn: rect)
        track.lineWidth = lineWidth
        if showsTrack {
            NSColor.black.withAlphaComponent(0.25).setStroke()
            track.stroke()
        }
        color.setStroke()
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
    let values: [Double]
    let warning: Bool

    func images() -> (template: NSImage?, highlights: NSImage?) {
        guard !values.isEmpty || warning else { return (nil, nil) }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        let ringDiameter: CGFloat = 18
        let lineWidth: CGFloat = 2.5
        let gap: CGFloat = 5
        let warningLabel = MenuBarRenderer.TextRun("⚠︎", font: .systemFont(ofSize: 12, weight: .bold))
        let labels = values.map { MenuBarRenderer.TextRun("\(Int($0.rounded(.down)))%", font: font) }
        var x = warning ? 1 + ceil(warningLabel.width) + gap : 1
        let positions = labels.map { label in
            let left = x
            x += ringDiameter + 4 + ceil(label.width) + gap
            return left
        }
        let size = NSSize(width: x - gap + 2, height: 22)
        let template = NSImage(size: size, flipped: false) { bounds in
            if warning { warningLabel.draw(left: 1, centerY: bounds.midY) }
            for (position, (value, label)) in zip(positions, zip(values, labels)) {
                let center = NSPoint(x: position + ringDiameter / 2, y: bounds.midY)
                if value > 0 {
                    MenuBarRenderer.drawRing(at: center, remainingPercent: value < 50 ? 0 : value,
                                             diameter: ringDiameter, lineWidth: lineWidth)
                }
                label.draw(left: position + ringDiameter + 4, centerY: bounds.midY)
            }
            return true
        }
        template.isTemplate = true
        guard values.contains(where: { $0 < 50 }) else { return (template, nil) }
        // AppKit tints the template for the menu bar. Draw the colored strokes on a separate layer.
        let highlights = NSImage(size: size, flipped: false) { bounds in
            for (position, value) in zip(positions, values) where value < 50 {
                let center = NSPoint(x: position + ringDiameter / 2, y: bounds.midY)
                MenuBarRenderer.drawRing(at: center, remainingPercent: value == 0 ? 100 : value,
                                         diameter: ringDiameter, lineWidth: lineWidth,
                                         color: value < 25 ? .systemRed : .systemOrange, showsTrack: false)
            }
            return true
        }
        return (template, highlights)
    }
}

final class MenuBarRingHighlights: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
