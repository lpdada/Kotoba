import Foundation

struct ClipCollection: Codable {
    let version: Int
    let clips: [Clip]
}

/// Owns clip content: the bundled starter library plus anything you import.
final class ClipLibrary: ObservableObject {
    @Published private(set) var clips: [Clip] = []

    private var bundled: [Clip] = []
    private var custom: [Clip] = []
    private let store: PersistenceStore
    private var analysisCache: [String: ClipAnalysis] = [:]

    init(store: PersistenceStore) {
        self.store = store
    }

    // MARK: Loading

    func load(customClips: [Clip]) {
        if bundled.isEmpty {
            bundled = Self.loadBundled()
        }
        custom = customClips
        clips = bundled + custom
        analysisCache.removeAll()
    }

    static func loadBundled() -> [Clip] {
        guard let url = Bundle.main.url(forResource: "SampleClips", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        do {
            let collection = try JSONDecoder().decode(ClipCollection.self, from: data)
            return collection.clips
        } catch {
            return []
        }
    }

    // MARK: Custom content

    func setCustom(_ newClips: [Clip]) {
        custom = newClips
        clips = bundled + custom
        analysisCache.removeAll()
    }

    func add(_ newClips: [Clip]) {
        custom.append(contentsOf: newClips)
        clips = bundled + custom
    }

    func removeCustom(id: String) {
        custom.removeAll { $0.id == id }
        clips = bundled + custom
        analysisCache.removeValue(forKey: id)
    }

    func clip(id: String) -> Clip? {
        clips.first { $0.id == id }
    }

    // MARK: Media

    func mediaURL(for clip: Clip) -> URL? {
        switch clip.media {
        case .localFile(let name):
            return store.resolvedMediaURL(named: name)
        case .remote(let address):
            return URL(string: address)
        case .generated, .youtube:
            return nil
        }
    }

    // MARK: Analysis

    func analysis(for clip: Clip, tokenizer: Tokenizer) -> ClipAnalysis {
        if let cached = analysisCache[clip.id] { return cached }
        let result = tokenizer.analyze(clip)
        analysisCache[clip.id] = result
        return result
    }

    func metrics(for clip: Clip, tokenizer: Tokenizer) -> ClipMetrics {
        analysis(for: clip, tokenizer: tokenizer).metrics
    }

    /// Clips whose subtitles contain the given dictionary form — the "search a
    /// word, hear it in context" view.
    func clips(containing lemma: String, tokenizer: Tokenizer) -> [Clip] {
        clips.filter { clip in
            let analysis = analysis(for: clip, tokenizer: tokenizer)
            return analysis.allTokens.contains { $0.lookupKey == lemma || $0.text == lemma }
        }
    }

    var topicCatalog: [String] {
        Array(Set(clips.flatMap(\.topics))).sorted()
    }
}
