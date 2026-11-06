import Foundation

// MARK: - Media descriptor

/// Where a clip's picture comes from.
///
/// * `.generated`  – original animated scene rendered by SwiftUI (bundled samples).
/// * `.localFile`  – file name inside the app's `Media` folder (your own footage).
/// * `.remote`     – absolute http(s) URL you control.
/// * `.youtube`    – a YouTube video id plus the segment to loop, played with the
///                   official embedded player (the video stays hosted by its owner).
enum ClipMedia: Hashable, Codable {
    case generated
    case localFile(String)
    case remote(String)
    case youtube(id: String, start: Double, end: Double)

    private enum CodingKeys: String, CodingKey { case kind, value, id, start, end }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "generated":
            self = .generated
        case "localFile":
            self = .localFile(try container.decode(String.self, forKey: .value))
        case "remote":
            self = .remote(try container.decode(String.self, forKey: .value))
        case "youtube":
            self = .youtube(
                id: try container.decode(String.self, forKey: .id),
                start: try container.decodeIfPresent(Double.self, forKey: .start) ?? 0,
                end: try container.decodeIfPresent(Double.self, forKey: .end) ?? 0
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown clip media kind: \(kind)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .generated:
            try container.encode("generated", forKey: .kind)
        case .localFile(let name):
            try container.encode("localFile", forKey: .kind)
            try container.encode(name, forKey: .value)
        case .remote(let url):
            try container.encode("remote", forKey: .kind)
            try container.encode(url, forKey: .value)
        case .youtube(let id, let start, let end):
            try container.encode("youtube", forKey: .kind)
            try container.encode(id, forKey: .id)
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
        }
    }

    var isVideo: Bool {
        switch self {
        case .generated: return false
        case .localFile, .remote, .youtube: return true
        }
    }

    var shortLabel: String {
        switch self {
        case .generated: return "内置朗读"
        case .localFile: return "本地片段"
        case .remote: return "网络片段"
        case .youtube: return "YouTube"
        }
    }
}

// MARK: - Clip

/// One scrollable learning unit: a short piece of media plus its subtitle lines.
struct Clip: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var series: String
    var episode: String
    /// Japanese subtitle text. Multiple sentences are separated by newlines.
    var transcript: String
    /// Chinese translation, one line per transcript line (best effort).
    var translation: String
    var translationEN: String
    /// Author declared level. When nil the level is estimated from the text.
    var level: JLPTLevel?
    var topics: [String]
    var durationSeconds: Double
    /// Optional offset into the media file where this clip begins (subtitle imports).
    /// Stored as an optional so older clip JSON that lacks the key still decodes.
    var mediaStartSeconds: Double?
    var media: ClipMedia
    var attribution: String
    var custom: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, series, episode, transcript, translation
        case translationEN = "translation_en"
        case level, topics
        case durationSeconds = "duration_seconds"
        case mediaStartSeconds = "start_seconds"
        case media, attribution, custom
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        series: String,
        episode: String = "",
        transcript: String,
        translation: String,
        translationEN: String = "",
        level: JLPTLevel? = nil,
        topics: [String] = [],
        durationSeconds: Double = 12,
        mediaStartSeconds: Double? = nil,
        media: ClipMedia = .generated,
        attribution: String = "",
        custom: Bool = false
    ) {
        self.id = id
        self.title = title
        self.series = series
        self.episode = episode
        self.transcript = transcript
        self.translation = translation
        self.translationEN = translationEN
        self.level = level
        self.topics = topics
        self.durationSeconds = durationSeconds
        self.mediaStartSeconds = mediaStartSeconds
        self.media = media
        self.attribution = attribution
        self.custom = custom
    }

    /// Individual subtitle lines, blanks removed.
    var lines: [String] {
        transcript
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var translationLines: [String] {
        translation
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Playback start inside the media file.
    var startSeconds: Double { mediaStartSeconds ?? 0 }

    var characterCount: Int { transcript.count }

    var displaySeries: String { series.isEmpty ? "素材库" : series }

}

// MARK: - Tokens

enum TokenKind: String, Codable, Hashable {
    case word
    case particle
    case punctuation
    case number
    case latin
    case unknown

    var isTappable: Bool { self != .punctuation }
}

/// A tappable unit produced by the tokenizer.
struct ClipToken: Identifiable, Hashable {
    let id: Int
    let text: String
    let lemma: String?
    let reading: String?
    let romaji: String?
    let entryID: String?
    let kind: TokenKind
    /// Conjugation description when the surface had to be deinflected, e.g. "て形".
    let formation: String?
    let characterRange: Range<Int>

    var lookupKey: String { lemma ?? text }
    var romajiText: String { romaji ?? Kana.romaji(reading ?? text) }
}

// MARK: - Difficulty metrics

/// Difficulty of a clip, derived from its vocabulary rather than hand-labelled.
struct ClipMetrics: Hashable {
    let level: JLPTLevel
    /// Continuous difficulty 1 (N5) ... 5 (N1).
    let levelRank: Double
    let tokenCount: Int
    let unknownRatio: Double
    let uniqueWordCount: Int
}

/// Per-line segmentation result, cached per clip.
struct ClipAnalysis {
    let lines: [[ClipToken]]
    let allTokens: [ClipToken]
    let metrics: ClipMetrics
}
