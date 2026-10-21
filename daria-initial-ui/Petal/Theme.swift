import SwiftUI
import Observation

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Each choice is a complete color system, with a complementary secondary family.
struct ThemeColors {
    let ink, softInk, mutedInk: UInt32
    let accent, deepAccent, phaseDark, highlight, lightAccent: UInt32
    let pastel, softPrimary, primarySurface: UInt32
    let secondary, secondaryPastel, secondarySurface, selectionInk: UInt32
    let background, border: UInt32
}

enum CoordinatedTheme: String, CaseIterable, Identifiable {
    case blush, lavender, sage, sky, peach
    var id: String { rawValue }
    var name: String {
        switch self {
        case .blush: "Blush & Sage"
        case .lavender: "Lavender & Buttercream"
        case .sage: "Sage & Apricot"
        case .sky: "Sky & Sand"
        case .peach: "Peach & Lilac"
        }
    }
    var detail: String {
        switch self {
        case .blush: "Blush pink · sage · warm ivory · forest green"
        case .lavender: "Lilac accents · plum text"
        case .sage: "Botanical greens · warm peach details"
        case .sky: "Soft blues · sandy neutrals"
        case .peach: "Apricot accents · dusky-purple details"
        }
    }
    var colors: ThemeColors {
        switch self {
        case .blush:
            // Screenshot reference: rose actions, sage selections, forest text, ivory canvas.
            ThemeColors(ink: 0x344A3C, softInk: 0x566B5C, mutedInk: 0x566B5C,
                        accent: 0xB43762, deepAccent: 0x87324F, phaseDark: 0x566B5C,
                        highlight: 0xD58EA4, lightAccent: 0xEBA0B6,
                        pastel: 0xF2C6CF, softPrimary: 0xF7DFE4, primarySurface: 0xF9E9EC,
                        secondary: 0x566B5C, secondaryPastel: 0xA8BDA5, secondarySurface: 0xE4ECE0,
                        selectionInk: 0x344A3C, background: 0xF7F3EC, border: 0xD9DCD2)
        case .lavender:
            ThemeColors(ink: 0x3C304B, softInk: 0x51415F, mutedInk: 0x584966,
                        accent: 0x76508C, deepAccent: 0x624277, phaseDark: 0x51405F,
                        highlight: 0xAD91C3, lightAccent: 0xC9B4D9,
                        pastel: 0xDCCCE9, softPrimary: 0xEBE1F2, primarySurface: 0xF1EAF6,
                        secondary: 0x756039, secondaryPastel: 0xE4D4A9, secondarySurface: 0xF4EEDC,
                        selectionInk: 0x483919, background: 0xF7F3F5, border: 0xDDD6D9)
        case .sage:
            ThemeColors(ink: 0x2F4539, softInk: 0x405848, mutedInk: 0x465D4E,
                        accent: 0x4F715B, deepAccent: 0x41624D, phaseDark: 0x3E5550,
                        highlight: 0x8DB39A, lightAccent: 0xB4CDB6,
                        pastel: 0xC9DDC9, softPrimary: 0xDEEADD, primarySurface: 0xEAF1E7,
                        secondary: 0x82553B, secondaryPastel: 0xE7BEA1, secondarySurface: 0xF6E7DA,
                        selectionInk: 0x4F341F, background: 0xF6F4EC, border: 0xD9DDD0)
        case .sky:
            ThemeColors(ink: 0x2C4054, softInk: 0x3D536A, mutedInk: 0x455A70,
                        accent: 0x416F94, deepAccent: 0x345E81, phaseDark: 0x4C536C,
                        highlight: 0x8EB6D6, lightAccent: 0xB4CEE3,
                        pastel: 0xCADEEF, softPrimary: 0xDFEAF5, primarySurface: 0xEAF1F8,
                        secondary: 0x796345, secondaryPastel: 0xDCC8A9, secondarySurface: 0xF2EBDF,
                        selectionInk: 0x493B28, background: 0xF5F4F0, border: 0xD6DDE0)
        case .peach:
            ThemeColors(ink: 0x503B46, softInk: 0x604952, mutedInk: 0x67515B,
                        accent: 0xA15A40, deepAccent: 0x874A36, phaseDark: 0x665078,
                        highlight: 0xD99A7D, lightAccent: 0xE8BCA6,
                        pastel: 0xF0D0BD, softPrimary: 0xF7E3D7, primarySurface: 0xFBEDE4,
                        secondary: 0x705981, secondaryPastel: 0xCEBCDD, secondarySurface: 0xEEE5F4,
                        selectionInk: 0x473650, background: 0xF9F3ED, border: 0xE1D7D2)
        }
    }
}

@Observable
final class PalettePreferences {
    static let shared = PalettePreferences()
    static let key = "petal.coordinatedPalette.v1"
    @ObservationIgnored private let defaults: UserDefaults
    var theme: CoordinatedTheme {
        didSet { defaults.set(theme.rawValue, forKey: Self.key) }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = CoordinatedTheme(rawValue: defaults.string(forKey: Self.key) ?? "") ?? .blush
    }
}

/// Read the observed selection wherever colors are used; switching never recreates app state.
enum Palette {
    private static var colors: ThemeColors { PalettePreferences.shared.theme.colors }
    static var blushPink: Color { Color(hex: colors.pastel) }
    static var sageGreen: Color { Color(hex: colors.secondaryPastel) }
    static var warmIvory: Color { Color(hex: colors.background) }
    static var forestGreen: Color { Color(hex: colors.secondary) }
    static var wine: Color { Color(hex: colors.ink) }
    static var plum: Color { Color(hex: colors.phaseDark) }
    static var berry: Color { Color(hex: colors.deepAccent) }
    static var rose: Color { Color(hex: colors.accent) }
    static var coral: Color { Color(hex: colors.highlight) }
    static var pink: Color { Color(hex: colors.highlight) }
    static var petal: Color { Color(hex: colors.lightAccent) }
    static var blush: Color { blushPink }
    static var mist: Color { Color(hex: colors.softPrimary) }
    static var cream: Color { warmIvory }
    static var bg: Color { warmIvory }
    static let surface = Color.white
    static var surface2: Color { Color(hex: colors.primarySurface) }
    static var ink: Color { wine }
    static var inkSoft: Color { Color(hex: colors.softInk) }
    static var inkFaint: Color { Color(hex: colors.mutedInk) }
    static var line: Color { Color(hex: colors.border) }
    static var accent: Color { rose }
    static var accentSoft: Color { mist }
    static var secondaryAccent: Color { forestGreen }
    static var secondarySurface: Color { Color(hex: colors.secondarySurface) }
    static var selectionSurface: Color { sageGreen }
    static var selectionInk: Color { Color(hex: colors.selectionInk) }
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
    var icon: AnyView? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: small ? 10 : 11, weight: .bold))
                        .accessibilityHidden(true)
                }
                if let icon { icon.frame(width: 14, height: 14).accessibilityHidden(true) }
                Text(label)
                    .font(small ? .caption : .subheadline)
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, small ? 11 : 14)
            .padding(.vertical, small ? 6 : 9)
            .foregroundStyle(selected ? Palette.selectionInk : Palette.ink)
            .background(selected ? Palette.selectionSurface : Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Palette.secondaryAccent : Palette.line))
            // Keep the visual pill compact while making the whole control easy to tap.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
