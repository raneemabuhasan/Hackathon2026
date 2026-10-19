import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// The team palette, darkest to lightest, plus the roles the UI uses.
enum Palette {
    static let wine = Color(hex: 0x590D22)
    static let plum = Color(hex: 0x800F2F)
    static let berry = Color(hex: 0xA4133C)
    static let rose = Color(hex: 0xC9184A)
    static let coral = Color(hex: 0xFF4D6D)
    static let pink = Color(hex: 0xFF758F)
    static let petal = Color(hex: 0xFF8FA3)
    static let blush = Color(hex: 0xFFB3C1)
    static let mist = Color(hex: 0xFFCCD5)
    static let cream = Color(hex: 0xFFF0F3)

    static let bg = cream
    static let surface = Color.white
    static let surface2 = Color(hex: 0xFFE6EC)
    static let ink = wine
    static let inkSoft = wine.opacity(0.66)
    static let inkFaint = wine.opacity(0.42)
    static let line = berry.opacity(0.12)
    static let accent = rose
    static let accentSoft = mist
}

extension Font {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .serif) }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Palette.berry.opacity(0.07), radius: 14, y: 6)
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.3)
            .foregroundStyle(Palette.inkFaint)
    }
}

/// Serif headline with one italic accent phrase, e.g. "Hi Maya, *be gentle* today".
struct DisplayTitle: View {
    let before: String
    let accent: String
    var after: String = ""
    var size: CGFloat = 34

    var body: some View {
        Text("\(before)\(Text(accent).italic().foregroundStyle(Palette.accent))\(after)")
            .font(.display(size))
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title).font(.system(size: 15, weight: .semibold))
            Spacer()
            if let trailing { Text(trailing).font(.caption).foregroundStyle(Palette.inkFaint) }
        }
    }
}

struct Chip: View {
    let label: String
    let selected: Bool
    var small = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: small ? 10 : 11, weight: .bold))
                        .accessibilityHidden(true)
                }
                Text(label)
                    .font(small ? .caption : .subheadline)
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, small ? 11 : 14)
            .padding(.vertical, small ? 6 : 9)
            .foregroundStyle(selected ? Color.white : Palette.ink)
            .background(selected ? Palette.accent : Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Palette.accent : Palette.berry.opacity(0.3)))
            // Keep the visual pill compact while making the whole control easy to tap.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

/// Wrapping row layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: proposal.width ?? width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Standard scrolling page used by every tab.
struct Page<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
    }
}
