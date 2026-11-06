import Foundation

// MARK: - Model

struct SubtitleCue: Hashable {
    var start: Double
    var end: Double
    var text: String
}

enum SubtitleFormat: String {
    case srt
    case vtt
}

struct SubtitleParseResult {
    let format: SubtitleFormat
    let cues: [SubtitleCue]
    let skippedBlocks: Int

    var duration: Double {
        guard let first = cues.first, let last = cues.last else { return 0 }
        return max(last.end - first.start, 0)
    }
}

enum SubtitleImportError: LocalizedError {
    case unreadableText
    case noCues

    var errorDescription: String? {
        switch self {
        case .unreadableText: return "这个文件读不出文本，请确认是 UTF-8 编码的字幕文件"
        case .noCues: return "没有解析出任何字幕条目，请确认是 SRT 或 VTT 格式"
        }
    }
}

// MARK: - Parser

/// Parses SRT and WebVTT subtitle files.
///
/// Written by hand instead of a regex sweep so the edge cases that actually show
/// up in downloaded subtitles stay explicit: BOM, CRLF, index lines, cue settings
/// after the timestamp, `<i>`/`<font>` tags, ASS override blocks, HTML entities,
/// and the duplicated "scrolling" cues that many fansub files contain.
enum SubtitleParser {
    static func detectFormat(_ text: String) -> SubtitleFormat {
        let head = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(16)
            .uppercased()
        return head.hasPrefix("WEBVTT") ? .vtt : .srt
    }

    static func parse(data: Data) throws -> SubtitleParseResult {
        let candidates: [String.Encoding] = [.utf8, .utf16, .shiftJIS, .isoLatin1]
        for encoding in candidates {
            if let text = String(data: data, encoding: encoding) {
                return try parse(text)
            }
        }
        throw SubtitleImportError.unreadableText
    }

    static func parse(_ raw: String) throws -> SubtitleParseResult {
        let text = normalize(raw)
        guard !text.isEmpty else { throw SubtitleImportError.unreadableText }

        let format = detectFormat(text)
        var cues: [SubtitleCue] = []
        var skipped = 0
        var block: [String] = []

        func flush() {
            defer { block.removeAll() }
            guard let first = block.first else { return }
            guard let timingIndex = block.firstIndex(where: { $0.contains("-->") }) else {
                let isHeader = first.hasPrefix("WEBVTT") || first.hasPrefix("NOTE") || first.hasPrefix("STYLE")
                if !isHeader { skipped += 1 }
                return
            }
            let timing = block[timingIndex]
            let halves = timing.components(separatedBy: "-->")
            guard halves.count >= 2 else { skipped += 1; return }

            // WebVTT allows cue settings after the end timestamp ("00:02.000 align:start").
            let endToken = halves[1].split(separator: " ").first.map(String.init) ?? ""
            guard let start = parseTimestamp(halves[0]),
                  let end = parseTimestamp(endToken) else {
                skipped += 1
                return
            }

            let body = block[(timingIndex + 1)...].joined(separator: "\n")
            let cleaned = clean(body)
            guard !cleaned.isEmpty, end > start else { skipped += 1; return }
            // Fansub files often repeat the same line across "scroll" cues.
            if let previous = cues.last, previous.text == cleaned { return }
            cues.append(SubtitleCue(start: start, end: end, text: cleaned))
        }

        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
            } else {
                block.append(line)
            }
        }
        flush()

        guard !cues.isEmpty else { throw SubtitleImportError.noCues }
        return SubtitleParseResult(format: format, cues: cues.sorted { $0.start < $1.start }, skippedBlocks: skipped)
    }

    // MARK: Pieces

    static func normalize(_ raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        text = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Accepts "00:00:01,500", "00:00:01.500", "01:02.500" and "62.5".
    static func parseTimestamp(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let pieces = trimmed.replacingOccurrences(of: ",", with: ".").components(separatedBy: ":")
        guard pieces.count >= 1, pieces.count <= 3 else { return nil }
        var total: Double = 0
        var multiplier: Double = 1
        for piece in pieces.reversed() {
            guard let number = Double(piece) else { return nil }
            total += number * multiplier
            multiplier *= 60
        }
        return total
    }

    static func clean(_ text: String) -> String {
        var value = stripBracedOverrides(text)
        value = stripAngleTags(value)
        value = decodeEntities(value)
        let lines = value
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    private static func stripBracedOverrides(_ text: String) -> String {
        guard text.contains("{") else { return text }
        var output = ""
        var depth = 0
        for character in text {
            if character == "{" { depth += 1; continue }
            if character == "}" { depth = max(depth - 1, 0); continue }
            if depth == 0 { output.append(character) }
        }
        return output
    }

    private static func stripAngleTags(_ text: String) -> String {
        guard text.contains("<") else { return text }
        var output = ""
        var inside = false
        for character in text {
            if character == "<" { inside = true; continue }
            if character == ">" { inside = false; continue }
            if !inside { output.append(character) }
        }
        return output
    }

    private static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}

// MARK: - Clip builder

/// Turns parsed cues into scroll-able clips.
struct SubtitleClipBuilder {
    var linesPerClip: Int = 3
    var maxSeconds: Double = 12

    func build(
        cues: [SubtitleCue],
        mediaFileName: String,
        series: String,
        level: JLPTLevel?
    ) -> [Clip] {
        guard !cues.isEmpty else { return [] }
        let perClip = max(1, min(linesPerClip, 8))
        let maxSpan = max(2, maxSeconds)
        let mediaName = mediaFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let media: ClipMedia = mediaName.isEmpty ? .generated : .localFile(mediaName)
        let label = series.isEmpty ? "字幕素材" : series
        let slug = Self.slug(mediaName.isEmpty ? label : mediaName)

        var clips: [Clip] = []
        var start = 0
        var index = 0
        while start < cues.count {
            var texts: [String] = []
            var timings: [ClipLineTiming] = []
            var lastEnd = cues[start].end
            var cursor = start
            while cursor < cues.count, texts.count < perClip {
                let cue = cues[cursor]
                let span = cue.end - cues[start].start
                if !texts.isEmpty && span > maxSpan { break }
                texts.append(cue.text)
                timings.append(ClipLineTiming(start: cue.start, end: max(cue.end, cue.start + 0.3)))
                lastEnd = max(lastEnd, cue.end)
                cursor += 1
            }
            index += 1
            clips.append(
                Clip(
                    id: "sub-\(slug)-\(index)",
                    title: "\(label) · \(index)",
                    series: label,
                    episode: "",
                    transcript: texts.joined(separator: "\n"),
                    translation: "",
                    translationEN: "",
                    level: level,
                    topics: ["字幕导入"],
                    durationSeconds: max(lastEnd - cues[start].start, 1),
                    mediaStartSeconds: cues[start].start,
                    lineTimings: timings,
                    media: media,
                    attribution: "从字幕文件导入（共 \(cues.count) 条字幕）",
                    custom: true
                )
            )
            start = cursor
        }
        return clips
    }

    /// Filesystem/identity friendly id fragment.
    static func slug(_ text: String) -> String {
        let mapped = text.lowercased().map { character -> Character in
            if character.isLetter || character.isNumber { return character }
            return "-"
        }
        var value = String(mapped)
        while value.contains("--") {
            value = value.replacingOccurrences(of: "--", with: "-")
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return value.isEmpty ? "clip" : String(value.prefix(48))
    }
}
