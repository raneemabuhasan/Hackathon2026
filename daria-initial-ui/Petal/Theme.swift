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

/// Curated light palettes: soft surfaces with darker, readable controls.
enum AppTheme: String, CaseIterable, Identifiable {
    case pink, lavender, sage, sky, peach
    var id: String { rawValue }

    var name: String {
        switch self {
        case .pink: "Petal Pink"
        case .lavender: "Lavender"
        case .sage: "Sage"
        case .sky: "Sky Blue"
        case .peach: "Peach"
        }
    }

    // Existing shade names remain available so all screens share the selection.
    var shades: [UInt32] {
        switch self {
        case .pink: [0x590D22, 0x800F2F, 0xA4133C, 0xC9184A, 0xFF4D6D,
                     0xFF758F, 0xFF8FA3, 0xFFB3C1, 0xFFCCD5, 0xFFF0F3, 0xFFE6EC]
        case .lavender: [0x302044, 0x493262, 0x60457D, 0x73558F, 0x977CB3,
                         0xB29BCC, 0xC5B1DC, 0xD9C9E9, 0xE8DDF2, 0xF7F2FB, 0xEFE5F6]
        case .sage: [0x213D32, 0x2E5142, 0x3D6653, 0x47745F, 0x7DA78C,
                     0x9BBDA6, 0xB2CDBA, 0xCDDFD0, 0xE0EBDF, 0xF3F8F1, 0xE9F1E5]
        case .sky: [0x20394F, 0x2B4E6A, 0x365F80, 0x416F94, 0x78A6C9,
                    0x9EBFDC, 0xB7CFE5, 0xD0E2F0, 0xE0EDF6, 0xF2F8FC, 0xE7F1F9]
        case .peach: [0x503126, 0x6A4130, 0x84543C, 0x986044, 0xC99170,
                      0xDEAF90, 0xE9C3A8, 0xF2D7C3, 0xF8E5D6, 0xFFF7F0, 0xFBECE0]
        }
    }

    var previewAccent: Color { Color(hex: shades[3]) }
    var previewPastel: Color { Color(hex: shades[7]) }
    var previewBackground: Color { Color(hex: shades[9]) }
}

/// Device-local appearance, observed by SwiftUI wherever palette colors are read.
/// Kept separate from account/profile data; changing it never restarts the app state.
@Observable
final class AppAppearance {
    static let shared = AppAppearance()
    static let storageKey = "petal.appearance.theme"

    @ObservationIgnored private let defaults: UserDefaults
    var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Self.storageKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = AppTheme(rawValue: defaults.string(forKey: Self.storageKey) ?? "") ?? .pink
    }
}

enum Palette {
    private static func shade(_ index: Int) -> Color {
        Color(hex: AppAppearance.shared.theme.shades[index])
    }
    static var wine: Color { shade(0) }
    static var plum: Color { shade(1) }
    static var berry: Color { shade(2) }
    static var rose: Color { shade(3) }
    static var coral: Color { shade(4) }
    static var pink: Color { shade(5) }
    static var petal: Color { shade(6) }
    static var blush: Color { shade(7) }
    static var mist: Color { shade(8) }
    static var cream: Color { shade(9) }

    static var bg: Color { cream }
    static let surface = Color.white
    static var surface2: Color { shade(10) }
    static var ink: Color { wine }
    static var inkSoft: Color { wine.opacity(0.72) }
    static var inkFaint: Color { wine.opacity(0.62) }
    static var line: Color { berry.opacity(0.18) }
    static var accent: Color { rose }
    static var accentSoft: Color { mist }
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
