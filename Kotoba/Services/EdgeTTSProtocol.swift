import Foundation

// MARK: - Voices

/// Voices that Microsoft's Edge read-aloud endpoint actually exposes for Japanese.
///
/// Verified against the service's public voice list: only `ja-JP-NanamiNeural`
/// and `ja-JP-KeitaNeural` are offered.  A custom id is allowed so the user can
/// switch if Microsoft adds more later.
enum EdgeTTSVoice: String, Codable, CaseIterable, Identifiable {
    case nanami
    case keita
    case custom

    var id: String { rawValue }

    var neuralName: String {
        switch self {
        case .nanami: return "ja-JP-NanamiNeural"
        case .keita: return "ja-JP-KeitaNeural"
        case .custom: return ""
        }
    }

    var title: String {
        switch self {
        case .nanami: return "Nanami（女声）"
        case .keita: return "Keita（男声）"
        case .custom: return "自定义语音 ID"
        }
    }
}

/// How read-aloud is produced.
enum ReadAloudMode: String, Codable, CaseIterable, Identifiable {
    /// Ask Microsoft's endpoint directly. Works only if the handshake is accepted.
    case edgeDirect
    /// Ask the user's own proxy (POST {base}/tts). Recommended when configured.
    case server
    /// Never touch the network.
    case systemOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .edgeDirect: return "Edge 直连"
        case .server: return "服务器合成（推荐）"
        case .systemOnly: return "仅系统语音"
        }
    }

    var detail: String {
        switch self {
        case .edgeDirect: return "直接请求 Microsoft 的免费朗读接口；被拒时自动改用系统语音"
        case .server: return "请求你自己的 edge-tts 代理（POST /tts）；失败时自动改用系统语音"
        case .systemOnly: return "完全不联网，始终使用系统语音"
        }
    }
}

/// Per-device speech preferences. Stored as an optional snapshot field so older
/// backups keep decoding.
struct VoiceOptions: Codable, Hashable {
    /// Legacy flag kept so old backups keep meaning: false used to mean "system only".
    var preferEdge: Bool = true
    var voice: EdgeTTSVoice = .nanami
    var customVoiceID: String = ""
    /// Optional so backups written before the 3-way switch still decode.
    var mode: ReadAloudMode?
    /// Empty means "reuse the transcription server address".
    var serverURL: String = ""

    static let `default` = VoiceOptions()

    /// The address to use for server synthesis: own field first, then the
    /// transcription server, so one host is enough for both features.
    func resolvedServerURL(transcriptionURL: String) -> String {
        let own = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !own.isEmpty { return own }
        return transcriptionURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Mode actually used, after honouring the legacy flag and an empty address.
    func effectiveMode(transcriptionURL: String) -> ReadAloudMode {
        let resolved = mode
        if let resolved { return Self.normalising(resolved, address: resolvedServerURL(transcriptionURL: transcriptionURL)) }
        // No explicit choice: migrate legacy flag, then follow the recommendation.
        if !preferEdge { return .systemOnly }
        let address = resolvedServerURL(transcriptionURL: transcriptionURL)
        return address.isEmpty ? .edgeDirect : .server
    }

    /// A server mode without an address is useless, so fall back to direct Edge,
    /// which itself falls back to the system voice.
    static func normalising(_ mode: ReadAloudMode, address: String) -> ReadAloudMode {
        if mode == .server, address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .edgeDirect
        }
        return mode
    }

    /// The voice id actually sent on the wire.
    var effectiveVoiceID: String {
        if voice == .custom {
            let trimmed = customVoiceID.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed
        }
        return voice.neuralName
    }

    var isUsable: Bool { !effectiveVoiceID.isEmpty }
}

// MARK: - SSML

enum EdgeTTSProtocol {
    /// The app's speech rate is an AVSpeechUtterance-style value (0.30–0.62,
    /// neutral 0.45). Map it to SSML `prosody rate` percent, clamped to ±50 %.
    static func ratePercent(forSpeechRate rate: Double) -> Int {
        let percent = (rate - 0.45) * 200
        return Int(percent.rounded()).clamped(to: -50...50)
    }

    static func ssml(text: String, voiceID: String, ratePercent: Int, pitchHz: Int = 0) -> String {
        let clamped = ratePercent.clamped(to: -50...50)
        let signRate = clamped >= 0 ? "+\(clamped)%" : "\(clamped)%"
        let pitch = pitchHz == 0 ? "+0Hz" : (pitchHz > 0 ? "+\(pitchHz)Hz" : "\(pitchHz)Hz")
        return """
        <speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="ja-JP">\
        <voice name="\(escape(voiceID))">\
        <prosody rate="\(signRate)" pitch="\(pitch)">\(escape(text))</prosody>\
        </voice></speak>
        """
    }

