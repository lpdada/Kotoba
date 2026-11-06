import SwiftUI

// MARK: - Furigana markup

/// Segments of `{漢字|かんじ}` markup found in dictionary examples.
enum FuriganaParser {
    struct Segment: Identifiable, Hashable {
        let id: Int
        let base: String
        let reading: String?
    }

    static func parse(_ markup: String) -> [Segment] {
        var segments: [Segment] = []
        var buffer = ""
        var index = 0
        var cursor = markup.startIndex

        while cursor < markup.endIndex {
            let character = markup[cursor]
            if character == "{" {
                if !buffer.isEmpty {
                    segments.append(Segment(id: index, base: buffer, reading: nil))
                    index += 1
                    buffer = ""
                }
                var body = ""
                var next = markup.index(after: cursor)
                while next < markup.endIndex, markup[next] != "}" {
                    body.append(markup[next])
                    next = markup.index(after: next)
                }
                let parts = body.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                let base = String(parts.first ?? "")
                let reading = parts.count > 1 ? String(parts[1]) : nil
                segments.append(Segment(id: index, base: base, reading: reading))
                index += 1
                cursor = next < markup.endIndex ? markup.index(after: next) : markup.endIndex
            } else {
                buffer.append(character)
                cursor = markup.index(after: cursor)
            }
        }
        if !buffer.isEmpty {
            segments.append(Segment(id: index, base: buffer, reading: nil))
        }
        return segments
    }
}

/// Renders dictionary example sentences with small readings above the kanji.
struct FuriganaMarkupView: View {
    let markup: String
    var fontSize: CGFloat = 15
    var color: Color = Theme.ink

    var body: some View {
        TokenFlowLayout(spacing: 1, lineSpacing: 3) {
            ForEach(FuriganaParser.parse(markup)) { segment in
                VStack(spacing: 0) {
                    if let reading = segment.reading {
                        Text(reading)
                            .scaledFont(fontSize * 0.58)
                            .foregroundStyle(color.opacity(0.55))
                    } else {
                        Text(" ")
                            .scaledFont(fontSize * 0.58)
                            .opacity(0)
                    }
                    Text(segment.base)
                        .scaledFont(fontSize, relativeTo: .body, weight: .regular, design: .serif)
                        .foregroundStyle(color)
                }
            }
        }
    }
}

// MARK: - Token view

struct SubtitleTokenView: View {
    let token: ClipToken
    let familiarity: Int?
    var showFurigana: Bool = true
    var showRomaji: Bool = false
    var isActive: Bool = false
    var fontSize: CGFloat = 21

    var body: some View {
        content
            .padding(.horizontal, token.kind == .punctuation ? 1 : 3)
            .padding(.vertical, 2)
            .background(
                isActive ? Theme.accent.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(Rectangle())
    }

    private var content: some View {
        VStack(spacing: 0) {
            if showFurigana, let reading = token.reading, reading != token.text, token.kind != .punctuation {
                Text(reading)
                    .scaledFont(fontSize * 0.52)
                    .foregroundStyle(tint.opacity(0.75))
            } else if showFurigana, token.kind != .punctuation {
                Text(" ")
                    .scaledFont(fontSize * 0.52)
                    .opacity(0)
            }
            Text(token.text)
                // Non-colour channel for familiarity: unknown words are solid
                // underlined, half-known dotted, known words plain.
                .stateUnderline(familiarity ?? 0)
                .scaledFont(fontSize, relativeTo: .body, weight: .regular, design: .serif)
                .foregroundStyle(tint)
            if showRomaji, token.kind == .word || token.kind == .particle {
                Text(token.romajiText)
                    .scaledFont(fontSize * 0.42)
                    .foregroundStyle(tint.opacity(0.5))
            }
        }
    }

    private func tokenLabel(_ token: ClipToken, familiarity: Int?) -> String {
        var parts = [token.text]
        if let reading = token.reading, reading != token.text { parts.append("读音 \(reading)") }
        if let formation = token.formation { parts.append(formation) }
        if let familiarity {
            parts.append("熟悉度 \(familiarity)，\(SpacedRepetition.familiarityTitle(familiarity))")
        } else {
            parts.append("未收录")
        }
        return parts.joined(separator: "，")
    }

    private var tint: Color {
        if let familiarity {
            return Theme.familiarityColor(familiarity)
        }
        switch token.kind {
        case .punctuation: return Theme.ink.opacity(0.55)
        case .unknown: return Theme.ink
        default: return Theme.ink
        }
    }
}

// MARK: - Line block

struct SubtitleLineView: View {
    let tokens: [ClipToken]
    let translation: String?
    var familiarityFor: (ClipToken) -> Int?
    var showFurigana: Bool = true
    var showRomaji: Bool = false
    var showTranslation: Bool = true
    var activeTokenID: Int?
    var onTapToken: (ClipToken) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TokenFlowLayout(spacing: 2, lineSpacing: 4) {
                ForEach(tokens) { token in
                    if token.kind == .punctuation {
                        Text(token.text)
                            .font(Theme.font(size: 21, design: .serif))
                            .foregroundStyle(Theme.ink.opacity(0.7))
                    } else {
                        Button {
                            onTapToken(token)
                        } label: {
                            SubtitleTokenView(
                                token: token,
                                familiarity: familiarityFor(token),
                                showFurigana: showFurigana,
                                showRomaji: showRomaji,
                                isActive: activeTokenID == token.id
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(tokenLabel(token, familiarity: familiarityFor(token))))
                        .accessibilityHint(Text("查看读音、释义与例句"))
                    }
                }
            }
            if showTranslation, let translation, !translation.isEmpty {
                Text(translation)
                    .font(Theme.font(size: 13))
                    .foregroundStyle(Theme.ink.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
