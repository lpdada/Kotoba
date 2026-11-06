import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client-side caption fetching for a YouTube video.
///
/// Kotoba has no server, so it only uses what the public watch page and the
/// public timedtext endpoints expose. When YouTube withholds the caption tracks
/// (or the request is blocked), the caller falls back to pasting lines manually —
/// there is no server-side transcription and no bundled third-party catalog.
struct YouTubeCaptionTrack: Hashable {
    let languageCode: String
    let kind: String
    let baseURL: String

    var isAutomatic: Bool { kind == "asr" }
    var displayName: String {
        let language = Locale.current.localizedString(forLanguageCode: languageCode) ?? languageCode
        return isAutomatic ? "\(language)（自动生成）" : language
    }
}

enum YouTubeCaptionError: LocalizedError {
    case noTracks
    case badURL
    case blocked
    case emptyTranscript
    case network(String)

    var errorDescription: String? {
        switch self {
        case .noTracks:
            return "这个视频没有公开字幕轨道。可以手动粘贴日文字幕，或换一个视频。"
        case .badURL:
            return "视频链接无法解析。"
        case .blocked:
            return "YouTube 拒绝了这次字幕请求（常见于无登录的自动生成字幕）。请手动粘贴字幕。"
        case .emptyTranscript:
            return "字幕轨道是空的，可能只包含自动生成的时间轴占位。"
        case .network(let message):
            return "网络请求失败：\(message)"
        }
    }
}

/// Pure parsing + a network step that can be injected (the harness feeds fixtures).
struct YouTubeCaptionService {
    /// Fetches raw bytes. Injected so the parsing logic is testable offline.
    var fetcher: (URL) async throws -> Data

    init(fetcher: @escaping (URL) async throws -> Data = YouTubeCaptionService.defaultFetcher) {
        self.fetcher = fetcher
    }

    static func defaultFetcher(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("ja,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 429 || http.statusCode == 403 {
            throw YouTubeCaptionError.blocked
        }
        return data
    }

    // MARK: Watch page -> tracks

    static let watchPageURL = "https://www.youtube.com/watch?v="

    /// Extracts caption tracks from the watch page HTML.
    static func tracks(fromWatchHTML html: String) throws -> [YouTubeCaptionTrack] {
        guard let anchor = html.range(of: "captionTracks") else { throw YouTubeCaptionError.noTracks }
        let tail = html[anchor.lowerBound...].prefix(20_000)
        var tracks: [YouTubeCaptionTrack] = []
        var cursor = tail.startIndex
        while let hit = tail.range(of: "\"baseUrl\":\"", range: cursor..<tail.endIndex) {
            let valueStart = hit.upperBound
            guard let valueEnd = tail[valueStart...].firstIndex(of: "\"") else { break }
            let rawURL = String(tail[valueStart..<valueEnd])
            // The language/kind of a track follow its baseUrl in the same object.
            let window = tail[valueEnd...].prefix(600)
            let language = Self.firstMatch(in: window, pattern: "\"languageCode\":\"([a-zA-Z-]{2,10})\"") ?? "und"
            let kind = Self.firstMatch(in: window, pattern: "\"kind\":\"([a-z]{2,6})\"") ?? ""
            tracks.append(
                YouTubeCaptionTrack(
                    languageCode: language,
                    kind: kind,
                    baseURL: rawURL.replacingOccurrences(of: "\\u0026", with: "&")
                )
            )
            cursor = valueEnd
        }
        guard !tracks.isEmpty else { throw YouTubeCaptionError.noTracks }
        return tracks
    }

    /// Japanese first, then anything else; hand-made before automatic.
    static func preferredTrack(_ tracks: [YouTubeCaptionTrack]) -> YouTubeCaptionTrack? {
        let japanese = tracks.filter { $0.languageCode.hasPrefix("ja") }
        if let manual = japanese.first(where: { !$0.isAutomatic }) { return manual }
        if let auto = japanese.first { return auto }
        if let manual = tracks.first(where: { !$0.isAutomatic }) { return manual }
        return tracks.first
    }

    // MARK: Timedtext -> cues

