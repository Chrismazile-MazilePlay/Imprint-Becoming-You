//
//  SpacedRepetitionBuilder.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/10/26.
//

import Foundation

// MARK: - SpacedRepetitionBuilder

/// Pure algorithm that expands a base set of affirmations to 2x count
/// by interleaving randomized repeats for within-session reinforcement.
///
/// ## Algorithm: Variable-Repeat Randomized Interleave
///
/// Each affirmation appears **1 to 3 times** total (original + 0-2 repeats).
/// The total output is always `base.count * 2`.
///
/// ### Core Rules
/// 1. Each affirmation appears 1-3 times, randomly assigned
/// 2. Total capped at `2N` segments (e.g., 20 for base 10)
/// 3. A repeat can only appear after a **minimum gap of 2** from its last occurrence
/// 4. The repeat queue uses **weighted random selection** — items waiting longest have higher probability
/// 5. The cadence varies: sometimes 2 new → 1 repeat, sometimes 3 new → 1 repeat
///
/// ### Example Output
///
/// ```
/// Base: [A0] [A1] [A2] [A3] [A4] [A5] [A6] [A7] [A8] [A9]
///
/// Expanded (20 segments):
/// [A0] [A1] [A0] [A2] [A3] [A1] [A4] [A5] [A0] [A6] [A3] [A7] [A8] [A5] [A9] [A2] [A7] [A6] [A8] [A9]
///  new  new  1st  new  new  1st  new  new  2nd  new  1st  new  new  1st  new  1st  1st  1st  1st  1st
/// ```
///
/// ### TTS Cache Compatibility
///
/// The returned array contains the **same `Affirmation` references** at multiple indices.
/// Since `TTSAudioCache`, `SessionPlaybackCoordinator`, and `SessionTTSQueueService`
/// are all UUID-keyed, duplicate entries resolve to the same cached audio — zero
/// re-synthesis, zero extra memory.
///
/// ### Usage
///
/// ```swift
/// // In startSession(mode:)
/// if loopConfiguration.isSpacedRepetitionEnabled && sessionAffirmations.count > 1 {
///     let expanded = SpacedRepetitionBuilder.expand(sessionAffirmations)
///     setSessionAffirmationsForShuffle(expanded)
/// }
/// ```
enum SpacedRepetitionBuilder {

    /// Expands base affirmations to 2x count by interleaving randomized repeats.
    ///
    /// Each affirmation appears 1-3 times total. The distribution is random:
    /// some get 2 extra repeats (3 total), some 1 (2 total), some 0 (1 total).
    /// Total output is always `base.count * 2`.
    ///
    /// - Parameter base: The original session affirmations (typically 10)
    /// - Returns: Expanded array with the same Affirmation references at multiple indices
    static func expand(_ base: [Affirmation]) -> [Affirmation] {
        guard base.count > 1 else { return base + base }

        let targetCount = base.count * 2
        let extraSlots = base.count  // e.g., 10 extra slots to fill

        // Step 1: Randomly assign repeat counts (0, 1, or 2) per affirmation
        let repeatCounts = distributeRepeats(count: base.count, totalExtra: extraSlots)

        // Step 2: Build the repeat pool — each entry tracks remaining repeats
        // and last position for gap enforcement
        var repeatPool: [(affirmation: Affirmation, remainingRepeats: Int, lastPosition: Int)] = []

        var result: [Affirmation] = []
        var baseIndex = 0

        while result.count < targetCount {
            let remaining = targetCount - result.count
            let newRemaining = base.count - baseIndex
            let repeatsRemaining = repeatPool.reduce(0) { $0 + $1.remainingRepeats }

            // Determine whether to place a new item or a repeat
            var placeRepeat = false

            if newRemaining == 0 {
                // No new items left — must place repeats
                placeRepeat = true
            } else if repeatsRemaining == 0 {
                // No repeats available — must place new
                placeRepeat = false
            } else if remaining <= repeatsRemaining {
                // Must place repeats to fit them all before target
                placeRepeat = true
            } else {
                // Randomized cadence — increases probability as pool grows
                let repeatProbability = min(0.5, Double(repeatsRemaining) / Double(remaining))
                placeRepeat = Double.random(in: 0..<1) < repeatProbability
            }

            if placeRepeat, let picked = pickWeightedRepeat(
                from: &repeatPool, currentPosition: result.count
            ) {
                result.append(picked)
            } else if baseIndex < base.count {
                let item = base[baseIndex]
                result.append(item)
                // Add to repeat pool if this affirmation has repeats assigned
                let repeats = repeatCounts[baseIndex]
                if repeats > 0 {
                    repeatPool.append((
                        affirmation: item,
                        remainingRepeats: repeats,
                        lastPosition: result.count - 1
                    ))
                }
                baseIndex += 1
            } else if let picked = pickWeightedRepeat(
                from: &repeatPool, currentPosition: result.count
            ) {
                result.append(picked)
            } else {
                // Safety fallback: all branches failed (gap constraint too restrictive).
                // Force-pick the repeat with the largest gap, ignoring minimum gap.
                if let bestIndex = repeatPool.enumerated()
                    .filter({ $0.element.remainingRepeats > 0 })
                    .max(by: {
                        (result.count - $0.element.lastPosition) < (result.count - $1.element.lastPosition)
                    })?
                    .offset {
                    let item = repeatPool[bestIndex].affirmation
                    repeatPool[bestIndex].remainingRepeats -= 1
                    repeatPool[bestIndex].lastPosition = result.count
                    result.append(item)
                    if repeatPool[bestIndex].remainingRepeats == 0 {
                        repeatPool.remove(at: bestIndex)
                    }
                }
            }
        }

        return Array(result.prefix(targetCount))
    }

