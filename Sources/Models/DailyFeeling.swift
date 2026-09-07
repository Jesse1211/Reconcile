import Foundation
import SwiftData

/// The user's daily mood/stress check-in (ADR-002).
///
/// `day` is the canonical LOCAL start-of-day `Date` (ADR-038).
///
/// INV-7: there is exactly ONE `DailyFeeling` per `day`, and both `mood` and
/// `stress` live on the `0...5` scale. Uniqueness is enforced by SwiftData's
/// `@Attribute(.unique)` on `day` PLUS an upsert path
/// (``upsert(day:mood:stress:whyText:in:)``) so writes never create a second row
/// for a day. Scale bounds are enforced by clamping on write.
@Model
public final class DailyFeeling {
    /// The canonical LOCAL start-of-day key (ADR-038). Unique per day (INV-7).
    @Attribute(.unique) public var day: Date
    /// Stable identity (independent of SwiftData's `PersistentIdentifier`).
    public var id: UUID
    /// Mood on the `0...5` scale (INV-7).
    public var mood: Int
    /// Stress on the `0...5` scale (INV-7).
    public var stress: Int
    /// Optional free-text reflection.
    public var whyText: String?

    public init(
        id: UUID = UUID(),
        day: Date,
        mood: Int,
        stress: Int,
        whyText: String? = nil
    ) {
        self.id = id
        self.day = day
        self.mood = DailyFeeling.clampScale(mood)
        self.stress = DailyFeeling.clampScale(stress)
        self.whyText = whyText
    }
}

public extension DailyFeeling {
    /// The valid feeling-scale range (INV-7).
    static let scale = 0...5

    /// Clamp a raw value into the `0...5` scale (INV-7).
    static func clampScale(_ value: Int) -> Int {
        min(max(value, scale.lowerBound), scale.upperBound)
    }

    /// Set `mood`, clamped to `0...5` (INV-7).
    func setMood(_ value: Int) {
        mood = DailyFeeling.clampScale(value)
    }

    /// Set `stress`, clamped to `0...5` (INV-7).
    func setStress(_ value: Int) {
        stress = DailyFeeling.clampScale(value)
    }
}

// MARK: - One-per-day upsert (INV-7)

public extension DailyFeeling {
    /// Insert or update the single `DailyFeeling` for `day` (INV-7).
    ///
    /// Guarantees at most one row per day: if a feeling already exists for the
    /// day it is UPDATED in place; otherwise a new one is inserted. Values are
    /// clamped to `0...5`.
    ///
    /// - Parameters:
    ///   - day: the canonical LOCAL start-of-day key (ADR-038).
    ///   - context: the SwiftData context to read/write through.
    /// - Returns: the upserted feeling.
    @discardableResult
    static func upsert(
        day: Date,
        mood: Int,
        stress: Int,
        whyText: String?,
        in context: ModelContext
    ) throws -> DailyFeeling {
        let existing = try fetch(day: day, in: context)
        if let existing {
            existing.setMood(mood)
            existing.setStress(stress)
            existing.whyText = whyText
            return existing
        }
        let created = DailyFeeling(day: day, mood: mood, stress: stress, whyText: whyText)
        context.insert(created)
        return created
    }

    /// Fetch the single `DailyFeeling` for `day`, if any (INV-7).
    static func fetch(day: Date, in context: ModelContext) throws -> DailyFeeling? {
        var descriptor = FetchDescriptor<DailyFeeling>(
            predicate: #Predicate { $0.day == day }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
