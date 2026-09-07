import Foundation

/// The lifecycle status of a Most Important Task (ADR-002).
///
/// An MIT is `open` until it is checked off, at which point it becomes
/// `completed` and a `completedOn` day key is stamped (INV-1). Stored as a raw
/// `String` so the value is stable across SwiftData migrations.
public enum MITStatus: String, CaseIterable, Codable, Sendable {
    /// Not yet completed.
    case open
    /// Checked off; `completedOn` is set (INV-1).
    case completed
}
