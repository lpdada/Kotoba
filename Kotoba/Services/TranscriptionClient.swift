import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Settings

/// Optional self-hosted transcription endpoint.
///
/// Off by default and empty by design: Kotoba ships no server address, no token
/// and no key. With no address the feature stays disabled and every existing
/// flow keeps working offline.
/// The personal deployment this build ships pre-filled with. It is a public
/// hostname (no secret); the field stays editable and clearing it disables both
/// server synthesis and server transcription.
enum ServerDefaults {
    static let baseURL = "https://asr.ysloving.com"
}

struct TranscriptionSettings: Codable, Hashable {
    var isEnabled: Bool = false
    var serverURL: String = ServerDefaults.baseURL
    var timeoutSeconds: Int = 90
    var translateToChinese: Bool = true

    static let disabled = TranscriptionSettings()

    /// Trimmed address without a trailing slash; a scheme-less host becomes HTTPS.
    var normalizedServerURL: String {
        var value = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        if !value.isEmpty, !value.contains("://") { value = "https://" + value }
        return value
    }

    /// Accepts either a base (`https://host`) or a full endpoint (`…/transcribe`).
    var endpointURL: URL? {
        let base = normalizedServerURL
        guard !base.isEmpty else { return nil }
        let candidate = base.lowercased().hasSuffix("/transcribe") ? base : base + "/transcribe"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    var healthURL: URL? {
        let base = normalizedServerURL
        guard !base.isEmpty else { return nil }
        return URL(string: base + "/health")
    }

    var isConfigured: Bool { isEnabled && endpointURL != nil }

    /// Clamped so a typo cannot turn into a five-minute hang.
    var timeoutInterval: TimeInterval { TimeInterval(min(max(timeoutSeconds, 15), 300)) }

    var statusLabel: String {
        if !isEnabled { return "已关闭" }
        if endpointURL == nil { return "地址无效" }
        return "已启用"
    }
}

// MARK: - Wire model

struct TranscriptionLine: Codable, Hashable, Identifiable {
    let start: Double
    let end: Double
    let japanese: String
    let chinese: String?

    var id: String { "\(start)-\(japanese)" }

    var subtitleCue: SubtitleCue {
        SubtitleCue(start: start, end: max(end, start + 0.3), text: japanese)
    }
}

struct TranscriptionResult: Equatable {
    let lines: [TranscriptionLine]
    let language: String?
    let provider: String?

    var japaneseText: String { lines.map(\.japanese).joined(separator: "\n") }

    /// Chinese column only when every line actually came back translated.
    var chineseText: String? {
        let translated = lines.compactMap(\.chinese).filter { !$0.isEmpty }
        guard translated.count == lines.count, !translated.isEmpty else { return nil }
        return translated.joined(separator: "\n")
    }
}

enum TranscriptionError: LocalizedError, Equatable {
    case notConfigured
    case invalidURL
    case http(status: Int, body: String)
    case decoding
    case empty
    case network(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "没有启用服务器转写。可以在「设置 › 云端转写」里填写自己的地址。"
        case .invalidURL:
            return "转写地址无效：需要 http(s):// 的完整地址。"
        case .http(let status, let body):
            let snippet = body.isEmpty ? "" : "：\(body.prefix(120))"
            return "转写服务返回 \(status)\(snippet)"
        case .decoding:
            return "转写服务返回的不是约定格式（缺少 lines 数组）。"
        case .empty:
            return "转写服务没有返回任何字幕行。"
        case .network(let message):
            return "连接转写服务失败：\(message)"
        case .cancelled:
            return "转写已取消。"
        }
    }
}

// MARK: - Client

/// Client for the documented `/transcribe` contract (see README).
///
/// Transport and sleep are injectable so retry/backoff and parsing can be tested
/// without a server or real clock.
struct TranscriptionClient {
    var settings: TranscriptionSettings
    /// Returns the body and the HTTP status. Platform-neutral so tests can fabricate
    /// responses without constructing `HTTPURLResponse`.
    var send: (URLRequest) async throws -> (Data, Int)
    var sleep: (Double) async throws -> Void

    static let maxAttempts = 3

    init(
        settings: TranscriptionSettings,
        send: @escaping (URLRequest) async throws -> (Data, Int) = TranscriptionClient.defaultSend,
        sleep: @escaping (Double) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
        }
    ) {
        self.settings = settings
        self.send = send
        self.sleep = sleep
    }

    static func defaultSend(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.network("响应不是 HTTP")
        }
        return (data, http.statusCode)
    }

    // MARK: Request

    func makeRequest(videoID: String) throws -> URLRequest {
        guard settings.isEnabled else { throw TranscriptionError.notConfigured }
        guard let url = settings.endpointURL else {
            throw settings.isEnabled ? TranscriptionError.invalidURL : TranscriptionError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = settings.timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var payload: [String: Any] = [
            "video_id": videoID,
            "format": "lines-v1"
        ]
        if settings.translateToChinese {
            payload["translate_to"] = "zh"
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    // MARK: Call

    func transcribe(videoID: String) async throws -> TranscriptionResult {
        let request = try makeRequest(videoID: videoID)
        var attempt = 0
        while true {
            attempt += 1
            do {
                let (data, statusCode) = try await send(request)
                if (200...299).contains(statusCode) {
                    return try Self.decode(data)
                }
                if statusCode == 429 || (500...599).contains(statusCode) {
                    let error = TranscriptionError.http(status: statusCode, body: Self.snippet(data))
                    if attempt >= Self.maxAttempts { throw error }
                    try await sleep(Self.backoff(attempt: attempt))
                    continue
                }
                throw TranscriptionError.http(status: statusCode, body: Self.snippet(data))
            } catch let error as TranscriptionError {
                throw error
            } catch is CancellationError {
                throw TranscriptionError.cancelled
            } catch {
                if attempt >= Self.maxAttempts {
                    throw TranscriptionError.network(error.localizedDescription)
                }
                try await sleep(Self.backoff(attempt: attempt))
                continue
            }
        }
    }

    /// 1 s, then 3 s. Deterministic so it can be asserted.
    static func backoff(attempt: Int) -> Double {
        attempt <= 1 ? 1 : 3
    }

    // MARK: Decoding

    static func decode(_ data: Data) throws -> TranscriptionResult {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw TranscriptionError.decoding
        }
        let raw = (root["lines"] as? [[String: Any]])
            ?? (root["segments"] as? [[String: Any]])
            ?? []
        var lines: [TranscriptionLine] = []
        for item in raw {
            let start = number(item["start"] ?? item["start_seconds"] ?? item["t"]) ?? 0
            let end = number(item["end"] ?? item["end_seconds"]) ?? (start + 2)
            let japanese = (item["japanese"] as? String)
                ?? (item["ja"] as? String)
                ?? (item["text"] as? String)
                ?? ""
            let chinese = (item["chinese"] as? String)
                ?? (item["zh"] as? String)
                ?? (item["translation"] as? String)
            let trimmed = japanese.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            lines.append(
                TranscriptionLine(
                    start: max(start, 0),
                    end: max(end, start + 0.3),
                    japanese: trimmed,
                    chinese: chinese?.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        }
        guard !lines.isEmpty else { throw TranscriptionError.empty }
        return TranscriptionResult(
            lines: lines.sorted { $0.start < $1.start },
            language: root["language"] as? String,
            provider: root["provider"] as? String
        )
    }

    static func snippet(_ data: Data, limit: Int = 160) -> String {
        guard let text = String(data: data, encoding: .utf8) else { return "" }
        return String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }

    private static func number(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
