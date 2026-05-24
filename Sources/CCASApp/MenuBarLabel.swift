import AppKit
import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var viewModel: AccountSwitcherViewModel

    var body: some View {
        Image(nsImage: renderedImage)
    }

    @MainActor
    private var renderedImage: NSImage {
        guard let account = viewModel.activeAccount else {
            return AppAssets.menuBarIcon()
        }
        return MenuBarRingRenderer.render(
            number: account.number,
            percent: viewModel.activeQuotaPercent,
            severity: viewModel.activeQuotaSeverity
        )
    }
}

private enum MenuBarRingRenderer {
    @MainActor
    static func render(number: Int, percent: Double?, severity: QuotaSeverity?) -> NSImage {
        let appearance = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) ?? .aqua
        let scheme: ColorScheme = (appearance == .darkAqua) ? .dark : .light

        let renderer = ImageRenderer(content:
            RingIcon(number: number, percent: percent, severity: severity)
                .environment(\.colorScheme, scheme)
        )
        renderer.scale = max(NSScreen.main?.backingScaleFactor ?? 2.0, 2.0)

        guard let image = renderer.nsImage else {
            return NSImage(size: NSSize(width: 18, height: 18))
        }
        image.isTemplate = false
        return image
    }
}

private struct RingIcon: View {
    let number: Int
    let percent: Double?
    let severity: QuotaSeverity?

    private static let trackColor = Color.secondary.opacity(0.35)

    private var progress: Double {
        guard let percent else { return 0 }
        return min(max(percent / 100, 0), 1)
    }

    private var ringColor: Color {
        severity?.color ?? Self.trackColor
    }

    private var label: String {
        number <= 9 ? "#\(number)" : "\(number)"
    }

    private static let strokeWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Self.trackColor, lineWidth: Self.strokeWidth)

            Circle()
                .inset(by: Self.strokeWidth / 2)
                .trim(from: 0, to: progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: Self.strokeWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))

            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(width: 18, height: 18)
    }
}
