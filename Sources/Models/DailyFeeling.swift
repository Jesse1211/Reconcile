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
/// for a day. Scale bounds are enforced by REJECTION: any write of a mood/stress
/// outside `0...5` throws ``InvariantError`` — out-of-range values are never
/// silently coerced, so caller bugs surface instead of being hidden.
@Model
public final class DailyFeeling {
    /// The canonical LOCAL start-of-day key (ADR-038). Unique per day (INV-7).
    @Attribute(.unique) public var day: Date
    /// Stable identity (independent of SwiftData's `PersistentIdentifier`).
    public var id: UUID
    /// Mood on the `0...5` scale (INV-7). Only ever set through validated paths.
    public private(set) var mood: Int
    /// Stress on the `0...5` scale (INV-7). Only ever set through validated paths.
    public private(set) var stress: Int
    /// Optional free-text reflection.
    public var whyText: String?

    /// Create a feeling, REJECTING out-of-range scales (INV-7).
    ///
    /// - Throws: ``InvariantError/moodOutOfRange(_:)`` or
    ///   ``InvariantError/stressOutOfRange(_:)`` if `mood`/`stress` fall outside
    ///   `0...5` (e.g. `-1` or `6`). Values are NEVER clamped.
    public init(
        id: UUID = UUID(),
        day: Date,
        mood: Int,
        stress: Int,
        whyText: String? = nil
    ) throws {
        try DailyFeeling.validateMood(mood)
        try DailyFeeling.validateStress(stress)
        self.id = id
        self.day = day
        self.mood = mood
        self.stress = stress
        self.whyText = whyText
    }
}

public extension DailyFeeling {
    /// The valid feeling-scale range (INV-7).
    static let scale = 0...5

    /// Errors raised when a mutation would violate a model-layer invariant (INV-7).
    enum InvariantError: Error, Equatable {
        /// INV-7: a `mood` outside `0...5` was supplied.
        case moodOutOfRange(Int)
        /// INV-7: a `stress` outside `0...5` was supplied.
        case stressOutOfRange(Int)
    }

    /// Validate a raw `mood`, REJECTING out-of-range values (INV-7).
    ///
    /// - Throws: ``InvariantError/moodOutOfRange(_:)`` if `value` is not in `0...5`.
    static func validateMood(_ value: Int) throws {
        guard scale.contains(value) else {
            throw InvariantError.moodOutOfRange(value)
        }
    }

    /// Validate a raw `stress`, REJECTING out-of-range values (INV-7).
    ///
    /// - Throws: ``InvariantError/stressOutOfRange(_:)`` if `value` is not in `0...5`.
    static func validateStress(_ value: Int) throws {
        guard scale.contains(value) else {
            throw InvariantError.stressOutOfRange(value)
        }
    }

    /// Set `mood`, REJECTING an out-of-range value (INV-7).
    ///
    /// - Throws: ``InvariantError/moodOutOfRange(_:)`` if `value` is not in `0...5`.
    func setMood(_ value: Int) throws {
        try DailyFeeling.validateMood(value)
        mood = value
    }

    /// Set `stress`, REJECTING an out-of-range value (INV-7).
    ///
    /// - Throws: ``InvariantError/stressOutOfRange(_:)`` if `value` is not in `0...5`.
    func setStress(_ value: Int) throws {
        try DailyFeeling.validateStress(value)
        stress = value
    }

    /// Validate the CURRENT stored state against INV-7 (both scales in `0...5`).
    ///
    /// - Throws: ``InvariantError`` if either stored value has drifted out of range.
    func validateInvariants() throws {
        try DailyFeeling.validateMood(mood)
        try DailyFeeling.validateStress(stress)
    }
}

// MARK: - One-per-day upsert (INV-7)

public extension DailyFeeling {
    /// Insert or update the single `DailyFeeling` for `day` (INV-7).
    ///
    /// Guarantees at most one row per day: if a feeling already exists for the
    /// day it is UPDATED in place; otherwise a new one is inserted. Out-of-range
    /// `mood`/`stress` values are REJECTED (thrown) BEFORE any mutation, so a
    /// rejected upsert leaves the store untouched — values are never clamped.
    ///
    /// - Parameters:
    ///   - day: the canonical LOCAL start-of-day key (ADR-038).
    ///   - context: the SwiftData context to read/write through.
    /// - Returns: the upserted feeling.
    /// - Throws: ``InvariantError`` if `mood`/`stress` fall outside `0...5`.
    @discardableResult
    static func upsert(
        day: Date,
        mood: Int,
        stress: Int,
        whyText: String?,
        in context: ModelContext
    ) throws -> DailyFeeling {
        // Reject out-of-range writes up front so a failed upsert never mutates
        // an existing row nor inserts a partially-valid one (INV-7).
        try validateMood(mood)
        try validateStress(stress)

        let existing = try fetch(day: day, in: context)
        if let existing {
            try existing.setMood(mood)
            try existing.setStress(stress)
            existing.whyText = whyText
            return existing
        }
        let created = try DailyFeeling(day: day, mood: mood, stress: stress, whyText: whyText)
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
