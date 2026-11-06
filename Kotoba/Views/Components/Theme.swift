import SwiftUI
import UIKit

/// Original visual language for the app: warm paper, deep ink, one indigo accent.
enum Theme {
    // MARK: Palette

    static let accent = Color(red: 0.18, green: 0.33, blue: 0.60)
    static let accentSoft = Color(red: 0.87, green: 0.90, blue: 0.97)
    static let jade = Color(red: 0.16, green: 0.52, blue: 0.40)
    static let amber = Color(red: 0.82, green: 0.52, blue: 0.13)
    static let rose = Color(red: 0.70, green: 0.26, blue: 0.31)
    static let lilac = Color(red: 0.44, green: 0.37, blue: 0.70)
    static let plum = Color(red: 0.36, green: 0.24, blue: 0.42)

    static let ink = dynamic(
        light: UIColor(red: 0.09, green: 0.10, blue: 0.13, alpha: 1),
        dark: UIColor(red: 0.95, green: 0.94, blue: 0.92, alpha: 1)
    )

    static let secondaryText = dynamic(
        light: UIColor(red: 0.40, green: 0.41, blue: 0.44, alpha: 1),
        dark: UIColor(red: 0.68, green: 0.68, blue: 0.70, alpha: 1)
    )

    static let paper = dynamic(
        light: UIColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1),
        dark: UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1)
    )

    static let card = dynamic(
        light: UIColor(red: 1.0, green: 0.995, blue: 0.97, alpha: 1),
        dark: UIColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1)
    )

    static let cardMuted = dynamic(
        light: UIColor(red: 0.95, green: 0.94, blue: 0.90, alpha: 1),
        dark: UIColor(red: 0.17, green: 0.17, blue: 0.19, alpha: 1)
    )

    static let screenBackground = dynamic(
        light: UIColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1),
        dark: UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
    )

    static let hairline = dynamic(
        light: UIColor.black.withAlphaComponent(0.08),
        dark: UIColor.white.withAlphaComponent(0.10)
    )

    // MARK: Metrics

    static let corner: CGFloat = 20
    static let smallCorner: CGFloat = 12
    static let cardPadding: CGFloat = 16

    // MARK: Semantic colors

    static func familiarityColor(_ level: Int) -> Color {
        switch level {
        case 1: return rose
        case 2: return amber
        case 3: return lilac
        case 4: return accent
        default: return jade
        }
    }

    static func levelColor(_ level: JLPTLevel?) -> Color {
        guard let level else { return secondaryText }
        switch level {
        case .n5: return jade
        case .n4: return Color(red: 0.24, green: 0.45, blue: 0.58)
        case .n3: return accent
        case .n2: return lilac
        case .n1: return plum
        }
    }

    static func ratingColor(_ rating: ReviewRating) -> Color {
        switch rating {
        case .again: return rose
        case .hard: return amber
        case .good: return accent
        case .easy: return jade
        }
    }

    /// Stable pseudo-random color used for generated scenes and avatars.
    static func colorHash(_ seed: String) -> Color {
        var hash: UInt64 = 5381
        for scalar in seed.unicodeScalars {
            hash = (hash &* 33) &+ UInt64(scalar.value)
        }
        let palette: [Color] = [accent, jade, lilac, plum, amber]
        return palette[Int(hash % UInt64(palette.count))]
    }

    // MARK: Typography (Dynamic Type aware)

    /// Font for a base point size, expressed as a system text style so it scales.
    static func font(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        font(FontScale.textStyle(for: Double(size)), weight: weight, design: design)
    }

    /// Font for a semantic text style. Prefer this for new code.
    static func font(
        _ style: FontScale.TextStyle,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        .system(swiftUITextStyle(style), design: design).weight(weight)
    }

    static func swiftUITextStyle(_ style: FontScale.TextStyle) -> Font.TextStyle {
        switch style {
        case .caption2: return .caption2
        case .caption: return .caption
        case .footnote: return .footnote
        case .subheadline: return .subheadline
        case .callout: return .callout
        case .body: return .body
        case .title3: return .title3
        case .title2: return .title2
        case .title: return .title
        case .largeTitle: return .largeTitle
        }
    }

    // MARK: Helpers

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

// MARK: - Shared modifiers

struct CardBackground: ViewModifier {
    var padded = true

    func body(content: Content) -> some View {
        content
            .padding(padded ? Theme.cardPadding : 0)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func card(padded: Bool = true) -> some View {
        modifier(CardBackground(padded: padded))
    }

    func screenBackground() -> some View {
        background(Theme.screenBackground.ignoresSafeArea())
    }

    func sectionSpacing() -> some View {
        padding(.horizontal, 18)
    }
}

// MARK: - Display text scaling

/// Keeps a large display size (kanji glyph, big counters) while letting Dynamic
/// Type grow it, via `@ScaledMetric` relative to a text style.
struct ScaledFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(base: CGFloat, relativeTo style: Font.TextStyle, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: base, relativeTo: style)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    func scaledFont(
        _ base: CGFloat,
        relativeTo style: Font.TextStyle = .body,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(ScaledFontModifier(base: base, relativeTo: style, weight: weight, design: design))
    }
}

// MARK: - Accessibility helpers

extension View {
    /// Read-only block read as one sentence, e.g. a card summary.
    func a11yCombine(_ label: String, hint: String? = nil, value: String? = nil) -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(label))
            .accessibilityHint(Text(hint ?? ""))
            .accessibilityValue(Text(value ?? ""))
    }

    /// Icon-only control: give it the meaning a sighted user gets from the glyph.
    func a11yButton(_ label: String, hint: String? = nil, value: String? = nil) -> some View {
        self
            .accessibilityLabel(Text(label))
            .accessibilityHint(Text(hint ?? ""))
            .accessibilityValue(Text(value ?? ""))
            .accessibilityAddTraits(.isButton)
    }

    /// Purely decorative artwork that must not appear in the VoiceOver tree.
    func a11yDecorative() -> some View {
        accessibilityHidden(true)
    }
}

extension Text {
    /// Secondary channel for state that would otherwise be colour-only.
    func stateUnderline(_ level: Int) -> Text {
        switch level {
        case 1: return underline(true, pattern: .solid, color: nil)
        case 2: return underline(true, pattern: .dot, color: nil)
        default: return self
        }
    }
}
