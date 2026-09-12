import SwiftUI

enum BrandAssets {
    static let resources: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Tibometer_Tibometer.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return .module
    }()

    static let logo: NSImage = {
        if let url = resources.url(forResource: "Logo", withExtension: "png"),
           let image = NSImage(contentsOf: url) { return image }
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }()

    static let githubMark: NSImage = {
        guard let url = resources.url(forResource: "GitHubMark", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return NSImage() }
        image.isTemplate = true
        return image
    }()

    static let menuBarIcon: NSImage = {
        let source = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            .flatMap { NSImage(contentsOf: $0) }
            ?? logo
        let image = source.copy() as! NSImage
        image.size = NSSize(width: 22, height: 22)
        image.isTemplate = false
        return image
    }()
}

struct GitHubIcon: View {
    var body: some View {
        Image(nsImage: BrandAssets.githubMark)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: 14, height: 14)
            .accessibilityHidden(true)
    }
}

struct BrandLogo: View {
    var size: CGFloat = 42

    var body: some View {
        Image(nsImage: BrandAssets.logo)
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).strokeBorder(.primary.opacity(0.07)))
            .accessibilityHidden(true)
    }
}