    /// Timedtext `fmt=json3` payload.
    static func cues(fromJSON3 data: Data) -> [SubtitleCue] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = object["events"] as? [[String: Any]] else { return [] }
        var cues: [SubtitleCue] = []
        for event in events {
            guard let segments = event["segs"] as? [[String: Any]] else { continue }
            let text = segments.compactMap { $0["utf8"] as? String }.joined()
            let normalized = normalize(text)
            guard !normalized.isEmpty else { continue }
            let start = (event["tStartMs"] as? Double ?? 0) / 1000
            let duration = (event["dDurationMs"] as? Double ?? 0) / 1000
            let end = start + max(duration, 0.6)
            if let previous = cues.last, previous.text == normalized { continue }
            cues.append(SubtitleCue(start: start, end: end, text: normalized))
        }
        return cues
    }

    /// Legacy timedtext XML: `<text start="0.5" dur="2.1">…</text>`.
    static func cues(fromXML string: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        var cursor = string.startIndex
        while let open = string.range(of: "<text", range: cursor..<string.endIndex) {
            guard let tagEnd = string[open.upperBound...].firstIndex(of: ">") else { break }
            guard let close = string.range(of: "</text>", range: tagEnd..<string.endIndex) else { break }
            let attributes = String(string[open.upperBound..<tagEnd])
            let body = String(string[string.index(after: tagEnd)..<close.lowerBound])
            let start = Double(firstMatch(in: Substring(attributes), pattern: "start=\"([0-9.]+)\"") ?? "") ?? 0
            let duration = Double(firstMatch(in: Substring(attributes), pattern: "dur=\"([0-9.]+)\"") ?? "") ?? 0
            // Captions are sometimes double-escaped (`&amp;lt;i&amp;gt;`), so decode,
            // strip, then decode once more before normalising.
            let text = normalize(decodeEntities(stripTags(decodeEntities(stripTags(body)))))
            if !text.isEmpty {
                if let previous = cues.last, previous.text == text {
                    // skip duplicate cue
                } else {
                    cues.append(SubtitleCue(start: start, end: start + max(duration, 0.6), text: text))
                }
            }
            cursor = close.upperBound
        }
        return cues
    }

    // MARK: Orchestration

    func fetchTracks(videoID: String) async throws -> [YouTubeCaptionTrack] {
        guard let url = URL(string: Self.watchPageURL + videoID) else { throw YouTubeCaptionError.badURL }
        let data: Data
        do {
            data = try await fetcher(url)
        } catch let error as YouTubeCaptionError {
            throw error
        } catch {
            throw YouTubeCaptionError.network(error.localizedDescription)
        }
        let html = String(data: data, encoding: .utf8) ?? ""
        return try Self.tracks(fromWatchHTML: html)
    }

    /// Japanese captions for a video id, with per-line timings.
    func fetchCues(videoID: String) async throws -> (track: YouTubeCaptionTrack, cues: [SubtitleCue]) {
        let tracks = try await fetchTracks(videoID: videoID)
        guard let track = Self.preferredTrack(tracks), let base = URL(string: track.baseURL) else {
            throw YouTubeCaptionError.noTracks
        }
        guard let jsonURL = URL(string: track.baseURL + (track.baseURL.contains("?") ? "&" : "?") + "fmt=json3"),
              let jsonData = try? await fetcher(jsonURL) else {
            throw YouTubeCaptionError.badURL
        }
        var cues = Self.cues(fromJSON3: jsonData)
        if cues.isEmpty, let xmlData = try? await fetcher(base) {
            cues = Self.cues(fromXML: String(data: xmlData, encoding: .utf8) ?? "")
        }
        guard !cues.isEmpty else { throw YouTubeCaptionError.emptyTranscript }
        return (track, cues)
    }

    // MARK: Text helpers

    static func normalize(_ text: String) -> String {
        var value = text
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        value = decodeEntities(value)
        while value.contains("  ") {
            value = value.replacingOccurrences(of: "  ", with: " ")
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stripTags(_ text: String) -> String {
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

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func firstMatch(in text: Substring, pattern: String) -> String? {
        let haystack = String(text)
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(haystack.startIndex..<haystack.endIndex, in: haystack)
        guard let match = regex.firstMatch(in: haystack, options: [], range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: haystack) else { return nil }
        return String(haystack[captured])
    }
}
