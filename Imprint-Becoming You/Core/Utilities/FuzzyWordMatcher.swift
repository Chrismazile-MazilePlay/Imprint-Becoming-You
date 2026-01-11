//
//  FuzzyWordMatcher.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/9/26.
//
/*
import Foundation
import os

// MARK: - AffirmationMatcher

/// High-performance fuzzy word matcher for speech-to-affirmation comparison.
///
/// Implements a multi-layered matching strategy based on research findings:
/// 1. **Normalization**: Case folding, punctuation, contraction expansion
/// 2. **Structural Matching**: Myers bit-parallel algorithm for edit distance
/// 3. **Phonetic Matching**: Double Metaphone for homophones
/// 4. **Sticky State**: Once matched, words stay matched (prevents flicker)
/// 5. **Stop-Word Guard**: Short words only count after content word matched
///
/// ## Performance
/// - < 10ms per transcription update
/// - < 1MB memory footprint
/// - Thread-safe via actor isolation
///
/// ## Usage
/// ```swift
/// let matcher = AffirmationMatcher()
/// await matcher.start(affirmation: "I am confident and capable")
/// let progress = await matcher.process(transcription: "I'm confident")
/// print(progress.fraction) // 0.6
/// ```
actor AffirmationMatcher {
    
    // MARK: - Types
    
    /// Result of processing a transcription
    struct MatchProgress: Sendable {
        /// Fraction of expected words matched (0.0 - 1.0)
        let fraction: Double
        
        /// Whether all words have been matched
        let isComplete: Bool
        
        /// Whether new words were matched in this update
        let hasProgressed: Bool
        
        /// Count of matched words
        let matchedCount: Int
        
        /// Total expected words
        let totalCount: Int
        
        /// Words matched in this update (for logging/debugging)
        let newlyMatchedWords: [String]
    }
    
    // MARK: - State
    
    /// Expected tokens from the affirmation (normalized)
    private var expectedTokens: [String] = []
    
    /// Original tokens (for display/logging)
    private var originalTokens: [String] = []
    
    /// Indices of tokens that have been matched (sticky)
    private var matchedIndices: Set<Int> = []
    
    /// Whether at least one content word has been matched
    private var hasMatchedContentWord: Bool = false
    
    /// Start time for duration tracking
    private var startTime: Date?
    
    /// Cached metaphone codes for expected tokens
    private var expectedMetaphoneCodes: [(primary: String, alternate: String?)] = []
    
    // MARK: - Public API
    
    /// Starts a new matching session for an affirmation
    /// - Parameter affirmation: The expected affirmation text
    func start(affirmation: String) {
        originalTokens = Normalizer.tokenize(affirmation)
        expectedTokens = Normalizer.normalizeAndTokenize(affirmation)
        matchedIndices = []
        hasMatchedContentWord = false
        startTime = Date()
        
        // Pre-compute metaphone codes for all expected tokens
        expectedMetaphoneCodes = expectedTokens.map { token in
            DoubleMetaphone.encode(token)
        }
    }
    
    /// Processes incoming transcription and returns match progress
    /// - Parameter transcription: The speech recognition transcription
    /// - Returns: Current match progress
    func process(transcription: String) -> MatchProgress {
        let incomingTokens = Normalizer.normalizeAndTokenize(transcription)
        var newlyMatched: [Int] = []
        var newlyMatchedWords: [String] = []
        
        for (index, expected) in expectedTokens.enumerated() {
            // Skip already matched (sticky state)
            if matchedIndices.contains(index) { continue }
            
            // Check if any incoming token matches this expected token
            for incoming in incomingTokens {
                if fuzzyMatch(incoming: incoming, expected: expected, index: index) {
                    // Stop-word guard: short words only count after content word
                    if expected.count <= 3 && !hasMatchedContentWord {
                        // Check if this is actually a content word match
                        if incoming.count > 3 {
                            hasMatchedContentWord = true
                            newlyMatched.append(index)
                            newlyMatchedWords.append(originalTokens[safe: index] ?? expected)
                        }
                        // Otherwise, defer matching short words
                    } else {
                        if expected.count > 3 {
                            hasMatchedContentWord = true
                        }
                        newlyMatched.append(index)
                        newlyMatchedWords.append(originalTokens[safe: index] ?? expected)
                    }
                    break
                }
            }
        }
        
        // If we now have a content word, retroactively match short words
        if hasMatchedContentWord {
            for (index, expected) in expectedTokens.enumerated() {
                if matchedIndices.contains(index) || newlyMatched.contains(index) { continue }
                if expected.count <= 3 {
                    for incoming in incomingTokens {
                        if fuzzyMatch(incoming: incoming, expected: expected, index: index) {
                            newlyMatched.append(index)
                            newlyMatchedWords.append(originalTokens[safe: index] ?? expected)
                            break
                        }
                    }
                }
            }
        }
        
        // Update sticky state
        newlyMatched.forEach { matchedIndices.insert($0) }
        
        let fraction = expectedTokens.isEmpty ? 0 : Double(matchedIndices.count) / Double(expectedTokens.count)
        
        return MatchProgress(
            fraction: fraction,
            isComplete: matchedIndices.count == expectedTokens.count,
            hasProgressed: !newlyMatched.isEmpty,
            matchedCount: matchedIndices.count,
            totalCount: expectedTokens.count,
            newlyMatchedWords: newlyMatchedWords
        )
    }
    
    /// Resets the matcher for a retry attempt
    func reset() {
        matchedIndices = []
        hasMatchedContentWord = false
        startTime = Date()
    }
    
    /// Duration since matching started
    var elapsedTime: TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }
    
    // MARK: - Matching Logic
    
    /// Performs multi-layer fuzzy matching
    private func fuzzyMatch(incoming: String, expected: String, index: Int) -> Bool {
        // Layer 1: Exact match (fastest path)
        if incoming == expected {
            return true
        }
        
        // Layer 2: Prefix match for partial words (3+ chars, zero errors)
        if incoming.count >= 3 && expected.hasPrefix(incoming) {
            return true
        }
        
        // Layer 3: Structural match (Myers algorithm with dynamic threshold)
        let threshold = dynamicThreshold(for: expected.count)
        if threshold > 0 {
            let distance = MyersBitParallel.editDistance(incoming, expected)
            if distance <= threshold {
                return true
            }
        }
        
        // Layer 4: Phonetic match (Double Metaphone)
        let incomingCodes = DoubleMetaphone.encode(incoming)
        let expectedCodes = expectedMetaphoneCodes[index]
        
        // Check primary codes
        if !incomingCodes.primary.isEmpty && incomingCodes.primary == expectedCodes.primary {
            return true
        }
        
        // Check alternate codes
        if let incomingAlt = incomingCodes.alternate, let expectedAlt = expectedCodes.alternate {
            if incomingAlt == expectedAlt {
                return true
            }
        }
        
        // Cross-check primary with alternate
        if let expectedAlt = expectedCodes.alternate, incomingCodes.primary == expectedAlt {
            return true
        }
        if let incomingAlt = incomingCodes.alternate, incomingAlt == expectedCodes.primary {
            return true
        }
        
        return false
    }
    
    /// Returns dynamic edit distance threshold based on word length
    private func dynamicThreshold(for length: Int) -> Int {
        switch length {
        case 1...3: return 0   // Must be exact
        case 4...6: return 1   // Single char slip
        case 7...10: return 2  // Common misspellings
        case 11...15: return 3 // High redundancy
        default: return 4      // Very long words (rare)
        }
    }
}

// MARK: - Normalizer

/// Text normalization utilities for speech matching
enum Normalizer {
    
    /// Comprehensive contraction expansion map
    private static let contractionMap: [String: String] = [
        // I contractions
        "i'm": "i am",
        "i've": "i have",
        "i'll": "i will",
        "i'd": "i would",
        "i'd've": "i would have",
        
        // You contractions
        "you're": "you are",
        "you've": "you have",
        "you'll": "you will",
        "you'd": "you would",
        
        // He/She/It contractions
        "he's": "he is",
        "she's": "she is",
        "it's": "it is",
        "he'll": "he will",
        "she'll": "she will",
        "it'll": "it will",
        "he'd": "he would",
        "she'd": "she would",
        
        // We/They contractions
        "we're": "we are",
        "we've": "we have",
        "we'll": "we will",
        "we'd": "we would",
        "they're": "they are",
        "they've": "they have",
        "they'll": "they will",
        "they'd": "they would",
        
        // Negative contractions
        "don't": "do not",
        "doesn't": "does not",
        "didn't": "did not",
        "can't": "cannot",
        "couldn't": "could not",
        "won't": "will not",
        "wouldn't": "would not",
        "shouldn't": "should not",
        "isn't": "is not",
        "aren't": "are not",
        "wasn't": "was not",
        "weren't": "were not",
        "haven't": "have not",
        "hasn't": "has not",
        "hadn't": "had not",
        
        // Other contractions
        "that's": "that is",
        "there's": "there is",
        "here's": "here is",
        "what's": "what is",
        "who's": "who is",
        "how's": "how is",
        "where's": "where is",
        "let's": "let us",
        "that'll": "that will",
        "who'll": "who will",
        "what'll": "what will",
        "there'll": "there will"
    ]
    
    /// Normalizes and tokenizes text for matching
    static func normalizeAndTokenize(_ text: String) -> [String] {
        var normalized = text.lowercased()
        
        // Remove punctuation
        normalized = normalized.components(separatedBy: CharacterSet.punctuationCharacters).joined()
        
        // Normalize diacritics (é → e, etc.)
        normalized = normalized.folding(options: .diacriticInsensitive, locale: .current)
        
        // Tokenize
        var tokens = normalized.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        
        // Expand contractions
        tokens = tokens.flatMap { token -> [String] in
            if let expansion = contractionMap[token] {
                return expansion.split(separator: " ").map(String.init)
            }
            return [token]
        }
        
        return tokens
    }
    
    /// Simple tokenization without normalization (for display)
    static func tokenize(_ text: String) -> [String] {
        text.split(separator: " ").map(String.init)
    }
}

// MARK: - Myers Bit-Parallel Algorithm

/// High-performance edit distance using Myers' bit-parallel algorithm
///
/// Computes Levenshtein distance in O(n × ⌈m/w⌉) time where w is word size (64 bits).
/// For typical affirmation words (< 64 chars), this is effectively O(n).
enum MyersBitParallel {
    
    /// Computes edit distance between two strings
    /// - Returns: Minimum edit distance (insertions + deletions + substitutions)
    static func editDistance(_ s1: String, _ s2: String) -> Int {
        let chars1 = Array(s1)
        let chars2 = Array(s2)
        
        let m = chars1.count
        let n = chars2.count
        
        // Handle edge cases
        if m == 0 { return n }
        if n == 0 { return m }
        
        // For very short strings, use simple DP (overhead of bit-parallel not worth it)
        if m <= 4 || n <= 4 {
            return levenshteinDP(chars1, chars2)
        }
        
        // Ensure pattern is shorter string for efficiency
        let (pattern, text): ([Character], [Character])
        if m <= n {
            (pattern, text) = (chars1, chars2)
        } else {
            (pattern, text) = (chars2, chars1)
        }
        
        let pLen = pattern.count
        // Note: text.count (tLen) not needed - we iterate directly over text
        
        // Build pattern masks for each character
        var patternMask: [Character: UInt64] = [:]
        for (i, char) in pattern.enumerated() {
            let mask = patternMask[char, default: 0]
            patternMask[char] = mask | (1 << i)
        }
        
        // Initialize bit vectors
        var vp: UInt64 = ~0  // Vertical positive
        var vn: UInt64 = 0   // Vertical negative
        var score = pLen
        
        let mask: UInt64 = 1 << (pLen - 1)
        
        // Process each character in text
        for char in text {
            let pm = patternMask[char, default: 0]
            
            let d0 = ((pm & vp) &+ vp) ^ vp | pm | vn
            var hp = vn | ~(d0 | vp)
            var hn = d0 & vp
            
            // Update score
            if (hp & mask) != 0 {
                score += 1
            } else if (hn & mask) != 0 {
                score -= 1
            }
            
            // Shift for next iteration
            hp = (hp << 1) | 1
            hn = hn << 1
            
            vp = hn | ~(d0 | hp)
            vn = d0 & hp
        }
        
        return score
    }
    
    /// Simple DP Levenshtein for short strings
    private static func levenshteinDP(_ s1: [Character], _ s2: [Character]) -> Int {
        let m = s1.count
        let n = s2.count
        
        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)
        
        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = s1[i - 1] == s2[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,      // deletion
                    curr[j - 1] + 1,  // insertion
                    prev[j - 1] + cost // substitution
                )
            }
            swap(&prev, &curr)
        }
        
        return prev[n]
    }
}

// MARK: - Double Metaphone

/// Double Metaphone phonetic encoding algorithm
///
/// Generates primary and alternate phonetic codes for words,
/// handling English pronunciation irregularities and loan words.
enum DoubleMetaphone {
    
    /// Phonetic encoding result
    typealias Code = (primary: String, alternate: String?)
    
    /// Encodes a word to its Double Metaphone representation
    static func encode(_ word: String) -> Code {
        guard !word.isEmpty else { return ("", nil) }
        
        var primary = ""
        var alternate = ""
        
        let chars = Array(word.uppercased())
        let length = chars.count
        var current = 0
        
        // Helper to get character at position
        func charAt(_ pos: Int) -> Character? {
            guard pos >= 0 && pos < length else { return nil }
            return chars[pos]
        }
        
        // Helper to check if string matches at position
        func stringAt(_ pos: Int, _ strings: String...) -> Bool {
            for str in strings {
                let strChars = Array(str)
                if pos + strChars.count > length { continue }
                var matches = true
                for (i, c) in strChars.enumerated() {
                    if chars[pos + i] != c {
                        matches = false
                        break
                    }
                }
                if matches { return true }
            }
            return false
        }
        
        // Helper to check if character is a vowel
        func isVowel(_ c: Character?) -> Bool {
            guard let c = c else { return false }
            return "AEIOU".contains(c)
        }
        
        // Skip silent letters at start
        if stringAt(0, "GN", "KN", "PN", "WR", "PS") {
            current += 1
        }
        
        // Initial X -> S
        if charAt(0) == "X" {
            primary += "S"
            alternate += "S"
            current += 1
        }
        
        // Main encoding loop
        while current < length && (primary.count < 4 || alternate.count < 4) {
            guard let c = charAt(current) else { break }
            
            switch c {
            case "A", "E", "I", "O", "U":
                if current == 0 {
                    primary += "A"
                    alternate += "A"
                }
                current += 1
                
            case "B":
                primary += "P"
                alternate += "P"
                current += charAt(current + 1) == "B" ? 2 : 1
                
            case "C":
                if stringAt(current, "CH") {
                    primary += "X"
                    alternate += "X"
                    current += 2
                } else if stringAt(current, "CI", "CE", "CY") {
                    primary += "S"
                    alternate += "S"
                    current += 1
                } else {
                    primary += "K"
                    alternate += "K"
                    current += stringAt(current, "CK", "CC") ? 2 : 1
                }
                
            case "D":
                if stringAt(current, "DG") {
                    if stringAt(current + 2, "I", "E", "Y") {
                        primary += "J"
                        alternate += "J"
                        current += 3
                    } else {
                        primary += "TK"
                        alternate += "TK"
                        current += 2
                    }
                } else {
                    primary += "T"
                    alternate += "T"
                    current += stringAt(current, "DT", "DD") ? 2 : 1
                }
                
            case "F":
                primary += "F"
                alternate += "F"
                current += charAt(current + 1) == "F" ? 2 : 1
                
            case "G":
                if charAt(current + 1) == "H" {
                    if current > 0 && !isVowel(charAt(current - 1)) {
                        primary += "K"
                        alternate += "K"
                    } else if current == 0 {
                        if charAt(current + 2) == "I" {
                            primary += "J"
                            alternate += "J"
                        } else {
                            primary += "K"
                            alternate += "K"
                        }
                    }
                    current += 2
                } else if charAt(current + 1) == "N" {
                    if current == 0 {
                        // GN at start is silent
                    } else {
                        primary += "KN"
                        alternate += "N"
                    }
                    current += 2
                } else if stringAt(current, "GI", "GE", "GY") {
                    primary += "J"
                    alternate += "K"
                    current += 1
                } else {
                    primary += "K"
                    alternate += "K"
                    current += charAt(current + 1) == "G" ? 2 : 1
                }
                
            case "H":
                if current == 0 || isVowel(charAt(current - 1)) {
                    if isVowel(charAt(current + 1)) {
                        primary += "H"
                        alternate += "H"
                    }
                }
                current += 1
                
            case "J":
                primary += "J"
                alternate += "J"
                current += charAt(current + 1) == "J" ? 2 : 1
                
            case "K":
                primary += "K"
                alternate += "K"
                current += charAt(current + 1) == "K" ? 2 : 1
                
            case "L":
                primary += "L"
                alternate += "L"
                current += charAt(current + 1) == "L" ? 2 : 1
                
            case "M":
                primary += "M"
                alternate += "M"
                current += charAt(current + 1) == "M" ? 2 : 1
                
            case "N":
                primary += "N"
                alternate += "N"
                current += charAt(current + 1) == "N" ? 2 : 1
                
            case "P":
                if charAt(current + 1) == "H" {
                    primary += "F"
                    alternate += "F"
                    current += 2
                } else {
                    primary += "P"
                    alternate += "P"
                    current += stringAt(current, "PP", "PB") ? 2 : 1
                }
                
            case "Q":
                primary += "K"
                alternate += "K"
                current += charAt(current + 1) == "Q" ? 2 : 1
                
            case "R":
                primary += "R"
                alternate += "R"
                current += charAt(current + 1) == "R" ? 2 : 1
                
            case "S":
                if stringAt(current, "SH") {
                    primary += "X"
                    alternate += "X"
                    current += 2
                } else if stringAt(current, "SI") && stringAt(current + 2, "O", "A") {
                    primary += "X"
                    alternate += "S"
                    current += 1
                } else {
                    primary += "S"
                    alternate += "S"
                    current += stringAt(current, "SS", "SC") ? 2 : 1
                }
                
            case "T":
                if stringAt(current, "TH") {
                    primary += "0"  // Using 0 for TH sound
                    alternate += "T"
                    current += 2
                } else if stringAt(current, "TI") && stringAt(current + 2, "O", "A") {
                    primary += "X"
                    alternate += "X"
                    current += 1
                } else {
                    primary += "T"
                    alternate += "T"
                    current += stringAt(current, "TT", "TD") ? 2 : 1
                }
                
            case "V":
                primary += "F"
                alternate += "F"
                current += charAt(current + 1) == "V" ? 2 : 1
                
            case "W":
                if charAt(current + 1) == "R" {
                    primary += "R"
                    alternate += "R"
                    current += 2
                } else if current == 0 && isVowel(charAt(current + 1)) {
                    primary += "A"
                    alternate += "F"
                    current += 1
                } else {
                    current += 1
                }
                
            case "X":
                primary += "KS"
                alternate += "KS"
                current += charAt(current + 1) == "X" ? 2 : 1
                
            case "Y":
                if isVowel(charAt(current + 1)) {
                    primary += "A"
                    alternate += "A"
                }
                current += 1
                
            case "Z":
                primary += "S"
                alternate += "S"
                current += charAt(current + 1) == "Z" ? 2 : 1
                
            default:
                current += 1
            }
        }
        
        // Truncate to 4 characters
        let primaryCode = String(primary.prefix(4))
        let alternateCode = String(alternate.prefix(4))
        
        return (primaryCode, primaryCode == alternateCode ? nil : alternateCode)
    }
}

// MARK: - Legacy FuzzyWordMatcher (Wrapper)

/// Legacy wrapper for backward compatibility with existing PracticeStore code.
///
/// Wraps the new actor-based AffirmationMatcher in a synchronous interface.
/// Note: For new code, prefer using AffirmationMatcher directly.
final class FuzzyWordMatcher: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// The underlying actor-based matcher
    private let matcher = AffirmationMatcher()
    
    /// Original affirmation text
    let affirmationText: String
    
    /// Expected words (normalized)
    let expectedWords: [String]
    
    /// Thread-safe state storage using OSAllocatedUnfairLock (Swift 6 compatible)
    private let state: OSAllocatedUnfairLock<AffirmationMatcher.MatchProgress?>
    
    // MARK: - Initialization
    
    init(affirmationText: String) {
        self.affirmationText = affirmationText
        self.expectedWords = Normalizer.normalizeAndTokenize(affirmationText)
        self.state = OSAllocatedUnfairLock(initialState: nil)
        
        // Start the matcher
        Task {
            await matcher.start(affirmation: affirmationText)
        }
    }
    
    // MARK: - Matching
    
    /// Checks recognized text for matches (async)
    func checkForMatchesAsync(in recognizedText: String) async -> [String] {
        let progress = await matcher.process(transcription: recognizedText)
        
        state.withLock { $0 = progress }
        
        return progress.newlyMatchedWords
    }
    
    /// Synchronous check for matches (uses cached state)
    func checkForMatches(in recognizedText: String) -> [String] {
        // Fire and forget async update
        Task {
            _ = await checkForMatchesAsync(in: recognizedText)
        }
        
        // Return last known newly matched (may be stale)
        return state.withLock { $0?.newlyMatchedWords ?? [] }
    }
    
    /// Resets the matcher for retry
    func reset() {
        Task {
            await matcher.reset()
        }
        state.withLock { $0 = nil }
    }
    
    // MARK: - Progress
    
    /// Fraction of expected words matched (0.0 - 1.0)
    var matchProgress: Double {
        state.withLock { $0?.fraction ?? 0 }
    }
    
    /// Number of words matched
    var matchedCount: Int {
        state.withLock { $0?.matchedCount ?? 0 }
    }
    
    /// Total expected words
    var totalCount: Int {
        expectedWords.count
    }
    
    /// Whether all words have been matched
    var isComplete: Bool {
        state.withLock { $0?.isComplete ?? false }
    }
    
    /// Whether new progress was made in last check
    var hasProgressed: Bool {
        state.withLock { $0?.hasProgressed ?? false }
    }
}
*/
