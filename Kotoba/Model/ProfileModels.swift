import Foundation

// MARK: - Learning profile

struct UserProfile: Codable, Equatable {
    var displayName: String = "同学"
    var level: JLPTLevel = .n5
    var dailyGoalMinutes: Int = 10
    var dailyNewWords: Int = 8
    var dailyReviewLimit: Int = 60
    var topics: [String] = []

    // Display
    var furiganaEnabled: Bool = true
    var romajiEnabled: Bool = true
    var translationEnabled: Bool = true
    var translationLanguage: TranslationLanguage = .chinese

    // Playback
    var autoplayEnabled: Bool = true
    var loopClip: Bool = true
    var playbackRate: Double = 1.0
    var speechRate: Double = 0.45

    // AI context explanations
    var aiEnabled: Bool = false
    var aiBaseURL: String = "https://api.openai.com/v1"
    var aiModel: String = "gpt-4o-mini"
    var aiLanguage: TranslationLanguage = .chinese

    var onboardingCompleted: Bool = false

    var dailyGoalSeconds: Double { Double(dailyGoalMinutes) * 60 }

    var goalSummary: String { "\(level.label) ・ 每天 \(dailyGoalMinutes) 分钟 ・ 新词 \(dailyNewWords) 个" }

    static let interestCatalog = [
        "日常会话", "校园", "恋爱", "悬疑", "热血", "美食",
        "旅行", "职场", "动画", "纪录片对白"
    ]
}

enum TranslationLanguage: String, Codable, CaseIterable, Identifiable {
    case chinese
    case english

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }

    var instruction: String {
        switch self {
        case .chinese: return "用简体中文回答"
        case .english: return "Answer in English"
        }
    }
}

// MARK: - Daily activity

struct DayActivity: Codable, Hashable {
    var dayKey: String
    var studiedSeconds: Double = 0
    var reviews: Int = 0
    var againCount: Int = 0
    var clipsWatched: Int = 0
    var newWords: Int = 0

    var minutes: Double { studiedSeconds / 60 }

    init(dayKey: String) {
        self.dayKey = dayKey
    }
}

struct WatchRecord: Identifiable, Codable, Hashable {
    let id: String
    let clipID: String
    var watchedAt: Date
    var seconds: Double
    var completed: Bool
}

// MARK: - Day keys

enum DayKey {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func key(for date: Date) -> String { formatter.string(from: date) }

    static func date(from key: String) -> Date? { formatter.date(from: key) }

    static func daysBack(_ count: Int, from date: Date = Date()) -> [String] {
        let calendar = Calendar.current
        return (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date) else { return nil }
            return key(for: day)
        }
    }
}

// MARK: - Achievements

struct Achievement: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let isUnlocked: Bool
    let progressText: String
}

// MARK: - Persisted snapshot

/// Everything the app stores on disk. A single document keeps writes atomic
/// and makes export / reset trivial.
struct AppSnapshot: Codable {
    var schemaVersion: Int = 1
    var profile: UserProfile = UserProfile()
    var words: [SavedWord] = []
    var sentenceCards: [SentenceCard] = []
    var decks: [Deck] = [Deck.makeDefault()]
    var customClips: [Clip] = []
    var activity: [String: DayActivity] = [:]
    var watchHistory: [WatchRecord] = []
    var savedClipIDs: [String] = []
    var explanations: [String: WordExplanation] = [:]
    var streakDayKeys: [String] = []
}
