import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for the user's own edge-tts proxy.
///
/// Contract (deployed and owned by the user, not by this repository):
///   POST {base}/tts
///   {"text": "…", "voice": "ja-JP-NanamiNeural", "rate_percent": 0}
///   → 200 `audio/mpeg` (MP3 bytes); `GET {base}/health` for liveness.
///
/// Kotoba ships no address and no token; the URL is whatever the user typed
/// (or the transcription server they already configured).
final class ServerTTSService {
    enum Failure: LocalizedError {
        case notConfigured
        case invalidURL
        case http(status: Int, body: String)
        case emptyAudio
        case malformedAudio
        case textTooLong(limit: Int)
        case network(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "没有配置朗读服务器"
            case .invalidURL: return "朗读服务器地址无效"
            case .http(let status, let body):
                let snippet = body.isEmpty ? "" : "：\(body.prefix(120))"
                return "朗读服务器返回 \(status)\(snippet)"
            case .emptyAudio: return "朗读服务器没有返回音频"
            case .malformedAudio: return "朗读服务器返回的不是 MP3"
            case .textTooLong(let limit): return "这一段超过 \(limit) 字，已在本地切成多段朗读"
            case .network(let message): return "连接朗读服务器失败：\(message)"
            }
        }
    }

    var baseURL: String
    /// Injected in tests; returns body + status code (platform-neutral).
    var send: (URLRequest) async throws -> (Data, Int)

    init(
        baseURL: String,
        send: @escaping (URLRequest) async throws -> (Data, Int) = ServerTTSService.defaultSend
    ) {
        self.baseURL = baseURL
        self.send = send
    }

    static func defaultSend(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Failure.network("响应不是 HTTP")
        }
        return (data, http.statusCode)
    }

    // MARK: Request

    /// Accepts `https://host`, `https://host/`, a scheme-less `host`, or a full `…/tts`.
    var endpointURL: URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty else { return nil }
        // A bare host is the common typo; default to HTTPS instead of failing.
        if !base.contains("://") { base = "https://" + base }
        if !base.lowercased().hasSuffix("/tts") { base += "/tts" }
        guard let url = URL(string: base),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// The live proxy accepts at most 1000 characters per request.
    static let maxTextLength = TextChunker.limit

    func makeRequest(text: String, voiceID: String, ratePercent: Int, timeout: Double) throws -> URLRequest {
        guard text.count <= Self.maxTextLength else {
            throw Failure.textTooLong(limit: Self.maxTextLength)
        }
        guard let url = endpointURL else {
            throw endpointURL == nil && baseURL.trimmingCharacters(in: .whitespaces).isEmpty
                ? Failure.notConfigured
                : Failure.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = EdgeTTSRouter.clampTimeout(timeout)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        let payload: [String: Any] = [
            "text": text,
            "voice": voiceID,
            "rate_percent": ratePercent
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    // MARK: Call

    func audio(text: String, voiceID: String, ratePercent: Int, timeout: Double = 15) async throws -> Data {
        let request = try makeRequest(text: text, voiceID: voiceID, ratePercent: ratePercent, timeout: timeout)
        let data: Data
        let status: Int
        do {
            (data, status) = try await send(request)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.network(error.localizedDescription)
        }
        guard (200...299).contains(status) else {
            throw Failure.http(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        guard !data.isEmpty else { throw Failure.emptyAudio }
        guard EdgeTTSProtocol.looksLikeMP3(data) else { throw Failure.malformedAudio }
        return data
    }
}
