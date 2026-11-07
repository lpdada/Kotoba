import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftUI

/// Central state and use-cases for the app.
///
/// Views talk to this object only; it owns persistence, scheduling, ranking and
/// the AI explainer selection.
@MainActor
final class AppModel: ObservableObject {
    // MARK: Published state

    @Published private(set) var isReady = false
    @Published private(set) var bootstrapMessage = "正在准备词典…"

    @Published var profile = UserProfile()
    @Published var words: [SavedWord] = []
    @Published var sentenceCards: [SentenceCard] = []
    @Published var decks: [Deck] = [Deck.makeDefault()]
    @Published var customClips: [Clip] = []
    @Published var activity: [String: DayActivity] = [:]
    @Published var watchHistory: [WatchRecord] = []
    @Published var savedClipIDs: Set<String> = []
    @Published var explanations: [String: WordExplanation] = [:]
    @Published var shadowingRecords: [ShadowingRecord] = []
    @Published var kanjiCards: [KanjiCard] = []
    /// Set when a caption fetch is in flight, so the importer can show progress.
    @Published var captionFetchStatus: String?
    /// Self-hosted transcription endpoint; disabled and empty by default.
    @Published var transcription = TranscriptionSettings()
    /// Read-aloud voice preferences (Edge TTS on by default).
    @Published var voiceOptions = VoiceOptions()
    /// Mirrors `grammar.progress` so badges refresh when a toggle happens.
    @Published var grammarProgress = GrammarProgress()
    @Published var metricsByClip: [String: ClipMetrics] = [:]
    @Published var toast: String?
    @Published var aiKeyStored = false

    // MARK: Services

    let store: PersistenceStore
    let dictionary = DictionaryStore()
    let kanji = KanjiStore()
    let grammar = GrammarStore()
    let library: ClipLibrary
    let speech = SpeechService()
    lazy var tokenizer = Tokenizer(dictionary: dictionary)
    private(set) lazy var reviewSession = ReviewSessionModel(app: self)

    private var saveTask: Task<Void, Never>?
    /// Set when an upgrade fills in the default address, so it is persisted once.
    private var didMigrateServerAddress = false
    private var pendingWatchRecords: [String: Double] = [:]

    init(store: PersistenceStore = PersistenceStore()) {
        self.store = store
        self.library = ClipLibrary(store: store)
    }

    // MARK: Bootstrap

    func bootstrap() async {
        guard !isReady else { return }
        bootstrapMessage = "正在准备词典…"
        dictionary.loadBundled()
        kanji.loadBundled()
        grammar.loadBundled()

        bootstrapMessage = "正在载入学习记录…"
        let snapshot = store.load()
        apply(snapshot)

        bootstrapMessage = "正在整理素材…"
        library.load(customClips: customClips)
        refreshMetrics()
        speech.onFallback = { [weak self] reason in
            self?.toast = reason
        }
        aiKeyStored = !(Secrets.value(for: Secrets.aiKeyAccount) ?? "").isEmpty
        if didMigrateServerAddress {
            didMigrateServerAddress = false
            scheduleSave()
        }
        isReady = true
    }

    // MARK: Snapshot plumbing

    private func apply(_ snapshot: AppSnapshot) {
        profile = snapshot.profile
        words = snapshot.words
        sentenceCards = snapshot.sentenceCards
        decks = snapshot.decks.isEmpty ? [Deck.makeDefault()] : snapshot.decks
        customClips = snapshot.customClips
        activity = snapshot.activity
        watchHistory = snapshot.watchHistory
        savedClipIDs = Set(snapshot.savedClipIDs)
        explanations = snapshot.explanations
        shadowingRecords = snapshot.shadowingRecords ?? []
        transcription = snapshot.transcription ?? .disabled
        // Pre-0.8.0 archives predate `voiceOptions` and kept an empty server
        // address, so the pre-filled default never reached those users.
        if Self.shouldMigrateServerAddress(
            archivedVoiceOptions: snapshot.voiceOptions,
            transcriptionURL: transcription.serverURL
        ) {
            transcription.serverURL = ServerDefaults.baseURL
            didMigrateServerAddress = true
        }
        voiceOptions = snapshot.voiceOptions ?? .default
        grammar.install(progress: snapshot.grammarProgress ?? GrammarProgress())
        grammarProgress = grammar.progress
        reconfigureSpeech()
        kanjiCards = snapshot.kanjiCards ?? []
    }

    private func makeSnapshot() -> AppSnapshot {
        var snapshot = AppSnapshot()
        snapshot.profile = profile
        snapshot.words = words
        snapshot.sentenceCards = sentenceCards
        snapshot.decks = decks
        snapshot.customClips = customClips
        snapshot.activity = activity
        snapshot.watchHistory = Array(watchHistory.suffix(400))
        snapshot.savedClipIDs = Array(savedClipIDs)
        snapshot.explanations = explanations
        snapshot.shadowingRecords = shadowingRecords
        snapshot.transcription = transcription
        snapshot.voiceOptions = voiceOptions
        snapshot.grammarProgress = grammar.progress
        snapshot.kanjiCards = kanjiCards
        snapshot.streakDayKeys = Array(activity.keys).sorted()
        return snapshot
    }

