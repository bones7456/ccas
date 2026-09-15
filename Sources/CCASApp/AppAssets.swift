import AppKit

enum AppAssets {
    // Cached per (name, size): `appIcon` mutates `image.size`, so callers asking
    // for different sizes must not share one instance. Returning the *same*
    // instance for the same request is the point — Core Animation keys its
    // decoded-image cache off the object, so handing it a fresh NSImage every
    // frame forced it to re-decode the PNG on every display cycle.
    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor
    static func appIcon(size: CGFloat) -> NSImage {
        let key = "AppIcon@\(size)"
        if let cached = cache[key] { return cached }

        let loaded = loadImage(named: "AppIcon")
            ?? NSImage(systemSymbolName: "lock.rectangle.stack", accessibilityDescription: "CCAS")
            ?? NSImage(size: NSSize(width: size, height: size))

        // AppIcon.png is 1024x1024 but is only ever shown at ~34pt. Redraw it
        // once at the requested size so the oversized bitmap can be released
        // after this call instead of being retained by the image cache.
        let image = downsampled(loaded, to: size) ?? loaded

        image.isTemplate = false
        image.size = NSSize(width: size, height: size)
        cache[key] = image
        return image
    }

    @MainActor
    static func menuBarIcon() -> NSImage {
        let key = "MenuBarIconTemplate@18"
        if let cached = cache[key] { return cached }

        let image = loadImage(named: "MenuBarIconTemplate")
            ?? NSImage(systemSymbolName: "person.2.badge.gearshape", accessibilityDescription: "CCAS")
            ?? NSImage(size: NSSize(width: 18, height: 18))

        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        cache[key] = image
        return image
    }

    private static func loadImage(named name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        return image
    }

    /// Rasterizes `image` once at `size` (2x, for Retina). Returns nil — leaving
    /// the caller with the original — when the source is already small enough to
    /// not be worth redrawing, which is also what keeps the SF Symbol fallbacks
    /// above out of this path.
    private static func downsampled(_ image: NSImage, to size: CGFloat) -> NSImage? {
        let scale: CGFloat = 2
        guard size > 0, image.size.width > size * scale else { return nil }

        let pixels = Int((size * scale).rounded())
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return nil
        }

        rep.size = NSSize(width: size, height: size)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: size, height: size),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        let result = NSImage(size: NSSize(width: size, height: size))
        result.addRepresentation(rep)
        return result
    }
}
