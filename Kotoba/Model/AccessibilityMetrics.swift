import Foundation

/// Typography scale shared by the UI and the verification harness.
///
/// The app avoids fixed point sizes: every text size is mapped onto a system text
/// style so Dynamic Type can grow it, or (for display text above 26 pt) applied
/// through `@ScaledMetric` so it keeps its base size and still scales.
enum FontScale {
    enum TextStyle: String, CaseIterable {
        case caption2, caption, footnote, subheadline, callout
        case body, title3, title2, title, largeTitle
    }

    /// Sizes above this are rendered through `@ScaledMetric`, not a text style,
    /// because mapping a 64 pt kanji onto `.largeTitle` would shrink the design.
    static let displayThreshold: Double = 26

    static func usesDisplayScaling(_ size: Double) -> Bool { size > displayThreshold }

    /// Nearest system text style for a base point size. Non-decreasing in `size`.
    static func textStyle(for size: Double) -> TextStyle {
        switch size {
        case ..<11.5: return .caption2
        case ..<12.5: return .caption
        case ..<14.0: return .footnote
        case ..<15.5: return .subheadline
        case ..<16.5: return .callout
        case ..<19.0: return .body
        case ..<22.0: return .title3
        case ..<27.0: return .title2
        case ..<34.0: return .title
        default: return .largeTitle
        }
    }

    /// Approximate default (Large) point size of each style, used for hints.
    static func defaultSize(for style: TextStyle) -> Double {
        switch style {
        case .caption2: return 11
        case .caption: return 12
        case .footnote: return 13
        case .subheadline: return 15
        case .callout: return 16
        case .body: return 17
        case .title3: return 20
        case .title2: return 22
        case .title: return 28
        case .largeTitle: return 34
        }
    }
}
