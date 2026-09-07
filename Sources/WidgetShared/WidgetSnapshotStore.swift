import Foundation

/// The shared-container persistence boundary for the widget snapshot (ADR-042).
///
/// A tiny read/write seam over the App Group container. The app-side
/// ``WidgetSnapshotWriter`` writes through it; the extension-side
/// ``WidgetSnapshotLoader`` reads through it. Behind a protocol so the REAL_STACK
/// gate can round-trip through a real App Group `UserDefaults` while unit tests
/// inject an in-memory double — WITHOUT the widget ever gaining a write path of its
/// own (the loader only calls `read`).
public protocol WidgetSnapshotStore: AnyObject {
    /// Read the current snapshot, or `nil` if none has been written yet.
    func read() -> WidgetSnapshot?
    /// Overwrite the stored snapshot (app-side single writer only, ADR-042).
    func write(_ snapshot: WidgetSnapshot)
}

/// The production store backed by the App Group shared `UserDefaults` (ADR-042).
///
/// This is the REAL shared container the snapshot round-trips through: the app
/// writes a JSON-encoded ``WidgetSnapshot`` under a single key, the widget reads it
/// back. Encoding uses ISO-8601-friendly `Date` handling so `runningStartedAt` and
/// `day` survive the round-trip intact.
public final class AppGroupSnapshotStore: WidgetSnapshotStore {
    private let defaults: UserDefaults
    private let key = "widget.snapshot.v1"

    /// Create a store over a specific `UserDefaults` suite.
    ///
    /// - Parameter defaults: the App Group suite (defaults to
    ///   ``AppGroup/sharedDefaults()``). Falls back to `.standard` only if the App
    ///   Group is unavailable, so the app still functions without the entitlement.
    public init(defaults: UserDefaults? = AppGroup.sharedDefaults()) {
        self.defaults = defaults ?? .standard
    }

    public func read() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? Self.decoder.decode(WidgetSnapshot.self, from: data)
    }

    public func write(_ snapshot: WidgetSnapshot) {
        guard let data = try? Self.encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// An in-memory snapshot store for unit tests and previews (no shared container).
public final class InMemorySnapshotStore: WidgetSnapshotStore {
    private var snapshot: WidgetSnapshot?

    public init(snapshot: WidgetSnapshot? = nil) {
        self.snapshot = snapshot
    }

    public func read() -> WidgetSnapshot? { snapshot }
    public func write(_ snapshot: WidgetSnapshot) { self.snapshot = snapshot }
}
