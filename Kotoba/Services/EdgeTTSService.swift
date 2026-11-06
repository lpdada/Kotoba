import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Network side of Edge read-aloud: one websocket, one SSML request, MP3 back.
///
/// Known limit: since 2025 the service rejects handshakes that lack
/// `Sec-MS-GEC` v2, an undocumented anti-abuse token. Kotoba sends the documented
/// handshake and lets any rejection fall back to the system voice; it does not
/// reimplement that token.
final class EdgeTTSService {
    enum Failure: LocalizedError {
        case rejected(status: Int)
        case timeout
        case emptyAudio
        case malformedAudio
        case cancelled

        var errorDescription: String? {
            switch self {
            case .rejected(let status): return "Edge TTS 拒绝握手（\(status)）"
            case .timeout: return "Edge TTS 超时"
            case .emptyAudio: return "Edge TTS 没有返回音频"
            case .malformedAudio: return "Edge TTS 返回的音频无法识别"
            case .cancelled: return "已取消"
            }
        }
    }

    private let cache: EdgeTTSCache
    private let session: URLSession

    init(cache: EdgeTTSCache = .shared, session: URLSession = .shared) {
        self.cache = cache
        self.session = session
    }

    /// Cache first, network second.
    func audio(for text: String, voiceID: String, ratePercent: Int, timeout: Double = 15) async throws -> URL {
        let key = EdgeTTSCacheKey.make(voiceID: voiceID, ratePercent: ratePercent, text: text)
        if let hit = cache.existing(forKey: key) { return hit }
        let data = try await synthesizeAudio(text: text, voiceID: voiceID, ratePercent: ratePercent, timeout: timeout)
        guard data.count > 256 else { throw Failure.emptyAudio }
        guard EdgeTTSProtocol.looksLikeMP3(data) else { throw Failure.malformedAudio }
        return try cache.store(data, forKey: key)
    }

    // MARK: Websocket

    func synthesizeAudio(text: String, voiceID: String, ratePercent: Int, timeout: Double) async throws -> Data {
        let deadline = EdgeTTSRouter.clampTimeout(timeout)
        let connectionID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        guard let url = URL(string: EdgeTTSProtocol.endpoint(videoIndependent: connectionID)) else {
            throw Failure.rejected(status: 0)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = deadline
        request.setValue(EdgeTTSProtocol.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(EdgeTTSProtocol.origin, forHTTPHeaderField: "Origin")
        request.setValue("ja-JP,ja;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        let task = session.webSocketTask(with: request)
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }

        let requestID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let timestamp = Self.timestamp()

        let config = "X-Timestamp:\(timestamp)\r\n"
            + "Content-Type:application/json; charset=utf-8\r\n"
            + "Path:speech.config\r\n\r\n"
            + EdgeTTSProtocol.configMessage()
        try await send(config, on: task, deadline: deadline)

        let ssml = "X-RequestId:\(requestID)\r\n"
            + "Content-Type:application/ssml+xml\r\n"
            + "X-Timestamp:\(timestamp)Z\r\n"
            + "Path:ssml\r\n\r\n"
            + EdgeTTSProtocol.ssml(text: text, voiceID: voiceID, ratePercent: ratePercent)
        try await send(ssml, on: task, deadline: deadline)

        var audio = Data()
        let started = Date()
        while true {
            if Date().timeIntervalSince(started) > deadline { throw Failure.timeout }
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await withTimeout(deadline) { try await task.receive() }
            } catch is CancellationError {
                throw Failure.timeout
            } catch let error as Failure {
                throw error
            } catch {
                // URLSession surfaces a close/handshake failure here.
                throw Failure.rejected(status: 0)
            }

            switch message {
            case .data(let data):
                guard let frame = EdgeTTSFrame.parse(data) else { continue }
                if frame.isAudio {
                    audio.append(frame.payload)
                } else if frame.isTurnEnd {
                    return audio
                }
            case .string(let text):
                if text.contains("Path:turn.end") { return audio }
                if text.contains("Path:turn.start") == false, text.contains("\"error\"") {
                    throw Failure.rejected(status: 200)
                }
            @unknown default:
                continue
            }
        }
    }

    private func send(_ text: String, on task: URLSessionWebSocketTask, deadline: Double) async throws {
        do {
            try await withTimeout(deadline) { try await task.send(.string(text)) }
        } catch {
            throw Failure.timeout
        }
    }

    private func withTimeout<T>(_ seconds: Double, _ operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(seconds, 0.1) * 1_000_000_000))
                throw Failure.timeout
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw Failure.timeout }
            return first
        }
    }

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter.string(from: Date())
    }
}
