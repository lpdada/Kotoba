import Foundation

/// One sentence's four-step Echo routine: listen, understand, imitate, compare.
///
/// Pure value type so the step order, wrap-around and completion rules can be
/// asserted without a UI or audio hardware.
enum EchoStep: Int, CaseIterable, Identifiable {
    case listen
    case understand
    case imitate
    case compare

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .listen: return "听"
        case .understand: return "懂"
        case .imitate: return "模仿"
        case .compare: return "对比"
        }
    }

    var detail: String {
        switch self {
        case .listen: return "先不看字幕，只听这一句"
        case .understand: return "看字幕与翻译，弄懂每个词"
        case .imitate: return "跟着原句读一遍并录下来"
        case .compare: return "原句和你的录音对比，自评一次"
        }
    }

    var next: EchoStep? {
        EchoStep(rawValue: rawValue + 1)
    }
}

enum WordState: String, Codable, CaseIterable, Identifiable {
    case unseen
    case learning
    case known

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unseen: return "未收录"
        case .learning: return "学习中"
        case .known: return "已认识"
        }
    }
}

/// Walks a sentence list through the four Echo steps.
struct EchoSession {
    let sentences: [IntensiveSentence]
    private(set) var index: Int
    private(set) var step: EchoStep
    private(set) var isFinished: Bool

    init(sentences: [IntensiveSentence], index: Int = 0) {
        self.sentences = sentences
        self.index = min(max(index, 0), max(sentences.count - 1, 0))
        self.step = .listen
        self.isFinished = sentences.isEmpty
    }

    var current: IntensiveSentence? {
        sentences.indices.contains(index) ? sentences[index] : nil
    }

    var sentenceCount: Int { sentences.count }

    /// 0...1 across the whole routine.
    var progress: Double {
        guard !sentences.isEmpty else { return 0 }
        let done = Double(index) * 4 + Double(step.rawValue)
        return min(done / (Double(sentences.count) * 4), 1)
    }

    /// Moves one step forward. Returns true when the sentence changed.
    @discardableResult
    mutating func advance() -> Bool {
        guard !isFinished, current != nil else { return false }
        if let next = step.next {
            step = next
            return false
        }
        // Finished "compare" for this sentence.
        if index + 1 < sentences.count {
            index += 1
            step = .listen
            return true
        }
        isFinished = true
        return false
    }

    /// Jumps to a sentence and starts again from "listen".
    mutating func jump(to sentenceIndex: Int) {
        guard sentences.indices.contains(sentenceIndex) else { return }
        index = sentenceIndex
        step = .listen
        isFinished = false
    }

    /// Test hook: back to the first sentence of the current list.
    mutating func resetForTests() {
        index = 0
        step = .listen
        isFinished = sentences.isEmpty
    }

    mutating func restart() {
        index = min(max(index, 0), max(sentences.count - 1, 0))
        step = .listen
        isFinished = sentences.isEmpty
    }

    /// Steps remaining for the current sentence (for "第 2 / 4 步" labels).
    var stepNumber: Int { step.rawValue + 1 }
}
