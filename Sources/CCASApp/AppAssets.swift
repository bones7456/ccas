import AppKit

enum AppAssets {
    static func appIcon(size: CGFloat) -> NSImage {
        let image = loadImage(named: "AppIcon")
            ?? NSImage(systemSymbolName: "lock.rectangle.stack", accessibilityDescription: "CCAS")
            ?? NSImage(size: NSSize(width: size, height: size))

        image.isTemplate = false
        image.size = NSSize(width: size, height: size)
        return image
    }

    static func menuBarIcon() -> NSImage {
        let image = loadImage(named: "MenuBarIconTemplate")
            ?? NSImage(systemSymbolName: "person.2.badge.gearshape", accessibilityDescription: "CCAS")
            ?? NSImage(size: NSSize(width: 18, height: 18))

        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    private static func loadImage(named name: String) -> NSImage? {
        var bundles = [Bundle.main]

        #if SWIFT_PACKAGE
        bundles.insert(Bundle.module, at: 0)
        #endif

        for bundle in bundles {
            if let url = bundle.url(forResource: name, withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }

        return nil
    }
}
