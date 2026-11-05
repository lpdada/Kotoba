import Foundation
import Security

/// File based persistence: one JSON document plus a media folder.
///
/// A single document keeps writes atomic and makes export / reset trivial, which
/// matters for an app that is meant to be personal and inspectable.
final class PersistenceStore {
    let root: URL
    private let stateURL: URL
    private let mediaURL: URL

    init(fileManager: FileManager = .default) {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        root = documents
        stateURL = documents.appendingPathComponent("KotobaState.json")
        mediaURL = documents.appendingPathComponent("Media", isDirectory: true)
        try? fileManager.createDirectory(at: mediaURL, withIntermediateDirectories: true)
    }

    func mediaDirectory() -> URL { mediaURL }

    func mediaURL(named name: String) -> URL { mediaURL.appendingPathComponent(name) }

    func resolvedMediaURL(named name: String) -> URL? {
        let url = mediaURL(named: name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var stateFileURL: URL { stateURL }

    // MARK: Load / save

    func load() -> AppSnapshot {
        guard let data = try? Data(contentsOf: stateURL) else { return AppSnapshot() }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(AppSnapshot.self, from: data)
        } catch {
            // Keep a copy of the unreadable file instead of silently destroying it.
            let backup = root.appendingPathComponent("KotobaState.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: stateURL, to: backup)
            return AppSnapshot()
        }
    }

    func save(_ snapshot: AppSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let temporary = stateURL.appendingPathExtension("tmp")
        try data.write(to: temporary, options: .atomic)
        _ = try FileManager.default.replaceItemAt(stateURL, withItemAt: temporary)
    }

    func exportJSON(_ snapshot: AppSnapshot) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = root.appendingPathComponent("KotobaExport-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    func reset() {
        try? FileManager.default.removeItem(at: stateURL)
    }
}

// MARK: - Keychain

/// The AI key lives in the keychain, not in the state document.
enum Secrets {
    private static let service = "app.kotoba.secrets"

    static func set(_ value: String, for account: String) {
        let data = Data(value.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func value(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static let aiKeyAccount = "ai.api.key"
}
