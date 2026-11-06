import Foundation

// Minimal stand-ins so the app's decision layer can be compiled and executed on
// Linux (no SwiftUI / AVFoundation / Security). Only the surface the logic files
// touch is declared here; anything that actually depends on the platform lives
// in the real targets and is exercised on a device.

@propertyWrapper
final class Published<Value> {
    private final class Box {
        var value: Value
        init(_ value: Value) { self.value = value }
    }
    private let box: Box

    init(wrappedValue: Value) { box = Box(wrappedValue) }

    var wrappedValue: Value {
        get { box.value }
        set { box.value = newValue }
    }
}

protocol ObservableObject: AnyObject {}

struct Animation {
    static func spring(response: Double, dampingFraction: Double) -> Animation { Animation() }
    static func easeOut(duration: Double) -> Animation { Animation() }
    static func easeInOut(duration: Double) -> Animation { Animation() }
}

func withAnimation<Result>(_ animation: Animation?, _ body: () throws -> Result) rethrows -> Result {
    try body()
}

/// Storage stand-in: the real one writes JSON to Documents and needs no special API here.
final class PersistenceStore {
    let root: URL

    init() {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kotoba-harness", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func mediaDirectory() -> URL { root }
    func mediaURL(named name: String) -> URL { root.appendingPathComponent(name) }
    func resolvedMediaURL(named name: String) -> URL? {
        let url = root.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func load() -> AppSnapshot { AppSnapshot() }
    func save(_ snapshot: AppSnapshot) throws { }
    func exportJSON(_ snapshot: AppSnapshot) throws -> URL { root }
    func reset() { }
}

/// Speech stand-in: TTS is device-only.
final class SpeechService {
    var hasJapaneseVoice: Bool { true }
    func speak(_ text: String, rate: Double) { }
    func stop() { }
}

/// Keychain stand-in: only the "is a key stored?" question matters to the logic.
enum Secrets {
    static let aiKeyAccount = "ai.api.key"
    static func set(_ value: String, for account: String) { }
    static func value(for account: String) -> String? { nil }
    static func delete(_ account: String) { }
}

// Sandbox-scoped resource access only exists on Apple platforms.
#if !canImport(Darwin)
extension URL {
    func startAccessingSecurityScopedResource() -> Bool { false }
    func stopAccessingSecurityScopedResource() { }
}
#endif
