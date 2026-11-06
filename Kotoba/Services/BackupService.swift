import Foundation

struct RestoreReport: Equatable {
    let words: Int
    let sentences: Int
    let decks: Int
    let clips: Int
    let activityDays: Int

    var summary: String {
        "生词 \(words) ・ 整句 \(sentences) ・ 分组 \(decks) ・ 片段 \(clips) ・ 记录 \(activityDays) 天"
    }
}

enum BackupError: LocalizedError {
    case unreadable
    case emptyBackup
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "这个文件不是 Kotoba 的备份（应为本应用导出的 JSON）"
        case .emptyBackup:
            return "备份里没有任何学习记录，已取消恢复以免覆盖现有数据"
        case .unsupportedSchema(let version):
            return "备份格式版本 \(version) 比当前应用更新，请先升级应用"
        }
    }
}

/// Reading/writing the app's own backup format, plus an Anki-compatible export.
///
/// Kept free of UI and storage so the logic can be executed on any host.
enum BackupService {
    static let schemaVersion = 1

    static func decodeSnapshot(from data: Data) throws -> AppSnapshot {
        let isoDecoder = JSONDecoder()
        isoDecoder.dateDecodingStrategy = .iso8601
        if let snapshot = try? isoDecoder.decode(AppSnapshot.self, from: data) {
            return snapshot
        }
        // Older exports (or hand-edited files) may use the default date strategy.
        if let snapshot = try? JSONDecoder().decode(AppSnapshot.self, from: data) {
            return snapshot
        }
        throw BackupError.unreadable
    }

    static func validate(_ snapshot: AppSnapshot) throws {
        guard snapshot.schemaVersion <= schemaVersion else {
            throw BackupError.unsupportedSchema(snapshot.schemaVersion)
        }
        let hasContent = !snapshot.words.isEmpty
            || !snapshot.sentenceCards.isEmpty
            || !snapshot.customClips.isEmpty
            || !snapshot.activity.isEmpty
        guard hasContent else { throw BackupError.emptyBackup }
    }

    static func report(for snapshot: AppSnapshot) -> RestoreReport {
        RestoreReport(
            words: snapshot.words.count,
            sentences: snapshot.sentenceCards.count,
            decks: snapshot.decks.count,
            clips: snapshot.customClips.count,
            activityDays: snapshot.activity.count
        )
    }

    /// Tab separated rows: word, reading, meanings, source sentence, tags.
    /// Anki imports this as a plain text file with tab separators; fields must not
    /// contain tabs or raw newlines, and tags must not contain spaces.
    static func ankiTSV(words: [SavedWord], decks: [Deck]) -> String {
        guard !words.isEmpty else { return "" }
        var deckNames: [String: String] = [:]
        for deck in decks { deckNames[deck.id] = deck.name }

        var rows: [String] = []
        for word in words {
            var tags = ["Kotoba"]
            if let level = word.level { tags.append(level.label) }
            for identifier in word.deckIDs {
                if let name = deckNames[identifier] { tags.append(tagSafe(name)) }
            }
            if word.familiarity >= 4 { tags.append("familiar") }
            if word.isIgnored { tags.append("ignored") }

            let fields = [
                word.word,
                word.reading,
                word.meanings.joined(separator: " / "),
                word.sourceSentence ?? "",
                tags.joined(separator: " ")
            ]
            rows.append(fields.map(escapeField).joined(separator: "\t"))
        }
        return rows.joined(separator: "\n")
    }

    static func exportFileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "Kotoba-Anki-\(formatter.string(from: date)).tsv"
    }

    private static func escapeField(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " / ")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func tagSafe(_ value: String) -> String {
        escapeField(value).replacingOccurrences(of: " ", with: "_")
    }
}
