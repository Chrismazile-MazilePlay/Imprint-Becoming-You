//
//  LoopConfiguration.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/12/26.
//

import Foundation

// MARK: - LoopConfiguration

/// Configuration for session looping and shuffling behavior.
///
/// ## Loop Options
/// - `1`: Single play (default) - session plays once
/// - `3`: Triple play - session plays 3 consecutive times
/// - `5`: Quintuple play - session plays 5 consecutive times
///
/// ## Shuffle Behavior
/// When enabled, affirmations are shuffled at the start of each loop iteration.
/// Each loop gets its own unique shuffled order.
///
/// ## State Reset
/// Configuration resets to default when:
/// - User taps Close button on results summary
/// - User taps floating X button to exit session
/// - Session is dismissed via any close action
///
/// ## Usage
/// ```swift
/// var config = LoopConfiguration()
/// config.cycleLoopCount()  // 1 → 3 → 5 → 1
/// config.toggleShuffle()   // Toggle shuffle on/off
///
/// // During session
/// if config.shouldAdvanceToNextLoop {
///     config.advanceLoop()
///     // Shuffle if enabled, reset index, continue
/// }
/// ```
struct LoopConfiguration: Equatable, Sendable {
    
    // MARK: - Properties
    
    /// Number of times to play through the session (1, 3, or 5)
    var loopCount: Int = 1
    
    /// Whether to shuffle affirmation order at start of each loop
    var isShuffleEnabled: Bool = false

    /// Whether spaced repetition is enabled (doubles session with interleaved repeats).
    ///
    /// When enabled, `SpacedRepetitionBuilder.expand()` doubles the session from
    /// N to 2N segments by interleaving randomized repeats. Each affirmation appears
    /// 1-3 times total. The expansion happens once in `startSession()` and persists
    /// across loops and repeats.
    var isSpacedRepetitionEnabled: Bool = false

    /// Current loop iteration (1-based, starts at 1)
    var currentLoopIteration: Int = 1
    
    // MARK: - Computed Properties
    
    /// Whether looping is active (more than single play)
    var isLooping: Bool {
        loopCount > 1
    }
    
    /// Whether all loops have been completed
    var isComplete: Bool {
        currentLoopIteration > loopCount
    }
    
    /// Whether there are more loops remaining after current one
    var hasMoreLoops: Bool {
        currentLoopIteration < loopCount
    }
    
    /// Whether we should advance to the next loop (current loop just finished)
    var shouldAdvanceToNextLoop: Bool {
        currentLoopIteration < loopCount
    }
    
    /// Progress text for UI display (e.g., "Loop 2 of 3")
    /// Returns nil if not looping (single play)
    var progressText: String? {
        guard isLooping else { return nil }
        return "Loop \(currentLoopIteration) of \(loopCount)"
    }
    
    // MARK: - Mutations
    
    /// Cycles through loop count options: 1 → 3 → 5 → 1
    mutating func cycleLoopCount() {
        switch loopCount {
        case 1:
            loopCount = 3
        case 3:
            loopCount = 5
        default:
            loopCount = 1
        }
    }
    
    /// Toggles shuffle on/off
    mutating func toggleShuffle() {
        isShuffleEnabled.toggle()
    }
    
    /// Advances to the next loop iteration
    mutating func advanceLoop() {
        currentLoopIteration += 1
    }
    
    /// Resets iteration counter to 1 (for starting a new repeat)
    mutating func resetIteration() {
        currentLoopIteration = 1
    }
    
    /// Resets entire configuration to defaults
    mutating func reset() {
        loopCount = 1
        isShuffleEnabled = false
        isSpacedRepetitionEnabled = false
        currentLoopIteration = 1
    }
    
    // MARK: - Static
    
    /// Default configuration (single play, no shuffle)
    static let `default` = LoopConfiguration()
    
    /// Available loop count options
    static let loopOptions = [1, 3, 5]

    /// Extended loop count options (page 2 — doubled values)
    static let extendedLoopOptions = [2, 6, 10]
}

// MARK: - Preview Support

extension LoopConfiguration {
    
    /// Preview configuration with 3 loops enabled
    static var previewLooping: LoopConfiguration {
        var config = LoopConfiguration()
        config.loopCount = 3
        config.currentLoopIteration = 2
        return config
    }
    
    /// Preview configuration with shuffle enabled
    static var previewShuffled: LoopConfiguration {
        var config = LoopConfiguration()
        config.isShuffleEnabled = true
        return config
    }
    
    /// Preview configuration with both loop and shuffle
    static var previewFull: LoopConfiguration {
        var config = LoopConfiguration()
        config.loopCount = 5
        config.isShuffleEnabled = true
        config.currentLoopIteration = 3
        return config
    }

    /// Preview configuration with spaced repetition enabled
    static var previewSpacedRepetition: LoopConfiguration {
        var config = LoopConfiguration()
        config.isSpacedRepetitionEnabled = true
        return config
    }
}