    /// Escapes the five XML metacharacters; captions and dictionary text can contain them.
    static func escape(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.count + 8)
        for character in text {
            switch character {
            case "&": output += "&amp;"
            case "<": output += "&lt;"
            case ">": output += "&gt;"
            case "\"": output += "&quot;"
            case "'": output += "&apos;"
            default: output.append(character)
            }
        }
        return output
    }

    static let audioFormat = "audio-24khz-48kbitrate-mono-mp3"

    /// Cheap sniff so a JSON error body is never handed to the audio player.
    static func looksLikeMP3(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        if data.count >= 3,
           data[data.startIndex] == 0x49,
           data[data.startIndex + 1] == 0x44,
           data[data.startIndex + 2] == 0x33 {
            return true
        }
        return data[data.startIndex] == 0xFF && (data[data.startIndex + 1] & 0xE0) == 0xE0
    }

    /// `speech.config` body, exactly as the service expects it.
    static func configMessage() -> String {
        """
        {"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},"outputFormat":"\(audioFormat)"}}}}
        """
    }

    static func endpoint(videoIndependent connectionID: String) -> String {
        "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=\(trustedClientToken)&ConnectionId=\(connectionID)"
    }

    /// Public, non-secret client token that the Edge extension itself ships with.
    static let trustedClientToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"

    /// Browser UA. Microsoft rejects handshakes whose UA version disagrees with the
    /// service's expectations, so the version is kept in one place.
    static let userAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0"
    static let origin = "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold"
}

// MARK: - Frames

/// One websocket message from the service: `[2-byte header length][header][payload]`.
struct EdgeTTSFrame: Equatable {
    let path: String
    let payload: Data

    var isAudio: Bool { path == "audio" }
    var isTurnEnd: Bool { path == "turn.end" }
    var isError: Bool { path == "turn.start" || path.hasPrefix("response") || payloadStartsWithError }

    private var payloadStartsWithError: Bool {
        guard let text = String(data: payload.prefix(32), encoding: .utf8) else { return false }
        return text.hasPrefix("Unable") || text.hasPrefix("Error")
    }

    /// Parses a binary frame. Returns nil for frames shorter than the length prefix.
    static func parse(_ data: Data) -> EdgeTTSFrame? {
        guard data.count >= 2 else { return nil }
        let headerLength = Int(data[data.startIndex]) << 8 | Int(data[data.startIndex + 1])
        guard data.count >= 2 + headerLength else { return nil }
        let headerStart = data.startIndex + 2
        let headerEnd = headerStart + headerLength
        let header = String(data: data[headerStart..<headerEnd], encoding: .utf8) ?? ""
        let payload = Data(data[headerEnd...])
        // Note: Swift clusters "\r\n" into a single Character, so normalise before splitting.
        let path = header
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .first { $0.lowercased().hasPrefix("path:") }
            .map { substring -> String in
                String(substring.dropFirst("path:".count)).trimmingCharacters(in: .whitespaces)
            } ?? ""
        return EdgeTTSFrame(path: path, payload: payload)
    }

    /// Builds a frame — used by tests and by the message logger.
    static func make(path: String, payload: Data) -> Data {
        let header = "X-RequestId:test\r\nContent-Type:application/octet-stream\r\nPath:\(path)\r\n\r\n"
        var data = Data()
        let length = UInt16(clamping: header.utf8.count)
        data.append(UInt8(length >> 8))
        data.append(UInt8(length & 0xFF))
        data.append(contentsOf: header.utf8)
        data.append(payload)
        return data
    }
}

// MARK: - Text chunking

/// The live proxy rejects bodies whose text exceeds 1000 characters (verified:
/// 400 with `String should have at most 1000 characters`). Network synthesis
/// therefore splits long text at sentence boundaries and plays the pieces in
/// order instead of failing over to the system voice.
enum TextChunker {
    static let limit = 1_000

    static func chunks(of text: String, limit: Int = TextChunker.limit) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed.isEmpty ? [] : [trimmed] }

        let terminators: Set<Character> = ["。", "！", "？", "!", "?", "\n"]
        var pieces: [String] = []
        var buffer = ""
        for character in trimmed {
            buffer.append(character)
            if terminators.contains(character) {
                pieces.append(buffer)
                buffer = ""
            }
        }
        if !buffer.isEmpty { pieces.append(buffer) }

        var result: [String] = []
        var current = ""
        for piece in pieces {
            if piece.count > limit {
                // Extremely long single sentence: hard-split it.
                if !current.isEmpty { result.append(current); current = "" }
                var remaining = Substring(piece)
                while remaining.count > limit {
                    let cut = remaining.index(remaining.startIndex, offsetBy: limit)
                    result.append(String(remaining[..<cut]))
                    remaining = remaining[cut...]
                }
                current = String(remaining)
                continue
            }
            if current.count + piece.count > limit {
                result.append(current)
                current = piece
            } else {
                current += piece
            }
        }
        if !current.isEmpty { result.append(current) }
        return result.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

