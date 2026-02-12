//
//  SequentialWordMatcher.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/11/26.
//

import Foundation

// MARK: - Sequential Word Matcher

/// Matches recognized speech against expected text in sequential (left-to-right) order.
///
/// Used during the listening phase to drive real-time word-by-word highlighting.
/// Word N only matches after words 0..<N have all matched, ensuring the highlight
/// progresses naturally from left to right as the user speaks.
///
/// ## Performance
/// O(n + m) where n = expected words, m = recognized words.
/// Safe to call every ~33ms during active listening without frame drops.
///
/// ## Normalization
/// Uses the same normalization as `TextAccuracyCalculator`: strips punctuation,
/// lowercases, and splits by whitespace. This ensures consistency between
/// word matching (for highlighting) and completion detection (for timeouts).
///
/// ## Algorithm
/// Walks the recognized words sequentially. For each recognized word, if it
/// matches the current expected word at the pointer, the pointer advances.
/// Filler words or re-starts in the transcript are skipped. The pointer
/// position at the end is the `matchedCount`.
///
/// ## Usage
/// ```swift
/// let result = SequentialWordMatcher.matchSequentially(
///     expected: "I am confident and strong",
///     recognized: "I am confident"
/// )
/// // result.matchedCount == 3
/// // result.totalExpectedWords == 5
/// // result.isComplete == false
/// ```
enum SequentialWordMatcher {

    // MARK: - Match Result

    /// Result of a sequential word match operation.
    struct MatchResult: Equatable, Sendable {

        /// Number of words matched sequentially from the start.
        let matchedCount: Int

        /// Total number of expected words in the affirmation.
        let totalExpectedWords: Int

        /// Whether all expected words have been matched.
        var isComplete: Bool {
            totalExpectedWords > 0 && matchedCount >= totalExpectedWords
        }
    }

    // MARK: - Public API

    /// Matches recognized text against expected text in sequential order.
    ///
    /// Words are matched strictly left-to-right: word N only matches after
    /// words 0..<N have all matched. Filler words in the recognized text
    /// (e.g., speech recognition artifacts) are skipped.
    ///
    /// - Parameters:
    ///   - expected: The full affirmation text the user should speak
    ///   - recognized: The partial or final transcription from speech recognition
    /// - Returns: Match result with count of sequentially matched words
    static func matchSequentially(
        expected: String,
        recognized: String
    ) -> MatchResult {
        let expectedWords = normalizeText(expected)
        let recognizedWords = normalizeText(recognized)

        guard !expectedWords.isEmpty else {
            return MatchResult(matchedCount: 0, totalExpectedWords: 0)
        }

        guard !recognizedWords.isEmpty else {
            return MatchResult(matchedCount: 0, totalExpectedWords: expectedWords.count)
        }

        var expectedIndex = 0

        for recognizedWord in recognizedWords {
            guard expectedIndex < expectedWords.count else { break }

            if recognizedWord == expectedWords[expectedIndex] {
                expectedIndex += 1
            }
        }

        return MatchResult(
            matchedCount: expectedIndex,
            totalExpectedWords: expectedWords.count
        )
    }

    /// Matches recognized text against pre-normalized expected words in sequential order.
    ///
    /// Use this overload when calling repeatedly with the same expected text
    /// (e.g., during a listening session) to avoid redundant normalization of
    /// the expected text on every call.
    ///
    /// - Parameters:
    ///   - expectedWords: Pre-normalized expected word array (from ``normalizeText(_:)``)
    ///   - recognized: The partial or final transcription from speech recognition
    /// - Returns: Match result with count of sequentially matched words
    static func matchSequentially(
        expectedWords: [String],
        recognized: String
    ) -> MatchResult {
        guard !expectedWords.isEmpty else {
            return MatchResult(matchedCount: 0, totalExpectedWords: 0)
        }

        let recognizedWords = normalizeText(recognized)

        guard !recognizedWords.isEmpty else {
            return MatchResult(matchedCount: 0, totalExpectedWords: expectedWords.count)
        }

        var expectedIndex = 0

        for recognizedWord in recognizedWords {
            guard expectedIndex < expectedWords.count else { break }

            if recognizedWord == expectedWords[expectedIndex] {
                expectedIndex += 1
            }
        }

        return MatchResult(
            matchedCount: expectedIndex,
            totalExpectedWords: expectedWords.count
        )
    }

    // MARK: - Normalization

    /// Normalizes text for word-level comparison.
    ///
    /// Strips punctuation, lowercases, and splits by whitespace.
    /// Matches `TextAccuracyCalculator.normalizeText()` for consistency.
    ///
    /// Call once before a listening session and pass the result to
    /// ``matchSequentially(expectedWords:recognized:)`` to avoid
    /// redundant normalization on every update.
    ///
    /// - Parameter text: Raw text to normalize
    /// - Returns: Array of normalized words
    static func normalizeText(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: .punctuationCharacters)
            .joined()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
    }
}
