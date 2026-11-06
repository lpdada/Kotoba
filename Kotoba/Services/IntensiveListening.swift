import Foundation

// MARK: - Shadowing records

enum ShadowingRating: String, Codable, CaseIterable, Identifiable {
    case gotIt
    case practiceAgain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gotIt: return "跟上了"
        case .practiceAgain: return "再来一次"
        }
    }
}

/// One recorded attempt at shadowing a single sentence.
///
/// The audio itself lives as a file in the app's Documents folder; this record
/// only keeps the file name plus the text that was practiced, so the entry stays
/// meaningful even if the audio later disappears (restore on another device).
struct ShadowingRecord: Identifiable, Codable, Hashable {
    let id: String
    let clipID: String
    let sentenceIndex: Int
    let japanese: String
    let fileName: String
    let durationSeconds: Double
    var rating: ShadowingRating
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        clipID: String,
        sentenceIndex: Int,
        japanese: String,
        fileName: String,
        durationSeconds: Double,
        rating: ShadowingRating = .practiceAgain,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.clipID = clipID
        self.sentenceIndex = sentenceIndex
        self.japanese = japanese
        self.fileName = fileName
        self.durationSeconds = durationSeconds
        self.rating = rating
        self.createdAt = createdAt
    }
}

// MARK: - Sentences

/// One practice unit inside a clip: a single sentence with its own time window.
struct IntensiveSentence: Identifiable, Hashable {
    let id: String
    let index: Int
    /// Absolute seconds in the media file.
    let start: Double
    let end: Double
    let japanese: String
    let translation: String?

    var duration: Double { max(end - start, 0.3) }

    var timeLabel: String {
        String(format: "%02d:%04.1f", Int(start) / 60, start.truncatingRemainder(dividingBy: 60))
    }
}

/// Builds the sentence list for intensive practice.
///
/// Preference order:
/// 1. real cue windows captured at subtitle import (`lineTimings`),
/// 2. otherwise the clip's own window, divided by character count.
/// Long lines that contain several 。！？ are split further so one practice unit
/// never hides two sentences.
enum IntensiveSentenceBuilder {
    static func build(for clip: Clip) -> [IntensiveSentence] {
        let lines = clip.lines
        guard !lines.isEmpty else { return [] }

        let translations = clip.translationLines
        let clipStart = clip.startSeconds
        let clipSpan = max(clip.durationSeconds, 0.5)
        let timings = clip.lineTimings

        var sentences: [IntensiveSentence] = []
        var index = 0

        for (lineIndex, line) in lines.enumerated() {
            let parts = split(line)
            guard !parts.isEmpty else { continue }

            let window: (start: Double, end: Double)
            if let timings, timings.count == lines.count, lineIndex < timings.count {
                let timing = timings[lineIndex]
                window = (max(timing.start, clipStart), max(timing.end, timing.start + 0.3))
            } else {
                let ratio = clipSpan / Double(max(lines.count, 1))
                window = (clipStart + ratio * Double(lineIndex), clipStart + ratio * Double(lineIndex + 1))
            }

            let totalCharacters = max(parts.reduce(0) { $0 + $1.count }, 1)
            var cursor = window.start
            for (partIndex, part) in parts.enumerated() {
                let share = Double(part.count) / Double(totalCharacters)
                let start = cursor
                let end = partIndex == parts.count - 1
                    ? max(window.end, start + 0.3)
                    : max(start + share * (window.end - window.start), start + 0.3)
                cursor = end
                sentences.append(
                    IntensiveSentence(
                        id: "\(clip.id)-s\(index)",
                        index: index,
                        start: start,
                        end: end,
                        japanese: part,
                        translation: translations[safe: lineIndex]
                    )
                )
                index += 1
            }
        }
        return sentences
    }

    /// Splits a line on Japanese/ASCII sentence-final punctuation, keeping it.
    static func split(_ line: String) -> [String] {
        let terminators: Set<Character> = ["。", "！", "？", "!", "?", "…", "‥"]
        var parts: [String] = []
        var buffer = ""
        for character in line {
            buffer.append(character)
            if terminators.contains(character) {
                let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { parts.append(trimmed) }
                buffer = ""
            }
        }
        let tail = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { parts.append(tail) }
        return parts
    }
}

