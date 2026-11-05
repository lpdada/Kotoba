import Foundation

// MARK: - Saved word

struct SavedWord: Identifiable, Codable, Hashable {
    let id: String
    var word: String
    var reading: String
    var romaji: String
    var meanings: [String]
    var level: JLPTLevel?
    var familiarity: Int
    var isIgnored: Bool
    var note: String
    var scheduling: SchedulingState
    var createdAt: Date
    var sourceClipID: String?
    var sourceSentence: String?
    var deckIDs: [String]

    init(
        id: String,
        word: String,
        reading: String,
        romaji: String = "",
        meanings: [String],
        level: JLPTLevel? = nil,
        familiarity: Int = 1,
        isIgnored: Bool = false,
        note: String = "",
        scheduling: SchedulingState = SchedulingState(),
        createdAt: Date = Date(),
        sourceClipID: String? = nil,
        sourceSentence: String? = nil,
        deckIDs: [String] = [Deck.defaultDeckID]
    ) {
        self.id = id
        self.word = word
        self.reading = reading
        self.romaji = romaji
        self.meanings = meanings
        self.level = level
        self.familiarity = familiarity
        self.isIgnored = isIgnored
        self.note = note
        self.scheduling = scheduling
        self.createdAt = createdAt
        self.sourceClipID = sourceClipID
        self.sourceSentence = sourceSentence
        self.deckIDs = deckIDs
    }

    var familiarityTitle: String { SpacedRepetition.familiarityTitle(familiarity) }

    var primaryMeaning: String { meanings.first ?? "" }

    var isDue: Bool { scheduling.isDue() }

    var dueDescription: String {
        if isIgnored { return "已忽略" }
        if scheduling.isNew { return "新词" }
        if scheduling.isLearning { return SpacedRepetition.describe(seconds: scheduling.dueAt.timeIntervalSinceNow) + "后" }
        if isDue { return "待复习" }
        return SpacedRepetition.describe(seconds: scheduling.dueAt.timeIntervalSinceNow) + "后"
    }
}

// MARK: - Sentence card

struct SentenceCard: Identifiable, Codable, Hashable {
    let id: String
    var text: String
    var translation: String
    var clipID: String?
    var createdAt: Date
    var familiarity: Int
    var scheduling: SchedulingState
    var note: String

    init(
        id: String = UUID().uuidString,
        text: String,
        translation: String,
        clipID: String? = nil,
        createdAt: Date = Date(),
        familiarity: Int = 1,
        scheduling: SchedulingState = SchedulingState(),
        note: String = ""
    ) {
        self.id = id
        self.text = text
        self.translation = translation
        self.clipID = clipID
        self.createdAt = createdAt
        self.familiarity = familiarity
        self.scheduling = scheduling
        self.note = note
    }
}

// MARK: - Deck

struct Deck: Identifiable, Codable, Hashable {
    static let defaultDeckID = "deck.default"

    let id: String
    var name: String
    var detail: String
    /// How many unseen cards this deck introduces per day.
    var newPerDay: Int
    /// Upper bound of reviews per day for this deck.
    var reviewLimit: Int
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        detail: String = "",
        newPerDay: Int = 8,
        reviewLimit: Int = 60,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.newPerDay = newPerDay
        self.reviewLimit = reviewLimit
        self.createdAt = createdAt
    }

    static func makeDefault() -> Deck {
        Deck(
            id: defaultDeckID,
            name: "我的生词",
            detail: "从视频里顺手保存的词都会先到这里",
            newPerDay: 8,
            reviewLimit: 60
        )
    }
}
