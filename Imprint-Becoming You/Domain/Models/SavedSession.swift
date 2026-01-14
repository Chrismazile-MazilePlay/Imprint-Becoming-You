//
//  SavedSession.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/12/26.
//

import Foundation
import SwiftData

// MARK: - SavedSession

/// A user-saved session configuration for replay.
///
/// Allows users to save a specific set of affirmations as a named session
/// for easy replay with customizable loop and shuffle options.
///
/// ## Features
/// - **Named Sessions**: User-provided name with auto-generated default
/// - **Ordered Affirmations**: Preserves original affirmation order
/// - **Default Mode**: Remembers preferred session mode
/// - **Reference Protection**: Affirmations in saved sessions cannot be deleted
///
/// ## Limits
/// - Free users: 3 saved sessions maximum
/// - Premium users: Unlimited saved sessions
///
/// ## Usage
/// ```swift
/// // Create a saved session
/// let session = SavedSession(
///     name: "Morning Confidence",
///     affirmationIds: affirmations.map(\.id),
///     defaultMode: .readThenSpeak,
///     affirmations: affirmations
/// )
///
/// // Play saved session
/// store.send(.startSavedSession(session))
/// ```
@Model
final class SavedSession {
    
    // MARK: - Identity Properties
    
    /// Unique identifier for the saved session
    @Attribute(.unique)
    var id: UUID
    
    /// User-provided name for the session
    var name: String
    
    /// Date when the session was created
    var createdAt: Date
    
    /// Date when the session was last played
    var lastPlayedAt: Date?
    
    // MARK: - Configuration Properties
    
    /// Default session mode (stored as raw value for persistence)
    var defaultModeRawValue: String
    
    /// Sort order for display (lower = higher in list)
    var sortOrder: Int
    
    // MARK: - Affirmation Storage
    
    /// Ordered affirmation IDs encoded as Data.
    ///
    /// We store IDs separately from the relationship to preserve order,
    /// since SwiftData relationships don't guarantee ordering.
    private var affirmationIdsData: Data
    
    /// Relationship to affirmations (for reference counting/protection).
    ///
    /// This inverse relationship allows us to check if an affirmation
    /// is part of any saved session before deletion.
    @Relationship(inverse: \Affirmation.savedSessions)
    var affirmations: [Affirmation]
    
    // MARK: - Initialization
    
    /// Creates a new saved session.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (defaults to new UUID)
    ///   - name: User-provided session name
    ///   - affirmationIds: Ordered array of affirmation UUIDs
    ///   - defaultMode: Preferred session mode for playback
    ///   - sortOrder: Display order (defaults to 0)
    ///   - affirmations: The actual affirmation objects for relationship
    ///   - createdAt: Creation timestamp (defaults to now)
    ///   - lastPlayedAt: Last playback timestamp (defaults to nil)
    init(
        id: UUID = UUID(),
        name: String,
        affirmationIds: [UUID],
        defaultMode: SessionMode,
        sortOrder: Int = 0,
        affirmations: [Affirmation] = [],
        createdAt: Date = Date(),
        lastPlayedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.lastPlayedAt = lastPlayedAt
        self.defaultModeRawValue = defaultMode.rawValue
        self.sortOrder = sortOrder
        self.affirmations = affirmations
        
        // Encode affirmation IDs to Data
        self.affirmationIdsData = (try? JSONEncoder().encode(affirmationIds)) ?? Data()
    }
    
    // MARK: - Computed Properties
    
    /// Ordered affirmation IDs (decoded from storage)
    var affirmationIds: [UUID] {
        get {
            (try? JSONDecoder().decode([UUID].self, from: affirmationIdsData)) ?? []
        }
        set {
            affirmationIdsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
    
    /// The default session mode as enum
    var defaultMode: SessionMode {
        SessionMode(rawValue: defaultModeRawValue) ?? .readThenSpeak
    }
    
    /// Number of affirmations in this session
    var affirmationCount: Int {
        affirmationIds.count
    }
    
    /// Whether this session is empty (no affirmations)
    var isEmpty: Bool {
        affirmationIds.isEmpty
    }
    
    /// Formatted creation date for display
    var formattedCreatedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: createdAt)
    }
    
    /// Short date format for default naming (e.g., "Jan 11")
    var shortCreatedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: createdAt)
    }
    
    /// Formatted last played date for display
    var formattedLastPlayedDate: String? {
        guard let lastPlayedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastPlayedAt, relativeTo: Date())
    }
    
    // MARK: - Methods
    
    /// Updates the default mode for this session.
    ///
    /// - Parameter mode: The new default session mode
    func setDefaultMode(_ mode: SessionMode) {
        defaultModeRawValue = mode.rawValue
    }
    
    /// Records that this session was played.
    func recordPlayback() {
        lastPlayedAt = Date()
    }
}

// MARK: - Sample Data

extension SavedSession {
    
    /// Sample saved session for previews
    static var sample: SavedSession {
        SavedSession(
            name: "Morning Confidence",
            affirmationIds: Affirmation.samples.map(\.id),
            defaultMode: .readThenSpeak,
            affirmations: Affirmation.samples
        )
    }
    
    /// Collection of sample saved sessions for previews
    static var samples: [SavedSession] {
        [
            SavedSession(
                name: "Morning Confidence",
                affirmationIds: Array(Affirmation.samples.prefix(5)).map(\.id),
                defaultMode: .readThenSpeak,
                sortOrder: 0,
                affirmations: Array(Affirmation.samples.prefix(5))
            ),
            SavedSession(
                name: "Evening Peace",
                affirmationIds: Array(Affirmation.samples.suffix(3)).map(\.id),
                defaultMode: .readAloud,
                sortOrder: 1,
                affirmations: Array(Affirmation.samples.suffix(3))
            ),
            SavedSession(
                name: "Focus Session",
                affirmationIds: Affirmation.samples.map(\.id),
                defaultMode: .speakOnly,
                sortOrder: 2,
                affirmations: Affirmation.samples
            )
        ]
    }
}