// MARK: - Playback state machine

enum IntensiveAction: Equatable {
    case replay
    case advance(Int)
    case pause
    case finished
}

/// Drives sentence-by-sentence playback. Pure value type so the ordering rules
/// (repeat count, A-B loop, auto pause, end of clip) can be asserted on any host.
struct IntensiveEngine {
    private(set) var sentences: [IntensiveSentence]
    private(set) var currentIndex: Int
    private(set) var loopCurrent: Bool
    private(set) var autoPauseAtEnd: Bool
    private(set) var repeatTarget: Int
    private(set) var completedRepeats: Int
    private(set) var isAwaitingUser: Bool

    init(
        sentences: [IntensiveSentence],
        currentIndex: Int = 0,
        repeatTarget: Int = 1,
        autoPauseAtEnd: Bool = true,
        loopCurrent: Bool = false
    ) {
        self.sentences = sentences
        self.currentIndex = min(max(currentIndex, 0), max(sentences.count - 1, 0))
        self.repeatTarget = min(max(repeatTarget, 1), 3)
        self.autoPauseAtEnd = autoPauseAtEnd
        self.loopCurrent = loopCurrent
        self.completedRepeats = 0
        self.isAwaitingUser = false
    }

    var current: IntensiveSentence? {
        guard sentences.indices.contains(currentIndex) else { return nil }
        return sentences[currentIndex]
    }

    var isLast: Bool { currentIndex >= sentences.count - 1 }

    var progress: Double {
        guard !sentences.isEmpty else { return 0 }
        return Double(currentIndex + 1) / Double(sentences.count)
    }

    /// Repeats already finished for the current sentence, 1-based for display.
    var repeatLabel: String {
        let done = min(completedRepeats + 1, max(repeatTarget, 1))
        return "\(done)/\(repeatTarget)"
    }

    // MARK: Navigation

    @discardableResult
    mutating func select(_ index: Int) -> IntensiveSentence? {
        guard sentences.indices.contains(index) else { return nil }
        currentIndex = index
        resetProgress()
        return sentences[index]
    }

    @discardableResult
    mutating func next() -> IntensiveSentence? {
        guard currentIndex + 1 < sentences.count else { return nil }
        currentIndex += 1
        resetProgress()
        return sentences[currentIndex]
    }

    @discardableResult
    mutating func previous() -> IntensiveSentence? {
        guard currentIndex > 0 else { return nil }
        currentIndex -= 1
        resetProgress()
        return sentences[currentIndex]
    }

    // MARK: Options

    mutating func setLoop(_ enabled: Bool) {
        loopCurrent = enabled
    }

    mutating func setAutoPause(_ enabled: Bool) {
        autoPauseAtEnd = enabled
        if !enabled { isAwaitingUser = false }
    }

    mutating func setRepeat(_ count: Int) {
        repeatTarget = min(max(count, 1), 3)
        completedRepeats = min(completedRepeats, repeatTarget - 1)
    }

    mutating func resume() {
        isAwaitingUser = false
    }

    mutating func restartCurrent() {
        resetProgress()
    }

    // MARK: Decide what to do when the playhead leaves the current sentence

    mutating func handleSentenceEnd() -> IntensiveAction {
        completedRepeats += 1

        // A-B loop means "keep repeating this sentence until I turn it off".
        let target = loopCurrent ? Int.max : repeatTarget
        if completedRepeats < target {
            return .replay
        }

        completedRepeats = 0
        if autoPauseAtEnd {
            isAwaitingUser = true
            return .pause
        }
        if currentIndex + 1 < sentences.count {
            currentIndex += 1
            return .advance(currentIndex)
        }
        return .finished
    }

    private mutating func resetProgress() {
        completedRepeats = 0
        isAwaitingUser = false
    }
}
