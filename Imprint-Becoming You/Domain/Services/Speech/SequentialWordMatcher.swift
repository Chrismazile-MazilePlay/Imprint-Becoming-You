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
/// Walks the recognized words sequentially. For each recognized word, tries
/// four matching strategies in order: (1) exact match, (2) fuzzy match,
/// (3) compound word detection, (4) substring split detection. If any
/// strategy succeeds, the pointer advances. Filler words or re-starts in
/// the transcript are skipped. The pointer position at the end is the
/// `matchedCount`.
///
/// ## Fuzzy Matching
/// When exact equality fails, words are compared using Levenshtein edit
/// distance with **lenient** thresholds designed for encouragement, not
/// accuracy. Users with accents or slight mispronunciations still see
/// their words highlight. Only obviously wrong words fail to match.
/// See ``isFuzzyMatch(_:_:)`` for thresholds.
///
/// ## Compound Word Detection
/// When the speech recognizer concatenates adjacent words into a single
/// token (e.g., `"strongerfocus"` instead of `"stronger focus"`), the
/// matcher detects this by checking if the recognized word equals the
/// concatenation of consecutive expected words at the current pointer.
/// Up to 3 consecutive expected words are tried. This prevents the
/// highlight from freezing when the user speaks fluidly.
/// See ``tryCompoundMatch(_:expectedWords:startIndex:maxCompoundWords:)``.
///
/// ## Substring Split Detection
/// When the on-device recognizer revises a partial and glues a
/// **previously-matched** word onto the **current** expected word
/// (e.g., `"strongerfocus"` when the pointer is at `"focus"` because
/// `"stronger"` was already matched), the compound matcher fails because
/// it only tries forward concatenation. The substring split detector
/// checks if the current expected word is a suffix of the recognized word,
/// then verifies the remaining prefix matches the previous expected word.
/// See ``trySubstringSplit(_:expectedWords:currentIndex:)``.
///
/// ## Continuation Matching
/// When the on-device recognizer revises a transcription mid-sentence
/// (e.g., after a stumble), the revised text may start from a later point
/// in the affirmation. The ``matchSequentially(expectedWords:recognizedWords:fromIndex:)``
/// overload enables matching from a given offset, allowing a "continuation pass"
/// that detects forward progress even after recognizer revisions.
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

        let matchedCount = runMatchingLoop(
            expectedWords: expectedWords,
            recognizedWords: recognizedWords,
            startIndex: 0
        )

        return MatchResult(
            matchedCount: matchedCount,
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

        let matchedCount = runMatchingLoop(
            expectedWords: expectedWords,
            recognizedWords: recognizedWords,
            startIndex: 0
        )

        return MatchResult(
            matchedCount: matchedCount,
            totalExpectedWords: expectedWords.count
        )
    }

    /// Matches pre-normalized recognized words against pre-normalized expected words.
    ///
    /// Use this overload when both arrays are already normalized — e.g., in the
    /// dual-pass strategy where recognized text is normalized once and reused
    /// for both the primary pass (fromIndex 0) and the continuation pass.
    ///
    /// - Parameters:
    ///   - expectedWords: Pre-normalized expected word array (from ``normalizeText(_:)``)
    ///   - recognizedWords: Pre-normalized recognized word array (from ``normalizeText(_:)``)
    ///   - fromIndex: The expected word index to start matching from (default 0)
    /// - Returns: Match result with `matchedCount` relative to the full expected array
    static func matchSequentially(
        expectedWords: [String],
        recognizedWords: [String],
        fromIndex: Int = 0
    ) -> MatchResult {
        guard !expectedWords.isEmpty else {
            return MatchResult(matchedCount: 0, totalExpectedWords: 0)
        }

        guard fromIndex < expectedWords.count else {
            return MatchResult(matchedCount: fromIndex, totalExpectedWords: expectedWords.count)
        }

        guard !recognizedWords.isEmpty else {
            return MatchResult(matchedCount: fromIndex, totalExpectedWords: expectedWords.count)
        }

        let matchedCount = runMatchingLoop(
            expectedWords: expectedWords,
            recognizedWords: recognizedWords,
            startIndex: fromIndex
        )

        return MatchResult(
            matchedCount: matchedCount,
            totalExpectedWords: expectedWords.count
        )
    }

    /// Matches recognized text against expected words starting from a given offset.
    ///
    /// Used when the on-device speech recognizer revises its transcription
    /// mid-sentence. After a stumble, the revised text may begin from a later
    /// point in the affirmation (e.g., `"because love covers..."` instead of
    /// `"Above all love each other deeply because love covers..."`).
    /// Starting from `fromIndex` lets the matcher detect forward progress
    /// even when the transcript was revised and no longer matches from index 0.
    ///
    /// - Parameters:
    ///   - expectedWords: Pre-normalized expected word array (from ``normalizeText(_:)``)
    ///   - recognized: The partial or final transcription from speech recognition
    ///   - fromIndex: The expected word index to start matching from
    /// - Returns: Match result with `matchedCount` relative to the full expected array
    static func matchSequentially(
        expectedWords: [String],
        recognized: String,
        fromIndex: Int
    ) -> MatchResult {
        guard fromIndex < expectedWords.count else {
            return MatchResult(matchedCount: fromIndex, totalExpectedWords: expectedWords.count)
        }

        let recognizedWords = normalizeText(recognized)

        guard !recognizedWords.isEmpty else {
            return MatchResult(matchedCount: fromIndex, totalExpectedWords: expectedWords.count)
        }

        let matchedCount = runMatchingLoop(
            expectedWords: expectedWords,
            recognizedWords: recognizedWords,
            startIndex: fromIndex
        )

        return MatchResult(
            matchedCount: matchedCount,
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

    // MARK: - Core Matching Loop

    /// Runs the sequential matching loop over pre-normalized word arrays.
    ///
    /// This is the single implementation of the matching algorithm, called by
    /// all public `matchSequentially` overloads. Walks the recognized words
    /// and advances the expected pointer on exact, fuzzy, or compound matches.
    ///
    /// - Parameters:
    ///   - expectedWords: Pre-normalized expected word array
    ///   - recognizedWords: Pre-normalized recognized word array
    ///   - startIndex: The expected word index to start matching from
    /// - Returns: Final pointer position (number of words matched from the start)
    private static func runMatchingLoop(
        expectedWords: [String],
        recognizedWords: [String],
        startIndex: Int
    ) -> Int {
        var expectedIndex = startIndex

        for recognizedWord in recognizedWords {
            guard expectedIndex < expectedWords.count else { break }

            if recognizedWord == expectedWords[expectedIndex]
                || isFuzzyMatch(recognizedWord, expectedWords[expectedIndex]) {
                expectedIndex += 1
            } else if let consumed = tryCompoundMatch(
                recognizedWord,
                expectedWords: expectedWords,
                startIndex: expectedIndex
            ) {
                expectedIndex += consumed
            } else if trySubstringSplit(
                recognizedWord,
                expectedWords: expectedWords,
                currentIndex: expectedIndex
            ) {
                expectedIndex += 1
            }
        }

        return expectedIndex
    }

    // MARK: - Fuzzy Matching

    /// Determines if two words are a "close enough" match for highlighting.
    ///
    /// Uses generous thresholds because the feature's purpose is **encouragement**,
    /// not accuracy testing. Users with accents or mispronunciations should still
    /// see their words highlight. Only obviously wrong words should fail.
    ///
    /// The sequential constraint (match must occur at the current pointer position)
    /// dramatically reduces false positive risk, allowing generous thresholds:
    ///
    /// - 1 character: **exact match only** (`"i"` vs `"a"` are too different)
    /// - 2 characters: edit distance ≤ 1 (`"am"` ≈ `"um"`)
    /// - 3–4 characters: edit distance ≤ 2 (`"and"` ≈ `"ant"`, `"love"` ≈ `"luv"`)
    /// - 5–7 characters: edit distance ≤ 2 (`"strong"` ≈ `"stong"`)
    /// - 8+ characters: edit distance ≤ 3 (`"confident"` ≈ `"confidant"`)
    ///
    /// Additionally, words sharing a common prefix of ≥ 60% length are accepted
    /// (catches truncated or extended recognitions).
    ///
    /// ## Performance
    /// O(n×m) where n, m are word lengths. Typical words are 4–12 chars →
    /// 16–144 ops per comparison. Negligible at ~33ms update intervals.
    ///
    /// - Parameters:
    ///   - word1: First normalized word
    ///   - word2: Second normalized word
    /// - Returns: `true` if the words are close enough for highlighting
    private static func isFuzzyMatch(_ word1: String, _ word2: String) -> Bool {
        let len1 = word1.count
        let len2 = word2.count
        let minLen = min(len1, len2)
        let maxLen = max(len1, len2)

        // Single-character words: exact only (caller handles equality)
        guard minLen >= 2 else { return false }

        // --- Prefix match: ≥ 60% shared prefix accepts the match ---
        let prefixThreshold = max(3, Int(ceil(Double(maxLen) * 0.6)))
        if minLen >= 3 {
            let commonPrefix = zip(word1, word2).prefix(while: { $0 == $1 }).count
            if commonPrefix >= prefixThreshold {
                return true
            }
        }

        // --- Edit distance with lenient thresholds ---
        let maxAllowed: Int
        switch minLen {
        case 2:       maxAllowed = 1
        case 3...4:   maxAllowed = 2
        case 5...7:   maxAllowed = 2
        default:      maxAllowed = 3  // 8+
        }

        // Quick reject: length difference alone exceeds threshold
        guard abs(len1 - len2) <= maxAllowed else { return false }

        return editDistance(Array(word1), Array(word2), threshold: maxAllowed) <= maxAllowed
    }

    // MARK: - Compound Word Matching

    /// Checks if a recognized word is a concatenation of consecutive expected words.
    ///
    /// When the on-device `SFSpeechRecognizer` returns words without spaces
    /// (e.g., `"strongerfocus"` for `"stronger focus"`), this method detects the
    /// concatenation by building progressively longer expected-word combinations
    /// starting at the current pointer and comparing against the recognized word.
    ///
    /// Only invoked when normal matching fails — not on every word.
    ///
    /// - Parameters:
    ///   - recognizedWord: The normalized recognized word that failed normal matching
    ///   - expectedWords: The full array of normalized expected words
    ///   - startIndex: Current pointer position in expected words
    ///   - maxCompoundWords: Maximum expected words to try concatenating (default 3)
    /// - Returns: Number of expected words consumed if matched, or `nil` if no match
    private static func tryCompoundMatch(
        _ recognizedWord: String,
        expectedWords: [String],
        startIndex: Int,
        maxCompoundWords: Int = 3
    ) -> Int? {
        var concatenation = expectedWords[startIndex]

        for k in 2...maxCompoundWords {
            let nextIndex = startIndex + k - 1
            guard nextIndex < expectedWords.count else { break }

            concatenation += expectedWords[nextIndex]

            if recognizedWord == concatenation
                || isFuzzyMatch(recognizedWord, concatenation) {
                return k
            }
        }

        return nil
    }

    // MARK: - Substring Split Detection

    /// Detects when the recognizer glues a previously-matched word onto the current expected word.
    ///
    /// After a partial transcription revision, the on-device `SFSpeechRecognizer` may
    /// concatenate an already-matched word with the next expected word into a single token
    /// (e.g., `"strongerfocus"` when the pointer is at `"focus"` and `"stronger"` was
    /// already matched in a prior partial). The compound matcher cannot handle this because
    /// it only tries **forward** concatenation from the current pointer.
    ///
    /// This method checks if the current expected word appears as a **suffix** of the
    /// recognized word, then verifies the remaining prefix matches the **previous** expected
    /// word (which the high-water mark already counted).
    ///
    /// Only invoked when exact, fuzzy, and compound matching all fail — not on every word.
    ///
    /// ## Example
    /// ```
    /// expectedWords = ["stronger", "focus"], pointer at index 1 ("focus")
    /// recognizedWord = "strongerfocus"
    ///
    /// 1. "focus" is a suffix of "strongerfocus" ✓
    /// 2. Remainder prefix = "stronger"
    /// 3. Previous word expectedWords[0] = "stronger" → exact match ✓
    /// 4. Return true → pointer advances by 1
    /// ```
    ///
    /// - Parameters:
    ///   - recognizedWord: The normalized recognized word that failed all other matching
    ///   - expectedWords: The full array of normalized expected words
    ///   - currentIndex: Current pointer position in expected words
    /// - Returns: `true` if the current expected word was found as a suffix with a valid
    ///   backward-verified prefix, `false` otherwise
    private static func trySubstringSplit(
        _ recognizedWord: String,
        expectedWords: [String],
        currentIndex: Int
    ) -> Bool {
        // Need a previous word to verify the prefix against
        guard currentIndex > 0 else { return false }

        let expected = expectedWords[currentIndex]

        // Require ≥ 3 chars to avoid false positives from short substrings
        // (e.g., "i" matching inside "mind", "a" inside "capable")
        guard expected.count >= 3 else { return false }

        // The recognized word must be longer than the expected word
        // (it contains the expected word + a prefix from the previous word)
        guard recognizedWord.count > expected.count else { return false }

        // Check if the expected word appears as a suffix of the recognized word
        guard recognizedWord.hasSuffix(expected) else { return false }

        // Extract the prefix (the portion before the expected word)
        let prefixEnd = recognizedWord.index(
            recognizedWord.endIndex,
            offsetBy: -expected.count
        )
        let remainder = String(recognizedWord[recognizedWord.startIndex..<prefixEnd])

        // Verify: the prefix must match the previous expected word
        let previousWord = expectedWords[currentIndex - 1]

        return remainder == previousWord || isFuzzyMatch(remainder, previousWord)
    }

    // MARK: - Edit Distance

    /// Computes Levenshtein edit distance with O(min(n,m)) space and early termination.
    ///
    /// Uses the standard dynamic programming algorithm with a single-row
    /// optimization. Swaps the shorter string into the row dimension to
    /// minimize memory allocation. Terminates early when the minimum value
    /// in a row exceeds the given threshold (all possible alignments are
    /// already worse than the caller's tolerance).
    ///
    /// - Parameters:
    ///   - s1: First character array
    ///   - s2: Second character array
    ///   - threshold: Maximum useful distance. If the true distance exceeds
    ///     this value, returns `threshold + 1` without completing the matrix.
    /// - Returns: Minimum edit distance, or `threshold + 1` if over threshold
    private static func editDistance(
        _ s1: [Character],
        _ s2: [Character],
        threshold: Int
    ) -> Int {
        let m = s1.count
        let n = s2.count
        if m == 0 { return n }
        if n == 0 { return m }

        // Length difference alone exceeds threshold
        if abs(m - n) > threshold { return threshold + 1 }

        // Use shorter array for the row to minimize space
        let (shorter, longer) = m <= n ? (s1, s2) : (s2, s1)
        let shortLen = shorter.count
        let longLen = longer.count

        var prev = Array(0...shortLen)
        var curr = [Int](repeating: 0, count: shortLen + 1)

        for i in 1...longLen {
            curr[0] = i
            var rowMin = curr[0]
            for j in 1...shortLen {
                let cost = longer[i - 1] == shorter[j - 1] ? 0 : 1
                curr[j] = min(
                    curr[j - 1] + 1,      // insertion
                    prev[j] + 1,          // deletion
                    prev[j - 1] + cost    // substitution
                )
                rowMin = min(rowMin, curr[j])
            }
            // Early termination: if every cell in this row exceeds the
            // threshold, no subsequent row can produce a value ≤ threshold.
            if rowMin > threshold { return threshold + 1 }
            swap(&prev, &curr)
        }
        return prev[shortLen]
    }
}