    func scheduleSave() {
        saveTask?.cancel()
        let snapshot = makeSnapshot()
        let store = self.store
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            do {
                try store.save(snapshot)
            } catch {
                await MainActor.run { self?.toast = "保存失败：\(error.localizedDescription)" }
            }
        }
    }

    func flushSave() {
        do {
            try store.save(makeSnapshot())
        } catch {
            toast = "保存失败：\(error.localizedDescription)"
        }
    }

    func updateProfile(_ mutate: (inout UserProfile) -> Void) {
        var copy = profile
        mutate(&copy)
        profile = copy
        scheduleSave()
    }

    // MARK: Word actions

    func savedWord(id: String) -> SavedWord? {
        words.first { $0.id == id }
    }

    func savedWord(forEntryID entryID: String) -> SavedWord? {
        words.first { $0.id == entryID }
    }

    func isSaved(entryID: String) -> Bool {
        words.contains { $0.id == entryID }
    }

    @discardableResult
    func saveWord(
        entry: DictEntry?,
        surface: String,
        sentence: String?,
        clip: Clip?
    ) -> SavedWord {
        let identifier = entry?.id ?? ("surface:" + surface)
        if let existing = words.first(where: { $0.id == identifier }) {
            return existing
        }
        let defaultDeck = decks.first?.id ?? Deck.defaultDeckID
        let word = SavedWord(
            id: identifier,
            word: entry?.word ?? surface,
            reading: entry?.reading ?? "",
            romaji: entry?.romaji ?? Kana.romaji(surface),
            meanings: entry?.meanings ?? [],
            level: entry?.level,
            sourceClipID: clip?.id,
            sourceSentence: sentence,
            deckIDs: [defaultDeck]
        )
        words.insert(word, at: 0)
        bumpToday { $0.newWords += 1 }
        scheduleSave()
        toast = "已加入生词本：\(word.word)"
        return word
    }

    func removeWord(_ word: SavedWord) {
        words.removeAll { $0.id == word.id }
        scheduleSave()
    }

    func updateWord(_ word: SavedWord) {
        guard let index = words.firstIndex(where: { $0.id == word.id }) else { return }
        words[index] = word
        scheduleSave()
    }

    func toggleIgnored(_ word: SavedWord) {
        var copy = word
        copy.isIgnored.toggle()
        updateWord(copy)
    }

    /// Manually declare "I already know this" — graduates the card to a long interval.
    func markKnown(_ word: SavedWord) {
        var copy = word
        copy.scheduling.intervalDays = max(copy.scheduling.intervalDays, 21)
        copy.scheduling.learningStep = 0
        copy.familiarity = max(copy.familiarity, 5)
        copy.scheduling.dueAt = Date().addingTimeInterval(21 * 86_400)
        copy.scheduling.reviewCount = max(copy.scheduling.reviewCount, 1)
        updateWord(copy)
        toast = "已标记为掌握：\(word.word)"
    }

    // MARK: Sentence cards

    @discardableResult
    func saveSentence(text: String, translation: String, clip: Clip?) -> SentenceCard {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = sentenceCards.first(where: { $0.text == trimmed }) {
            return existing
        }
        let card = SentenceCard(text: trimmed, translation: translation, clipID: clip?.id)
        sentenceCards.insert(card, at: 0)
        scheduleSave()
        toast = "已保存整句卡片"
        return card
    }

    func removeSentence(_ card: SentenceCard) {
        sentenceCards.removeAll { $0.id == card.id }
        scheduleSave()
    }

    // MARK: Decks

    func deck(for id: String) -> Deck? {
        decks.first { $0.id == id }
    }

    @discardableResult
    func createDeck(name: String, detail: String = "") -> Deck {
        let deck = Deck(name: name.isEmpty ? "新分组" : name, detail: detail)
        decks.append(deck)
        scheduleSave()
        return deck
    }

    func updateDeck(_ deck: Deck) {
        guard let index = decks.firstIndex(where: { $0.id == deck.id }) else { return }
        decks[index] = deck
        scheduleSave()
    }

    func deleteDeck(_ deck: Deck) {
        guard deck.id != Deck.defaultDeckID else {
            toast = "默认分组不能删除"
            return
        }
        decks.removeAll { $0.id == deck.id }
        for index in words.indices {
            words[index].deckIDs.removeAll { $0 == deck.id }
            if words[index].deckIDs.isEmpty {
                words[index].deckIDs = [Deck.defaultDeckID]
            }
        }
        scheduleSave()
    }

    func wordCount(inDeck id: String) -> Int {
        words.filter { $0.deckIDs.contains(id) }.count
    }

    // MARK: Review

    func dueReviewCount(at date: Date = Date()) -> Int {
        let wordsDue = words.filter { !$0.isIgnored && $0.scheduling.isDue(at: date) }.count
        let sentencesDue = sentenceCards.filter { $0.scheduling.isDue(at: date) }.count
        let kanjiDue = kanjiCards.filter { $0.scheduling.isDue(at: date) }.count
        return wordsDue + sentencesDue + kanjiDue
    }

    func newWordCount() -> Int {
        words.filter { !$0.isIgnored && $0.scheduling.isNew }.count
    }

    func makeReviewQueue(includeNew: Bool = true, now: Date = Date()) -> [ReviewSessionModel.Item] {
        var items: [ReviewSessionModel.Item] = []

        // Reviews respect both the per-deck limit and the global daily cap.
        var reviewAllowance = deckAllowances(newCards: false)
        var remainingReviews = profile.dailyReviewLimit
        var newAllowance = deckAllowances(newCards: true)
        var remainingNew = profile.dailyNewWords
        let dueWords = words
            .filter { !$0.isIgnored && !$0.scheduling.isNew && $0.scheduling.isDue(at: now) }
            .sorted { $0.scheduling.dueAt < $1.scheduling.dueAt }
        for word in dueWords {
            guard remainingReviews > 0 else { break }
            guard consumeAllowance(&reviewAllowance, for: word) else { continue }
            items.append(ReviewSessionModel.Item(kind: .word(word.id)))
            remainingReviews -= 1
        }

        if includeNew {
            let newWords = words
                .filter { !$0.isIgnored && $0.scheduling.isNew }
                .sorted { $0.createdAt > $1.createdAt }
            for word in newWords {
                guard remainingNew > 0 else { break }
                guard consumeAllowance(&newAllowance, for: word) else { continue }
                items.append(ReviewSessionModel.Item(kind: .word(word.id)))
                remainingNew -= 1
            }
        }

        // Kanji share the same daily budgets so one day never doubles in size.
        let dueKanji = kanjiCards
            .filter { $0.scheduling.isDue(at: now) && !$0.scheduling.isNew }
            .sorted { $0.scheduling.dueAt < $1.scheduling.dueAt }
        for card in dueKanji {
            guard remainingReviews > 0 else { break }
            items.append(ReviewSessionModel.Item(kind: .kanji(card.literal)))
            remainingReviews -= 1
        }
        if includeNew {
            let newKanji = kanjiCards
                .filter { $0.scheduling.isNew }
                .sorted { $0.createdAt > $1.createdAt }
            for card in newKanji {
                guard remainingNew > 0 else { break }
                items.append(ReviewSessionModel.Item(kind: .kanji(card.literal)))
                remainingNew -= 1
            }
        }

        let dueSentences = sentenceCards
            .filter { $0.scheduling.isDue(at: now) }
            .prefix(12)
        items += dueSentences.map { ReviewSessionModel.Item(kind: .sentence($0.id)) }

        return items.shuffled()
    }

    /// Remaining card budget per deck for this queue build.
    private func deckAllowances(newCards: Bool) -> [String: Int] {
        var result: [String: Int] = [:]
        for deck in decks {
            result[deck.id] = newCards ? deck.newPerDay : deck.reviewLimit
        }
        return result
    }

    /// A word counts against the first deck that still admits cards.
    private func consumeAllowance(_ allowance: inout [String: Int], for word: SavedWord) -> Bool {
        let deckIDs = word.deckIDs.isEmpty ? [Deck.defaultDeckID] : word.deckIDs
        for identifier in deckIDs {
            // Words in a deck that no longer exists are never blocked.
            guard let remaining = allowance[identifier] else { return true }
            if remaining > 0 {
                allowance[identifier] = remaining - 1
                return true
            }
        }
        return false
    }

    func word(id: String) -> SavedWord? { words.first { $0.id == id } }
    func sentence(id: String) -> SentenceCard? { sentenceCards.first { $0.id == id } }

    func applyWordRating(_ rating: ReviewRating, wordID: String, now: Date = Date()) -> SavedWord? {
        guard let index = words.firstIndex(where: { $0.id == wordID }) else { return nil }
        let current = words[index]
        let result = SpacedRepetition.review(
            state: current.scheduling,
            familiarity: current.familiarity,
            rating: rating,
            now: now
        )
        var updated = current
        updated.scheduling = result.state
        updated.familiarity = result.familiarity
        words[index] = updated
        recordReview(rating: rating)
        return updated
    }

    func applySentenceRating(_ rating: ReviewRating, cardID: String, now: Date = Date()) -> SentenceCard? {
        guard let index = sentenceCards.firstIndex(where: { $0.id == cardID }) else { return nil }
        let current = sentenceCards[index]
        let result = SpacedRepetition.review(
            state: current.scheduling,
            familiarity: current.familiarity,
            rating: rating,
            now: now
        )
        var updated = current
        updated.scheduling = result.state
        updated.familiarity = result.familiarity
        sentenceCards[index] = updated
        recordReview(rating: rating)
        return updated
    }

    // MARK: Activity

    var today: DayActivity {
        activity[DayKey.key(for: Date())] ?? DayActivity(dayKey: DayKey.key(for: Date()))
    }

    private func bumpToday(_ mutate: (inout DayActivity) -> Void) {
        let key = DayKey.key(for: Date())
        var entry = activity[key] ?? DayActivity(dayKey: key)
        mutate(&entry)
        activity[key] = entry
    }

    func addStudySeconds(_ seconds: Double) {
        guard seconds > 0 else { return }
        bumpToday { $0.studiedSeconds += seconds }
        scheduleSave()
    }

    func recordReview(rating: ReviewRating) {
        bumpToday {
            $0.reviews += 1
            if rating == .again { $0.againCount += 1 }
        }
        scheduleSave()
    }

    func recordWatch(clip: Clip, seconds: Double, completed: Bool) {
        let record = WatchRecord(
            id: UUID().uuidString,
            clipID: clip.id,
            watchedAt: Date(),
            seconds: seconds,
            completed: completed
        )
        watchHistory.append(record)
        if watchHistory.count > 400 {
            watchHistory.removeFirst(watchHistory.count - 400)
        }
        if completed {
            bumpToday { $0.clipsWatched += 1 }
        }
        scheduleSave()
    }

    var streakDays: Int {
        var streak = 0
        let calendar = Calendar.current
        for offset in 0..<400 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Date()) else { break }
            let key = DayKey.key(for: day)
            let entry = activity[key]
            let studied = (entry?.studiedSeconds ?? 0) >= 60 || (entry?.reviews ?? 0) > 0
            if studied {
                streak += 1
            } else if offset > 0 {
                break
            }
        }
        return streak
    }

    func activityRange(days: Int) -> [DayActivity] {
        DayKey.daysBack(days).map { key in
            activity[key] ?? DayActivity(dayKey: key)
        }
    }

    var retention: Double {
        let recent = activityRange(days: 30)
        let total = recent.reduce(0) { $0 + $1.reviews }
        let again = recent.reduce(0) { $0 + $1.againCount }
        guard total > 0 else { return 0 }
        return 1 - Double(again) / Double(total)
    }

    var minutesToday: Double { today.studiedSeconds / 60 }

    var goalProgress: Double {
        guard profile.dailyGoalSeconds > 0 else { return 0 }
        return min(today.studiedSeconds / profile.dailyGoalSeconds, 1)
    }

    var familiarityCounts: [Int: Int] {
        var counts: [Int: Int] = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0]
        for word in words where !word.isIgnored {
            counts[word.familiarity, default: 0] += 1
        }
        return counts
    }

    var knownWordCount: Int {
        words.filter { !$0.isIgnored && $0.familiarity >= 4 }.count
    }

    var learningWordCount: Int {
        words.filter { !$0.isIgnored && $0.familiarity <= 3 }.count
    }

    var knownLemmas: Set<String> {
        Set(words.filter { !$0.isIgnored }.map(\.word))
    }

    var achievements: [Achievement] {
        let totalWords = words.count
        let learned = knownWordCount
        let reviews = activity.values.reduce(0) { $0 + $1.reviews }
        let clips = Set(watchHistory.map(\.clipID)).count
        let streak = streakDays
        return [
            Achievement(
                id: "first_word",
                title: "第一颗种子",
                detail: "保存第一个生词",
                symbol: "leaf",
                isUnlocked: totalWords >= 1,
                progressText: "\(min(totalWords, 1))/1"
            ),
            Achievement(
                id: "twenty_five",
                title: "词汇小站",
                detail: "生词本累计 25 个词",
                symbol: "square.stack.3d.up",
                isUnlocked: totalWords >= 25,
                progressText: "\(min(totalWords, 25))/25"
            ),
            Achievement(
                id: "hundred_reviews",
                title: "复习一百次",
                detail: "完成 100 次闪卡评分",
                symbol: "arrow.triangle.2.circlepath",
                isUnlocked: reviews >= 100,
                progressText: "\(min(reviews, 100))/100"
            ),
            Achievement(
                id: "streak_seven",
                title: "连续七天",
                detail: "连续 7 天学习",
                symbol: "flame",
                isUnlocked: streak >= 7,
                progressText: "\(min(streak, 7))/7"
            ),
            Achievement(
                id: "clip_explorer",
                title: "素材探索者",
                detail: "看过 10 条不同片段",
                symbol: "film.stack",
                isUnlocked: clips >= 10,
                progressText: "\(min(clips, 10))/10"
            ),
            Achievement(
                id: "mastery",
                title: "掌握二十",
                detail: "20 个词达到“熟悉”以上",
                symbol: "checkmark.seal",
                isUnlocked: learned >= 20,
                progressText: "\(min(learned, 20))/20"
            )
        ]
    }

    // MARK: Feed

    func metrics(for clip: Clip) -> ClipMetrics {
        library.metrics(for: clip, tokenizer: tokenizer)
    }

    private func refreshMetrics() {
        var result: [String: ClipMetrics] = [:]
        for clip in library.clips {
            result[clip.id] = library.metrics(for: clip, tokenizer: tokenizer)
        }
        metricsByClip = result
    }

    func feedContext() -> FeedRanker.Context {
        var counts: [String: Int] = [:]
        for record in watchHistory {
            counts[record.clipID, default: 0] += 1
        }
        return FeedRanker.Context(
            profile: profile,
            metrics: metricsByClip,
            watchCounts: counts,
            savedClipIDs: savedClipIDs,
            knownLemmas: knownLemmas
        )
    }

    func rankedFeed() -> [Clip] {
        guard !library.clips.isEmpty else { return [] }
        return FeedRanker.ranked(library.clips, context: feedContext())
    }

    func toggleSavedClip(_ clip: Clip) {
        if savedClipIDs.contains(clip.id) {
            savedClipIDs.remove(clip.id)
            toast = "已取消收藏片段"
        } else {
            savedClipIDs.insert(clip.id)
            toast = "已收藏片段"
        }
        scheduleSave()
    }

    // MARK: Explanations

    private func explanationKey(word: String, sentence: String) -> String {
        word + "␟" + sentence
    }

    func cachedExplanation(word: String, sentence: String) -> WordExplanation? {
        explanations[explanationKey(word: word, sentence: sentence)]
    }

    func invalidateExplanation(word: String, sentence: String) {
        explanations.removeValue(forKey: explanationKey(word: word, sentence: sentence))
        scheduleSave()
    }

    func explain(word: String, sentence: String, entry: DictEntry?) async -> WordExplanation {
        let key = explanationKey(word: word, sentence: sentence)
        if let cached = explanations[key] { return cached }

        let explainer: ContextExplaining
        if profile.aiEnabled {
            let config = AIConfiguration(
                baseURL: profile.aiBaseURL,
                model: profile.aiModel,
                apiKey: Secrets.value(for: Secrets.aiKeyAccount) ?? ""
            )
            if config.isConfigured {
                explainer = RemoteLLMExplainer(configuration: config, language: profile.aiLanguage)
            } else {
                explainer = LocalContextExplainer(tokenizer: tokenizer, dictionary: dictionary)
            }
        } else {
            explainer = LocalContextExplainer(tokenizer: tokenizer, dictionary: dictionary)
        }

        do {
            let result = try await explainer.explain(word: word, sentence: sentence, entry: entry)
            explanations[key] = result
            scheduleSave()
            return result
        } catch {
            var fallback = try? await LocalContextExplainer(tokenizer: tokenizer, dictionary: dictionary)
                .explain(word: word, sentence: sentence, entry: entry)
            if fallback == nil {
                fallback = WordExplanation(
                    headline: "解释失败：\(error.localizedDescription)",
                    grammar: "",
                    nuance: "",
                    source: "本地语法分析",
                    createdAt: Date(),
                    isRemote: false
                )
            }
            let value = fallback!
            explanations[key] = value
            scheduleSave()
            return value
        }
    }

    // MARK: AI key

    func saveAIKey(_ key: String) {
        Secrets.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: Secrets.aiKeyAccount)
        aiKeyStored = !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if aiKeyStored {
            updateProfile { $0.aiEnabled = true }
            toast = "已保存 AI 密钥"
        } else {
            updateProfile { $0.aiEnabled = false }
            toast = "已清除 AI 密钥"
        }
    }

    // MARK: Content import

    func importClips(from url: URL) throws -> Int {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let collection = try decoder.decode(ClipCollection.self, from: data)
        var imported: [Clip] = []
        for original in collection.clips {
            var copy = original
            copy.custom = true
            if customClips.contains(where: { $0.id == copy.id }) {
                copy = Clip(
                    id: copy.id + "-" + String(UUID().uuidString.prefix(4)),
                    title: copy.title,
                    series: copy.series,
                    episode: copy.episode,
                    transcript: copy.transcript,
                    translation: copy.translation,
                    translationEN: copy.translationEN,
                    level: copy.level,
                    topics: copy.topics,
                    durationSeconds: copy.durationSeconds,
                    media: copy.media,
                    attribution: copy.attribution,
                    custom: true
                )
            }
            imported.append(copy)
        }
        customClips.append(contentsOf: imported)
        library.setCustom(customClips)
        refreshMetrics()
        scheduleSave()
        return imported.count
    }

    @discardableResult
    func addCustomClip(_ clip: Clip) -> Clip {
        // Same video + same range twice would duplicate the SwiftUI identity.
        if let existing = customClips.first(where: { $0.id == clip.id }) {
            return existing
        }
        addCustomClips([clip])
        return clip
    }

    /// Batch variant: one metrics rebuild and one save for a whole import.
    @discardableResult
    func addCustomClips(_ clips: [Clip]) -> Int {
        var added = 0
        for clip in clips where !customClips.contains(where: { $0.id == clip.id }) {
            customClips.append(clip)
            added += 1
        }
        guard added > 0 else { return 0 }
        library.setCustom(customClips)
        refreshMetrics()
        scheduleSave()
        return added
    }

    /// Parses a subtitle file's text through the shared importer pipeline.
    @discardableResult
    func importSubtitleCues(
        _ result: SubtitleParseResult,
        mediaFileName: String,
        series: String,
        level: JLPTLevel?,
        linesPerClip: Int,
        maxSeconds: Double
    ) -> Int {
        var builder = SubtitleClipBuilder()
        builder.linesPerClip = linesPerClip
        builder.maxSeconds = maxSeconds
        let clips = builder.build(
            cues: result.cues,
            mediaFileName: mediaFileName,
            series: series,
            level: level
        )
        return addCustomClips(clips)
    }

    func removeCustomClip(_ clip: Clip) {
        customClips.removeAll { $0.id == clip.id }
        library.removeCustom(id: clip.id)
        refreshMetrics()
        scheduleSave()
    }

    func copyMediaFile(from url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let destination = store.mediaURL(named: url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return url.lastPathComponent
    }

    // MARK: Shadowing

    func shadowingDirectory() -> URL { store.shadowingFolder() }

    func audioURL(for record: ShadowingRecord) -> URL? {
        store.resolvedShadowingURL(named: record.fileName)
    }

    func records(forClip clipID: String, sentence sentenceIndex: Int) -> [ShadowingRecord] {
        shadowingRecords
            .filter { $0.clipID == clipID && $0.sentenceIndex == sentenceIndex }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func latestRecord(forClip clipID: String, sentence sentenceIndex: Int) -> ShadowingRecord? {
        records(forClip: clipID, sentence: sentenceIndex).first
    }

    @discardableResult
    func saveShadowingRecord(
        clipID: String,
        sentenceIndex: Int,
        japanese: String,
        fileName: String,
        duration: Double,
        rating: ShadowingRating
    ) -> ShadowingRecord {
        let record = ShadowingRecord(
            clipID: clipID,
            sentenceIndex: sentenceIndex,
            japanese: japanese,
            fileName: fileName,
            durationSeconds: max(duration, 0.1),
            rating: rating
        )
        shadowingRecords.insert(record, at: 0)
        pruneShadowingRecords(clipID: clipID, sentenceIndex: sentenceIndex, keeping: 3)
        scheduleSave()
        return record
    }

    func deleteShadowing(_ record: ShadowingRecord) {
        if let url = audioURL(for: record) {
            try? FileManager.default.removeItem(at: url)
        }
        shadowingRecords.removeAll { $0.id == record.id }
        scheduleSave()
    }

    /// Keeps the newest `keeping` recordings per sentence so the folder cannot grow forever.
    private func pruneShadowingRecords(clipID: String, sentenceIndex: Int, keeping: Int) {
        let matching = shadowingRecords.filter { $0.clipID == clipID && $0.sentenceIndex == sentenceIndex }
        guard matching.count > keeping else { return }
        for record in matching.dropFirst(keeping) {
            if let url = audioURL(for: record) {
                try? FileManager.default.removeItem(at: url)
            }
            shadowingRecords.removeAll { $0.id == record.id }
        }
    }

    private func clearShadowingFolder() {
        let folder = store.shadowingFolder()
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: Kanji

    func kanjiEntry(_ literal: String) -> KanjiEntry? { kanji.entry(for: literal) }

    func kanjiCard(_ literal: String) -> KanjiCard? {
        kanjiCards.first { $0.literal == literal }
    }

    func exampleWords(for entry: KanjiEntry, limit: Int = 4) -> [KanjiExampleWord] {
        kanji.exampleWords(for: entry, dictionary: dictionary, limit: limit)
    }

    @discardableResult
    func saveKanjiCard(_ entry: KanjiEntry) -> KanjiCard {
        if let existing = kanjiCard(entry.literal) { return existing }
        let card = KanjiCard(literal: entry.literal)
        kanjiCards.insert(card, at: 0)
        bumpToday { $0.newWords += 1 }
        scheduleSave()
        toast = "已加入汉字复习：\(entry.literal)"
        return card
    }

    func updateKanjiCard(_ card: KanjiCard) {
        guard let index = kanjiCards.firstIndex(where: { $0.literal == card.literal }) else { return }
        kanjiCards[index] = card
        scheduleSave()
    }

    func removeKanjiCard(_ card: KanjiCard) {
        kanjiCards.removeAll { $0.literal == card.literal }
        scheduleSave()
    }

    func applyKanjiRating(_ rating: ReviewRating, literal: String, now: Date = Date()) -> KanjiCard? {
        guard let index = kanjiCards.firstIndex(where: { $0.literal == literal }) else { return nil }
        let current = kanjiCards[index]
        let result = SpacedRepetition.review(
            state: current.scheduling,
            familiarity: current.familiarity,
            rating: rating,
            now: now
        )
        var updated = current
        updated.scheduling = result.state
        updated.familiarity = result.familiarity
        kanjiCards[index] = updated
        recordReview(rating: rating)
        return updated
    }

    var kanjiLearnedCount: Int {
        kanjiCards.filter { $0.familiarity >= 4 }.count
    }

    var kanjiDueCount: Int {
        kanjiCards.filter { $0.scheduling.isDue() }.count
    }

    /// Bundled total, saved cards and learned cards per JLPT band.
    var kanjiLevelStats: [KanjiLevelStat] {
        let savedByLevel = Dictionary(grouping: kanjiCards) { card in
            kanji.entry(for: card.literal)?.levelSortKey ?? 9
        }
        return kanji.levelGroups.map { group in
            let cards = savedByLevel[group.key] ?? []
            return KanjiLevelStat(
                key: group.key,
                label: group.label,
                total: group.count,
                saved: cards.count,
                learned: cards.filter { $0.familiarity >= 4 }.count
            )
        }
    }

    // MARK: Word states (known / learning / unseen)

    func wordState(entryID: String) -> WordState {
        guard let word = savedWord(id: entryID) else { return .unseen }
        if word.isIgnored { return .unseen }
        return word.familiarity >= 4 ? .known : .learning
    }

    /// Explicit KNOWN / LEARNING / UNSEEN switch used by the lookup sheet.
    @discardableResult
    func setWordState(
        _ state: WordState,
        entry: DictEntry?,
        surface: String,
        sentence: String? = nil,
        clip: Clip? = nil
    ) -> SavedWord? {
        let identifier = entry?.id ?? ("surface:" + surface)
        switch state {
        case .unseen:
            if let existing = savedWord(id: identifier) {
                removeWord(existing)
            }
            toast = "已移出生词本：\(entry?.word ?? surface)"
            return nil
        case .known:
            var word = saveWord(entry: entry, surface: surface, sentence: sentence, clip: clip)
            word.familiarity = 5
            word.isIgnored = false
            word.scheduling.intervalDays = max(word.scheduling.intervalDays, 21)
            word.scheduling.learningStep = 0
            word.scheduling.preLapseInterval = nil
            word.scheduling.reviewCount = max(word.scheduling.reviewCount, 1)
            word.scheduling.dueAt = Date().addingTimeInterval(21 * 86_400)
            updateWord(word)
            toast = "标记为已认识：\(word.word)"
            return word
        case .learning:
            var word = saveWord(entry: entry, surface: surface, sentence: sentence, clip: clip)
            word.familiarity = 1
            word.isIgnored = false
            word.scheduling = SchedulingState()
            updateWord(word)
            toast = "改为学习中：\(word.word)"
            return word
        }
    }

    // MARK: YouTube captions

    /// Builds a clip from fetched caption cues, keeping per-line timings so the
    /// intensive / Echo views can work sentence by sentence.
    @discardableResult
    func importYouTubeClip(
        videoID: String,
        title: String,
        cues: [SubtitleCue],
        translation: String = "",
        level: JLPTLevel? = nil,
        attribution: String = "字幕来自 YouTube 公开轨道"
    ) -> Clip? {
        guard let first = cues.first, let last = cues.last else { return nil }
        let start = first.start
        let end = max(last.end, start + 1)
        let clip = Clip(
            id: "yt-\(videoID)-\(Int(start))-\(Int(end))",
            title: title.isEmpty ? "YouTube 片段 \(videoID)" : title,
            series: "YouTube",
            episode: "",
            transcript: cues.map(\.text).joined(separator: "\n"),
            translation: translation,
            translationEN: "",
            level: level,
            topics: ["YouTube"],
            durationSeconds: end - start,
            mediaStartSeconds: start,
            lineTimings: cues.map { ClipLineTiming(start: $0.start, end: max($0.end, $0.start + 0.3)) },
            media: .youtube(id: videoID, start: start, end: end),
            attribution: attribution,
            custom: true
        )
        addCustomClip(clip)
        return clip
    }

    /// True only for archives written before 0.8.0 (no `voiceOptions`) that also
    /// carry an empty transcription address. Addresses the user cleared *after*
    /// 0.8.0 are untouched because those archives already have `voiceOptions`.
    static func shouldMigrateServerAddress(archivedVoiceOptions: VoiceOptions?, transcriptionURL: String) -> Bool {
        archivedVoiceOptions == nil
            && transcriptionURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Grammar status

    /// Cycles a grammar entry's status and persists it with the snapshot.
    @discardableResult
    func toggleGrammarStatus(_ entry: GrammarEntry) -> GrammarStatus {
        let status = grammar.toggleStatus(for: entry)
        grammarProgress = grammar.progress
        scheduleSave()
        toast = "\(entry.pattern)：\(status.title)"
        return status
    }

    // MARK: Voice options

    func updateVoiceOptions(_ mutate: (inout VoiceOptions) -> Void) {
        var copy = voiceOptions
        mutate(&copy)
        voiceOptions = copy
        reconfigureSpeech()
        scheduleSave()
    }

    /// Resolves the 3-way mode (own address → transcription address → edge → system)
    /// and hands it to the single speech entry point.
    private func reconfigureSpeech() {
        let transcriptionURL = transcription.serverURL
        speech.configure(
            mode: voiceOptions.effectiveMode(transcriptionURL: transcriptionURL),
            voiceID: voiceOptions.effectiveVoiceID,
            serverBaseURL: voiceOptions.resolvedServerURL(transcriptionURL: transcriptionURL)
        )
    }

    // MARK: Self-hosted transcription

    func updateTranscription(_ mutate: (inout TranscriptionSettings) -> Void) {
        var copy = transcription
        mutate(&copy)
        transcription = copy
        // The read-aloud server address may follow the transcription server.
        reconfigureSpeech()
        scheduleSave()
    }

    /// Client built from current settings; injectable for tests.
    func transcriptionClient(
        send: ((URLRequest) async throws -> (Data, Int))? = nil,
        sleep: ((Double) async throws -> Void)? = nil
    ) -> TranscriptionClient {
        TranscriptionClient(
            settings: transcription,
            send: send ?? TranscriptionClient.defaultSend,
            sleep: sleep ?? { seconds in
                try await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
            }
        )
    }

    /// Calls the configured server and returns timestamped lines.
    func transcribeYouTube(videoID: String, client: TranscriptionClient? = nil) async throws -> TranscriptionResult {
        guard transcription.isConfigured else { throw TranscriptionError.notConfigured }
        let active = client ?? transcriptionClient()
        return try await active.transcribe(videoID: videoID)
    }

    /// Saves a server transcript as a clip (same shape as caption imports).
    @discardableResult
    func importTranscribedClip(
        videoID: String,
        title: String,
        result: TranscriptionResult,
        level: JLPTLevel? = nil
    ) -> Clip? {
        importYouTubeClip(
            videoID: videoID,
            title: title,
            cues: result.lines.map(\.subtitleCue),
            translation: result.chineseText ?? "",
            level: level,
            attribution: "字幕由自建服务器转写（\(result.provider ?? "server")）"
        )
    }

    /// Optional `GET /health` probe used by the settings screen.
    func pingTranscriptionServer() async -> String {
        guard let url = transcription.healthURL else { return "地址无效" }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return "响应不是 HTTP" }
            switch http.statusCode {
            case 200: return "服务器可用"
            case 404: return "服务器在线，但没有 /health（可忽略）"
            default: return "服务器返回 \(http.statusCode)"
            }
        } catch {
            return "连接失败：\(error.localizedDescription)"
        }
    }

    // MARK: Library browsing

    enum ClipSourceFilter: String, CaseIterable, Identifiable {
        case all, youtube, local, generated

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "全部"
            case .youtube: return "YouTube"
            case .local: return "本地"
            case .generated: return "朗读"
            }
        }
    }

    /// Clips for the library screen, filtered by estimated level, text and source.
    func libraryClips(
        level: JLPTLevel? = nil,
        query: String = "",
        source: ClipSourceFilter = .all
    ) -> [Clip] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return library.clips.filter { clip in
            if let level {
                let estimate = metricsByClip[clip.id]?.level ?? clip.level
                guard estimate == level else { return false }
            }
            switch source {
            case .all:
                break
            case .youtube:
                if case .youtube = clip.media {} else { return false }
            case .local:
                if case .localFile = clip.media {} else { return false }
            case .generated:
                if case .generated = clip.media {} else { return false }
            }
            guard !trimmed.isEmpty else { return true }
            return clip.title.localizedStandardContains(trimmed)
                || clip.series.localizedStandardContains(trimmed)
                || clip.transcript.localizedStandardContains(trimmed)
        }
        .sorted { lhs, rhs in
            let left = metricsByClip[lhs.id]?.level.rank ?? 9
            let right = metricsByClip[rhs.id]?.level.rank ?? 9
            if left != right { return left < right }
            return lhs.title < rhs.title
        }
    }

    // MARK: Backup, restore, interoperability

    func restore(from url: URL) throws -> RestoreReport {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let snapshot = try BackupService.decodeSnapshot(from: data)
        try BackupService.validate(snapshot)

        apply(snapshot)
        library.setCustom(customClips)
        refreshMetrics()
        reviewSession.reset()
        flushSave()
        return BackupService.report(for: snapshot)
    }

    func exportAnkiTSV() -> URL? {
        let content = BackupService.ankiTSV(words: words, decks: decks)
        guard !content.isEmpty else {
            toast = "生词本为空，没有可导出的卡片"
            return nil
        }
        let url = store.root.appendingPathComponent(BackupService.exportFileName())
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            toast = "导出失败：\(error.localizedDescription)"
            return nil
        }
    }

    // MARK: Review load forecast

    /// Cards scheduled per day, with overdue cards folded into today.
    func reviewForecast(days: Int = 7, now: Date = Date()) -> [ForecastDay] {
        let calendar = Calendar.current
        let todayKey = DayKey.key(for: now)
        var buckets: [String: Int] = [:]

        var dueDates: [Date] = []
        for word in words where !word.isIgnored && !word.scheduling.isNew {
            dueDates.append(word.scheduling.dueAt)
        }
        for card in sentenceCards {
            dueDates.append(card.scheduling.dueAt)
        }
        for date in dueDates {
            let effective = max(date, now)
            let key = DayKey.key(for: effective)
            buckets[key, default: 0] += 1
        }

        var result: [ForecastDay] = []
        for offset in 0..<max(days, 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let key = DayKey.key(for: day)
            result.append(
                ForecastDay(
                    dayKey: key,
                    date: day,
                    due: buckets[key] ?? 0,
                    isToday: key == todayKey
                )
            )
        }
        return result
    }

    /// Cards that were due before today started.
    var overdueCount: Int {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let wordOverdue = words.filter {
            !$0.isIgnored && !$0.scheduling.isNew && $0.scheduling.dueAt < startOfToday
        }.count
        let sentenceOverdue = sentenceCards.filter { $0.scheduling.dueAt < startOfToday }.count
        return wordOverdue + sentenceOverdue
    }

    // MARK: Data management

    func exportState() -> URL? {
        flushSave()
        do {
            return try store.exportJSON(makeSnapshot())
        } catch {
            toast = "导出失败：\(error.localizedDescription)"
            return nil
        }
    }

    func resetEverything() {
        words.removeAll()
        sentenceCards.removeAll()
        customClips.removeAll()
        activity.removeAll()
        watchHistory.removeAll()
        savedClipIDs.removeAll()
        explanations.removeAll()
        shadowingRecords.removeAll()
        kanjiCards.removeAll()
        clearShadowingFolder()
        decks = [Deck.makeDefault()]
        profile = UserProfile(displayName: profile.displayName, onboardingCompleted: false)
        library.setCustom([])
        store.reset()
        flushSave()
        toast = "已清空本地数据"
    }
}
