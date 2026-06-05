import AppKit
import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var viewModel: AccountSwitcherViewModel

    var body: some View {
        Image(nsImage: renderedImage)
    }

    @MainActor
    private var renderedImage: NSImage {
        _ = viewModel.appearanceTick
        _ = viewModel.markerBlinkOn
        guard let account = viewModel.activeAccount else {
            return AppAssets.menuBarIcon()
        }
        return MenuBarRingRenderer.render(
            number: account.number,
            percent: viewModel.activeQuotaPercent,
            severity: viewModel.activeQuotaSeverity,
            timeMarker: viewModel.activeQuotaTimeMarker,
            markerVisible: viewModel.markerBlinkOn
        )
    }
}

private enum MenuBarRingRenderer {
    @MainActor
    static func render(
        number: Int,
        percent: Double?,
        severity: QuotaSeverity?,
        timeMarker: Double?,
        markerVisible: Bool
    ) -> NSImage {
        let appearance = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) ?? .aqua
        let scheme: ColorScheme = (appearance == .darkAqua) ? .dark : .light

        let renderer = ImageRenderer(content:
            RingIcon(
                number: number,
                percent: percent,
                severity: severity,
                timeMarker: timeMarker,
                markerVisible: markerVisible
            )
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
    var timeMarker: Double? = nil
    var markerVisible: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    private static let trackColor = Color.secondary.opacity(0.35)
    // Electric cyan — vivid enough to stand out at menu bar size against the
    // green/orange/red arc and the gray track.
    private static let markerColor = Color(red: 0.0, green: 0.9, blue: 1.0)

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

    private var fillColor: Color {
        colorScheme == .dark
            ? Color(white: 0.15)
            : Color(white: 0.92)
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Self.trackColor, lineWidth: Self.strokeWidth)

            Circle()
                .inset(by: Self.strokeWidth)
                .fill(fillColor)

            Circle()
                .inset(by: Self.strokeWidth / 2)
                .trim(from: 0, to: progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: Self.strokeWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))

            if let timeMarker {
                RingTimeMarker(fraction: timeMarker)
                    .stroke(Self.markerColor, style: StrokeStyle(lineWidth: 1.3, lineCap: .butt))
                    .opacity(markerVisible ? 1.0 : 0.3)
            }

            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(width: 18, height: 18)
    }
}

/// A short radial tick crossing the ring's stroke band at the given fraction
/// of a full turn, measured clockwise from 12 o'clock (matching the arc).
private struct RingTimeMarker: Shape {
    let fraction: Double
    // Span the ring's stroke band (~6.5...9.0) so the tick sits inside it.
    private static let innerRadius: CGFloat = 6.6
    private static let outerRadius: CGFloat = 8.9

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let theta = min(max(fraction, 0), 1) * 2 * .pi
        let sinT = sin(theta)
        let cosT = cos(theta)

        var path = Path()
        path.move(to: CGPoint(
            x: center.x + Self.innerRadius * sinT,
            y: center.y - Self.innerRadius * cosT
        ))
        path.addLine(to: CGPoint(
            x: center.x + Self.outerRadius * sinT,
            y: center.y - Self.outerRadius * cosT
        ))
        return path
    }
}