// MARK: - Cache keys

enum EdgeTTSCacheKey {
    /// `voice|rate|text` → hex digest. Stable across launches so repeats hit cache.
    static func make(voiceID: String, ratePercent: Int, text: String) -> String {
        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let material = "\(voiceID)|\(ratePercent)|\(normalizedText)"
        return SHA256Hex.digest(Data(material.utf8))
    }
}

// MARK: - Fallback policy

enum EdgeTTSDecision: Equatable {
    case useEdge
    case useSystem(reason: String)

    var shouldUseEdge: Bool { self == .useEdge }

    var reason: String {
        switch self {
        case .useEdge: return ""
        case .useSystem(let reason): return reason
        }
    }
}

enum EdgeTTSRouter {
    /// Cooldown after a failed attempt, so studying never waits on a broken
    /// network round-trip over and over. Tracked per engine by the caller, so a
    /// server failure cools only the server path and a direct failure only the
    /// direct path.
    static let failureCooldown: Double = 60

    static func decide(
        preferEdge: Bool,
        voiceUsable: Bool,
        online: Bool,
        secondsSinceLastFailure: Double?
    ) -> EdgeTTSDecision {
        guard preferEdge else { return .useSystem(reason: "已在设置里关闭 Edge TTS") }
        guard voiceUsable else { return .useSystem(reason: "没有可用的语音 ID") }
        guard online else { return .useSystem(reason: "当前离线") }
        if let secondsSinceLastFailure, secondsSinceLastFailure < failureCooldown {
            return .useSystem(reason: "刚刚失败过，临时改用系统语音")
        }
        return .useEdge
    }

    static func clampTimeout(_ seconds: Double) -> Double {
        min(max(seconds, 5), 30)
    }
}

// MARK: - Small utilities

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// Minimal SHA-256 so cache keys work on every platform (CryptoKit is Apple-only
/// and this keeps the logic file testable on Linux).
enum SHA256Hex {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    static func digest(_ data: Data) -> String {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var message = [UInt8](data)
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }

        var w = [UInt32](repeating: 0, count: 64)
        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            for index in 0..<16 {
                let offset = chunkStart + index * 4
                w[index] = UInt32(message[offset]) << 24
                    | UInt32(message[offset + 1]) << 16
                    | UInt32(message[offset + 2]) << 8
                    | UInt32(message[offset + 3])
            }
            for index in 16..<64 {
                let s0 = rotr(w[index - 15], 7) ^ rotr(w[index - 15], 18) ^ (w[index - 15] >> 3)
                let s1 = rotr(w[index - 2], 17) ^ rotr(w[index - 2], 19) ^ (w[index - 2] >> 10)
                w[index] = w[index - 16] &+ s0 &+ w[index - 7] &+ s1
            }

            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for index in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let temp1 = hh &+ s1 &+ ch &+ k[index] &+ w[index]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ temp1
                d = c; c = b; b = a; a = temp1 &+ temp2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }
        return h.map { String(format: "%08x", $0) }.joined()
    }

    private static func rotr(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value >> count) | (value << (32 - count))
    }
}

// MARK: - Audio cache

/// File cache for synthesized MP3s, keyed by voice + rate + text.
///
/// Foundation-only so the eviction policy can be exercised on Linux. The cap is
/// deliberately small (50 MB ≈ 2.5 hours of 48 kbps speech).
final class EdgeTTSCache {
    static let shared = EdgeTTSCache()

    let directory: URL
    let limitBytes: Int

    init(directory: URL? = nil, limitBytes: Int = 50 * 1024 * 1024) {
        self.limitBytes = limitBytes
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directory = base.appendingPathComponent("EdgeTTS", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func fileURL(forKey key: String) -> URL {
        directory.appendingPathComponent(key + ".mp3")
    }

    /// Cache hit, also refreshing the access date for LRU.
    func existing(forKey key: String) -> URL? {
        let url = fileURL(forKey: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return url
    }

    @discardableResult
    func store(_ data: Data, forKey key: String) throws -> URL {
        let url = fileURL(forKey: key)
        try data.write(to: url, options: .atomic)
        evictIfNeeded()
        return url
    }

    func currentSize() -> Int {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return items.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + size
        }
    }

    /// Least-recently-used eviction until the folder fits the cap.
    @discardableResult
    func evictIfNeeded() -> Int {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return 0 }

        struct Entry { let url: URL; let size: Int; let date: Date }
        var entries: [Entry] = items.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            return Entry(url: url, size: values.fileSize ?? 0, date: values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > limitBytes else { return 0 }

        entries.sort { $0.date < $1.date }
        var removed = 0
        for entry in entries where total > limitBytes {
            if (try? FileManager.default.removeItem(at: entry.url)) != nil {
                total -= entry.size
                removed += 1
            }
        }
        return removed
    }
}
