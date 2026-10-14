import SwiftUI

// Building blocks shared by the detail screens (exercise, recipe): the look
// approved in October 2026, kept in one place so the screens stay alike.

/// iOS 18 and later report scrolling directly; a preference read from the
/// content (DetailScrollKey) covers iOS 16-17.
struct ScrollOffsetReader: ViewModifier {
    @Binding var offset: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { -($0.contentOffset.y + $0.contentInsets.top) } action: { _, y in
                offset = y
            }
        } else {
            content
        }
    }
}

struct DetailScrollKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}


struct GlassCircleButton: View {
    let icon: String
    var label: LocalizedStringKey = "Back"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial)
                .background(Color.black.opacity(0.25))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.15)))
        }
        .accessibilityLabel(Text(label))
    }
}

struct FactCell: View {
    let value: String
    let label: String
    var accent = false

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(accent ? SBFont.heading(14) : SBFont.heading(18))
                .foregroundColor(accent ? .sbAccent : .sbTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 24)
            Text(label)
                .font(SBFont.label(11))
                .foregroundColor(.sbTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.sbSurface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sbBorder))
    }
}


/// Chips that wrap onto the next line when they don't fit.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

struct SectionTitle: View {
    let icon: String
    let title: String

    var body: some View {
        Label {
            Text(title).font(SBFont.heading(14)).foregroundColor(.sbTextPrimary)
        } icon: {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundColor(.sbAccent)
        }
        .padding(.bottom, 8)
    }
}


/// The compact bar that takes over from the photo once the page is scrolled:
/// a way back and the title.
struct DetailTopBar: View {
    let title: String
    let visible: Bool
    let back: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.sbTextPrimary)
                    .frame(width: 32, height: 32)
                    .background(Color.sbSurfaceRaised)
                    .clipShape(Circle())
            }
            .accessibilityLabel(Text("Back"))
            Text(title)
                .font(SBFont.heading(16))
                .foregroundColor(.sbTextPrimary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Color.sbBorder).frame(height: 1), alignment: .bottom)
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: visible)
        .allowsHitTesting(visible)
    }
}
