import Foundation
import SwiftData

/// A Most Important Task (ADR-002).
///
/// Day/`*On` fields (`createdOn`, `completedOn`, `appearsOn`) are the canonical
/// LOCAL start-of-day `Date` produced via the `Clock` (ADR-038); no time-of-day
/// component ever leaks into them. Callers must pass clock-derived day keys.
///
/// Invariants enforced here:
///   * INV-1: `createdOn <= completedOn` whenever the task is completed, and a
///     `completedOn` is present iff `status == .completed`.
///   * INV-6: a soft-deleted MIT is RETAINED (`isDeleted == true`, `deletedAt`
///     stamped) but must be EXCLUDED from stats. Deletion never destroys rows;
///     use ``countsTowardStats`` / ``MIT.statsPredicate`` for aggregation.
@Model
public final class MIT {
    /// Stable identity (independent of SwiftData's `PersistentIdentifier`).
    public var id: UUID
    /// The task text.
    public var text: String
    /// Optional reason/context the user attached.
    public var reason: String?
    /// Lifecycle status (ADR-002).
    public var status: MITStatus
    /// The local start-of-day key the task was created on (ADR-038).
    public var createdOn: Date
    /// The local start-of-day key the task was completed on, or `nil` while open (INV-1).
    public var completedOn: Date?
    /// The local start-of-day key the task appears on the board (ADR-038).
    public var appearsOn: Date
    /// Backing store for the soft-delete flag (INV-6). See ``isDeleted``.
    ///
    /// NOT named `isDeleted`: `PersistentModel` already vends a read-only
    /// `isDeleted` (marked-for-context-deletion status). A stored `isDeleted`
    /// property collides with it and becomes unreadable — the protocol's value
    /// shadows it on read. We store under a distinct name and expose the spec's
    /// `isDeleted` contract via the ``isDeleted`` computed accessor below.
    public var isSoftDeleted: Bool
    /// When the MIT was soft-deleted, or `nil` if live (INV-6).
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        text: String,
        reason: String? = nil,
        status: MITStatus = .open,
        createdOn: Date,
        completedOn: Date? = nil,
        appearsOn: Date,
        isDeleted: Bool = false,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.reason = reason
        self.status = status
        self.createdOn = createdOn
        self.completedOn = completedOn
        self.appearsOn = appearsOn
        self.isSoftDeleted = isDeleted
        self.deletedAt = deletedAt
    }
}

// MARK: - Invariants (model/service layer)

public extension MIT {
    /// Errors raised when a mutation would violate a model-layer invariant.
    enum InvariantError: Error, Equatable {
        /// INV-1: a completion day earlier than the creation day was supplied.
        case completedBeforeCreated(createdOn: Date, completedOn: Date)
    }

    /// The soft-delete flag (INV-6), exposing the spec's `isDeleted` contract over
    /// the ``isSoftDeleted`` backing store (which avoids the reserved name).
    var isDeleted: Bool {
        get { isSoftDeleted }
        set { isSoftDeleted = newValue }
    }

    /// Whether this MIT counts toward statistics (INV-6): live (not soft-deleted).
    ///
    /// Soft-deleted MITs are retained in the store for history/undo but are
    /// EXCLUDED from every stat aggregation.
    var countsTowardStats: Bool {
        !isSoftDeleted
    }

    /// A `#Predicate` selecting only MITs that count toward stats (INV-6).
    ///
    /// Use this for every stats/aggregation fetch so soft-deleted rows are never
    /// counted, while remaining queryable for history.
    static var statsPredicate: Predicate<MIT> {
        #Predicate<MIT> { !$0.isSoftDeleted }
    }

    /// Mark the task completed on the given local day key, enforcing INV-1.
    ///
    /// - Parameter day: the canonical LOCAL start-of-day key (ADR-038), normally
    ///   `clock.today()`.
    /// - Throws: ``InvariantError/completedBeforeCreated(createdOn:completedOn:)``
    ///   if `day < createdOn` (INV-1).
    func markCompleted(on day: Date) throws {
        guard day >= createdOn else {
            throw InvariantError.completedBeforeCreated(createdOn: createdOn, completedOn: day)
        }
        status = .completed
        completedOn = day
    }

    /// Reopen the task, clearing its completion stamp (INV-1: no `completedOn` while open).
    func reopen() {
        status = .open
        completedOn = nil
    }

    /// Soft-delete the task on the given instant (INV-6): retained, excluded from stats.
    ///
    /// - Parameter date: the deletion timestamp (`clock.now()`).
    func softDelete(at date: Date) {
        isSoftDeleted = true
        deletedAt = date
    }

    /// Restore a soft-deleted task (INV-6).
    func restore() {
        isSoftDeleted = false
        deletedAt = nil
    }

    /// Validate INV-1 for the CURRENT state: if completed, `completedOn` must be
    /// present and `>= createdOn`; if open, `completedOn` must be `nil`.
    ///
    /// - Throws: ``InvariantError/completedBeforeCreated(createdOn:completedOn:)``.
    func validateInvariants() throws {
        switch status {
        case .completed:
            if let completedOn, completedOn < createdOn {
                throw InvariantError.completedBeforeCreated(createdOn: createdOn, completedOn: completedOn)
            }
        case .open:
            break
        }
    }
}
