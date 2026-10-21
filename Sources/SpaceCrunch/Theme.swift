import SpaceCrunchCore
import SwiftUI

enum Theme {
    static let cornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 20
    static let contentMaxWidth: CGFloat = 1_060

    /// Apple's standard control corner radius for the current release.
    static let controlRadius: CGFloat = 10
}

/// The app's type ramp, following the macOS type scale.
enum AppFont {
    static let largeTitle = Font.system(size: 26, weight: .bold)
    static let title = Font.system(size: 20, weight: .semibold)
    static let headline = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13)
    static let callout = Font.system(size: 12)
    static let caption = Font.system(size: 11)
    static let caption2 = Font.system(size: 10)
}

extension SpaceCategory {
    var color: Color {
        switch self {
        case .apps:
            Color(red: 0.20, green: 0.47, blue: 0.96)
        case .photos:
            Color(red: 0.97, green: 0.39, blue: 0.51)
        case .video:
            Color(red: 0.60, green: 0.38, blue: 0.96)
        case .audio:
            Color(red: 0.94, green: 0.27, blue: 0.35)
        case .documents:
            Color(red: 0.15, green: 0.66, blue: 0.70)
        case .downloads:
            Color(red: 0.98, green: 0.58, blue: 0.18)
        case .developer:
            Color(red: 0.35, green: 0.42, blue: 0.94)
        case .caches:
            Color(red: 0.93, green: 0.71, blue: 0.15)
        case .archives:
            Color(red: 0.60, green: 0.53, blue: 0.42)
        case .other:
            Color(red: 0.54, green: 0.57, blue: 0.62)
        }
    }
}

extension CleanupSafety {
    var color: Color {
        switch self {
        case .safe:
            Color(red: 0.11, green: 0.62, blue: 0.34)
        case .review:
            Color(red: 0.91, green: 0.53, blue: 0.12)
        }
    }

    var symbolName: String {
        switch self {
        case .safe: "checkmark.shield.fill"
        case .review: "exclamationmark.shield.fill"
        }
    }
}

// MARK: - Surfaces

/// The app's backdrop: a soft, colourful wash over the window colour.
///
/// Liquid Glass refracts whatever sits behind it, so a flat window background
/// makes every glass panel read as a plain rounded rectangle. The wash gives
/// the glass something to bend.
///
/// This is drawn behind the detail column, not behind the whole window. The
/// sidebar keeps the system's own material that way, which is how a native
/// split view looks — and the glow lands in the trailing corner of the window
/// instead of in the middle of the sidebar.
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            RadialGradient(
                colors: [Color.accentColor.opacity(wash(for: 0.30)), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 700
            )
            .blendMode(blend)

            RadialGradient(
                colors: [Color.purple.opacity(wash(for: 0.22)), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 620
            )
            .blendMode(blend)
        }
        .ignoresSafeArea()
    }

    /// Light mode has far less headroom before the wash turns the page milky.
    /// Additive blending on a white background is what makes it pastel, so in
    /// light mode the glow is composited normally and kept much fainter.
    private var blend: BlendMode {
        colorScheme == .dark ? .plusLighter : .normal
    }

    private func wash(for amount: Double) -> Double {
        colorScheme == .dark ? amount : amount * 0.22
    }
}

/// A Liquid Glass panel: translucent, refractive, and borderless apart from its
/// own specular highlight.
struct GlassPanel: ViewModifier {
    var padding: CGFloat = Theme.cardPadding
    var cornerRadius: CGFloat = Theme.cornerRadius
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .glassEffect(
                Glass.regular.tint(tint),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}

/// The standard content container: a glass panel that sits on the app
/// background and reads as a distinct surface without a hard border.
struct CardStyle: ViewModifier {
    var padding: CGFloat = Theme.cardPadding
    var cornerRadius: CGFloat = Theme.cornerRadius

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}

extension View {
    func card(padding: CGFloat = Theme.cardPadding) -> some View {
        modifier(CardStyle(padding: padding))
    }

    /// A floating glass surface that sits above content — used for toolbars,
    /// action bars, and popovers.
    func glassPanel(
        cornerRadius: CGFloat = Theme.cornerRadius,
        tint: Color? = nil
    ) -> some View {
        glassEffect(
            Glass.regular.tint(tint),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }

    func contentColumn() -> some View {
        frame(maxWidth: Theme.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Small pieces

struct SafetyBadge: View {
    let safety: CleanupSafety

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: safety.symbolName)
                .font(.system(size: 9, weight: .semibold))
            Text(safety.title)
                .font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(safety.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(safety.color.opacity(0.14)))
        .accessibilityLabel(safety.title)
    }
}

struct SelectionCircle: View {
    let state: AppModel.SelectionState

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(state == .none ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.accentColor))
            .contentTransition(.symbolEffect(.replace))
    }

    private var symbol: String {
        switch state {
        case .none: "circle"
        case .some: "minus.circle.fill"
        case .all: "checkmark.circle.fill"
        }
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AppFont.headline)
            if let subtitle {
                Text(subtitle)
                    .font(AppFont.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct EmptyStateView: View {
    let symbolName: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbolName)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
                .frame(width: 92, height: 92)
                .glassEffect(
                    .regular,
                    in: Circle()
                )

            VStack(spacing: 5) {
                Text(title)
                    .font(AppFont.title)
                Text(message)
                    .font(AppFont.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct CapacityBar: View {
    let segments: [(color: Color, value: Int64)]
    let total: Int64
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            HStack(spacing: 2) {
                if total > 0 {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        let fraction = min(1, max(0, Double(segment.value) / Double(total)))
                        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                            .fill(segment.color)
                            .frame(width: max(0, width * fraction - 2))
                    }
                    let used = segments.reduce(0) { $0 + $1.value }
                    let freeFraction = max(0, 1 - Double(used) / Double(total))
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.35))
                        .frame(width: max(0, width * freeFraction))
                } else {
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.35))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// A row that highlights when the pointer is over it.
///
/// This stays a flat wash on purpose. Native macOS list rows highlight that
/// way even on macOS 26 - frost each row and the list turns into a field of
/// separate panes instead of one surface with a highlighted row in it.
struct HoverHighlight: ViewModifier {
    @State private var hovering = false
    var radius: CGFloat = 8
    var color: Color = .primary

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(color.opacity(hovering ? 0.06 : 0))
            )
            .onHover { hovering = $0 }
    }
}
