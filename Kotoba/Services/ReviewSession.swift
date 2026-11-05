import Foundation
import SwiftUI

/// Drives one flashcard session: queue, flip state, ratings and undo.
@MainActor
final class ReviewSessionModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case reviewing
        case finished
    }

    struct Item: Identifiable, Hashable {
        enum Kind: Hashable {
            case word(String)
            case sentence(String)
        }

        let kind: Kind

        var id: String {
            switch kind {
            case .word(let identifier): return "w:" + identifier
            case .sentence(let identifier): return "s:" + identifier
            }
        }
    }

    struct Log {
        let item: Item
        let rating: ReviewRating
        let previousWord: SavedWord?
        let previousSentence: SentenceCard?
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var queue: [Item] = []
    @Published private(set) var index = 0
    @Published var isFlipped = false
    @Published private(set) var logs: [Log] = []
    @Published private(set) var startedAt: Date?
    @Published private(set) var finishedAt: Date?

    private unowned let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    // MARK: Derived

    var current: Item? {
        guard index < queue.count else { return nil }
        return queue[index]
    }

    var word: SavedWord? {
        guard case .word(let identifier)? = current?.kind else { return nil }
        return app.word(id: identifier)
    }

    var sentence: SentenceCard? {
        guard case .sentence(let identifier)? = current?.kind else { return nil }
        return app.sentence(id: identifier)
    }

    var progress: Double {
        guard !queue.isEmpty else { return 0 }
        return min(Double(index) / Double(queue.count), 1)
    }

    var remaining: Int { max(queue.count - index, 0) }

    var againCount: Int { logs.filter { $0.rating == .again }.count }

    var goodCount: Int { logs.filter { $0.rating != .again }.count }

    var accuracy: Double {
        guard !logs.isEmpty else { return 0 }
        return Double(goodCount) / Double(logs.count)
    }

    var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }

    // MARK: Transport

    func start(includeNew: Bool = true) {
        queue = app.makeReviewQueue(includeNew: includeNew)
        index = 0
        isFlipped = false
        logs.removeAll()
        startedAt = queue.isEmpty ? nil : Date()
        finishedAt = nil
        phase = queue.isEmpty ? .finished : .reviewing
    }

    func restart() {
        start(includeNew: true)
    }

    func flip() {
        guard phase == .reviewing else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            isFlipped.toggle()
        }
    }

    func rate(_ rating: ReviewRating) {
        guard phase == .reviewing, let item = current else { return }
        switch item.kind {
        case .word(let identifier):
            let previous = app.word(id: identifier)
            _ = app.applyWordRating(rating, wordID: identifier)
            logs.append(Log(item: item, rating: rating, previousWord: previous, previousSentence: nil))
        case .sentence(let identifier):
            let previous = app.sentence(id: identifier)
            _ = app.applySentenceRating(rating, cardID: identifier)
            logs.append(Log(item: item, rating: rating, previousWord: nil, previousSentence: previous))
        }
        index += 1
        isFlipped = false
        if index >= queue.count {
            finishedAt = Date()
            phase = .finished
            if let startedAt {
                app.addStudySeconds(Date().timeIntervalSince(startedAt))
            }
        }
    }

    func undo() {
        guard let last = logs.popLast() else { return }
        switch last.item.kind {
        case .word(let identifier):
            if let previous = last.previousWord,
               let position = app.words.firstIndex(where: { $0.id == identifier }) {
                app.words[position] = previous
            }
        case .sentence(let identifier):
            if let previous = last.previousSentence,
               let position = app.sentenceCards.firstIndex(where: { $0.id == identifier }) {
                app.sentenceCards[position] = previous
            }
        }
        // Roll back the daily counters the rating added.
        let key = DayKey.key(for: Date())
        if var entry = app.activity[key] {
            entry.reviews = max(entry.reviews - 1, 0)
            if last.rating == .again {
                entry.againCount = max(entry.againCount - 1, 0)
            }
            app.activity[key] = entry
        }
        index = max(index - 1, 0)
        isFlipped = true
        if phase == .finished {
            phase = .reviewing
            finishedAt = nil
        }
        app.scheduleSave()
    }

    func end() {
        if let startedAt, phase == .reviewing {
            app.addStudySeconds(Date().timeIntervalSince(startedAt))
        }
        finishedAt = Date()
        phase = .finished
    }

    func reset() {
        phase = .idle
        queue = []
        index = 0
        logs.removeAll()
        isFlipped = false
        startedAt = nil
        finishedAt = nil
    }
}