    // MARK: - Repeat Distribution

    /// Distributes `totalExtra` repeat slots across `count` affirmations.
    ///
    /// Each affirmation gets 0, 1, or 2 repeats. Sum always equals `totalExtra`.
    /// The distribution is randomized: ~40% chance of 2 repeats, ~60% chance of 1,
    /// with leftovers distributed to ensure the total is exact.
    ///
    /// - Parameters:
    ///   - count: Number of base affirmations
    ///   - totalExtra: Total extra slots to distribute (typically equal to `count`)
    /// - Returns: Array of repeat counts per affirmation (each 0, 1, or 2)
    private static func distributeRepeats(count: Int, totalExtra: Int) -> [Int] {
        var repeats = Array(repeating: 0, count: count)
        var remaining = totalExtra

        // Shuffle indices for random assignment order
        var indices = Array(0..<count)
        indices.shuffle()

        for i in indices {
            guard remaining > 0 else { break }
            // Assign 1 or 2 repeats randomly (weighted toward 1)
            let maxForThis = min(2, remaining)
            let assigned: Int
            if maxForThis == 2 {
                // ~40% chance of 2 repeats, ~60% chance of 1
                assigned = Double.random(in: 0..<1) < 0.4 ? 2 : 1
            } else {
                assigned = 1
            }
            repeats[i] = assigned
            remaining -= assigned
        }

        // Distribute any leftover (if random choices left some)
        while remaining > 0 {
            for i in indices where repeats[i] < 2 && remaining > 0 {
                repeats[i] += 1
                remaining -= 1
            }
        }

        return repeats
    }

    // MARK: - Weighted Selection

    /// Picks a repeat using weighted random selection.
    ///
    /// Enforces minimum gap of 2 positions from last occurrence.
    /// Items waiting longest have higher probability of being selected.
    /// Decrements remaining count; removes entry when exhausted.
    ///
    /// - Parameters:
    ///   - pool: Mutable pool of pending repeats
    ///   - currentPosition: Current position in the result array
    /// - Returns: The selected affirmation, or `nil` if no eligible repeats
    private static func pickWeightedRepeat(
        from pool: inout [(affirmation: Affirmation, remainingRepeats: Int, lastPosition: Int)],
        currentPosition: Int
    ) -> Affirmation? {
        let eligible = pool.enumerated().filter {
            $0.element.remainingRepeats > 0 && currentPosition - $0.element.lastPosition >= 2
        }
        guard !eligible.isEmpty else { return nil }

        // Weight by gap since last occurrence — longer gaps = higher selection probability
        let weights = eligible.map { Double(currentPosition - $0.element.lastPosition) }
        let totalWeight = weights.reduce(0, +)
        var random = Double.random(in: 0..<totalWeight)

        for (i, weight) in weights.enumerated() {
            random -= weight
            if random <= 0 {
                let poolIndex = eligible[i].offset
                pool[poolIndex].remainingRepeats -= 1
                pool[poolIndex].lastPosition = currentPosition
                let item = pool[poolIndex].affirmation
                if pool[poolIndex].remainingRepeats == 0 {
                    pool.remove(at: poolIndex)
                }
                return item
            }
        }

        // Fallback (should not reach here in practice)
        let poolIndex = eligible[0].offset
        pool[poolIndex].remainingRepeats -= 1
        pool[poolIndex].lastPosition = currentPosition
        let item = pool[poolIndex].affirmation
        if pool[poolIndex].remainingRepeats == 0 {
            pool.remove(at: poolIndex)
        }
        return item
    }
}
