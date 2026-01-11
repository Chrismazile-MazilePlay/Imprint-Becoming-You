//
//  SimpleWordMatcher.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/10/26.
//

import Foundation
import os.log

// MARK: - Logger

private let matcherLog = Logger(subsystem: "com.imprint.audio", category: "WordMatcher")

// MARK: - SimpleWordMatcher

/// Matches transcribed speech against expected affirmation text.
///
/// Uses simple normalized word comparison instead of complex fuzzy algorithms.
/// The heavy lifting is done by Apple's speech recognition with `contextualStrings`.
///
/// ## Usage
/// ```swift
/// let matcher = SimpleWordMatcher(expectedText: "I am confident and capable")
/// matcher.updateTranscription("I am confident")
/// print(matcher.progress) // 0.5
/// print(matcher.matchedWords) // ["i", "am", "confident"]
/// ```
@MainActor
final class SimpleWordMatcher {
    
    // MARK: - Properties
    
    /// The expected affirmation text (normalized)
    let expectedText: String
    
    /// Expected words (normalized, ordered)
    let expectedWords: [String]
    
    /// Set of expected words for O(1) lookup
    private let expectedWordSet: Set<String>
    
    /// Currently matched words
    private(set) var matchedWords: Set<String> = []
    
    /// Current transcription
    private(set) var currentTranscription: String = ""
    
    /// Progress (0.0 to 1.0)
    var progress: Float {
        guard !expectedWords.isEmpty else { return 1.0 }
        return Float(matchedWords.count) / Float(expectedWords.count)
    }
    
    /// Whether all words have been matched
    var isComplete: Bool {
        matchedWords.count >= expectedWords.count
    }
    
    /// Words that haven't been matched yet
    var unmatchedWords: [String] {
        expectedWords.filter { !matchedWords.contains($0) }
    }
    
    /// Last update timestamp
    private var lastUpdateTime: Date = Date()
    
    /// Number of new words matched in last update
    private(set) var newMatchesInLastUpdate: Int = 0
    
    // MARK: - Initialization
    
    /// Creates a matcher for the given expected text
    /// - Parameter expectedText: The affirmation text to match against
    init(expectedText: String) {
        self.expectedText = expectedText
        self.expectedWords = Self.normalizeAndTokenize(expectedText)
        self.expectedWordSet = Set(expectedWords)
        
        matcherLog.info("📋 SimpleWordMatcher initialized")
        matcherLog.info("   Expected: \"\(expectedText)\"")
        matcherLog.info("   Words: \(self.expectedWords.joined(separator: ", "))")
    }
    
    // MARK: - Public Methods
    
    /// Updates with new transcription from speech recognition
    /// - Parameter transcription: The transcribed text
    /// - Returns: Number of new words matched
    @discardableResult
    func updateTranscription(_ transcription: String) -> Int {
        currentTranscription = transcription
        lastUpdateTime = Date()
        
        // Normalize and tokenize transcription
        let transcribedWords = Self.normalizeAndTokenize(transcription)
        
        matcherLog.debug("📝 Transcription update: \"\(transcription.prefix(50))...\"")
        matcherLog.debug("   Transcribed words: \(transcribedWords.joined(separator: ", "))")
        
        // Find new matches
        let previousMatchCount = matchedWords.count
        
        for word in transcribedWords {
            if expectedWordSet.contains(word) && !matchedWords.contains(word) {
                matchedWords.insert(word)
                matcherLog.info("✅ Matched: \"\(word)\"")
            }
        }
        
        newMatchesInLastUpdate = matchedWords.count - previousMatchCount
        
        if newMatchesInLastUpdate > 0 {
            matcherLog.info("📊 Progress: \(Int(self.progress * 100))% (\(self.matchedWords.count)/\(self.expectedWords.count) words)")
        }
        
        return newMatchesInLastUpdate
    }
    
    /// Resets the matcher for retry
    func reset() {
        matchedWords.removeAll()
        currentTranscription = ""
        newMatchesInLastUpdate = 0
        lastUpdateTime = Date()
        
        matcherLog.info("🔄 SimpleWordMatcher reset")
    }
    
    /// Returns contextual phrases for speech recognition
    /// These should be passed to `SFSpeechAudioBufferRecognitionRequest.contextualStrings`
    var contextualPhrases: [String] {
        // Return the full phrase plus individual words
        var phrases = [expectedText]
        phrases.append(contentsOf: expectedWords)
        return phrases
    }
    
    // MARK: - Text Accuracy
    
    /// Calculates text accuracy between transcription and expected
    /// - Returns: Accuracy score (0.0 to 1.0)
    func calculateAccuracy() -> Float {
        guard !expectedWords.isEmpty else { return 1.0 }
        
        let transcribedWords = Self.normalizeAndTokenize(currentTranscription)
        
        // Calculate word-level accuracy
        var matches = 0
        var transcribedSet = Set(transcribedWords)
        
        for word in expectedWords {
            if transcribedSet.contains(word) {
                matches += 1
                transcribedSet.remove(word) // Don't double-count
            }
        }
        
        let accuracy = Float(matches) / Float(expectedWords.count)
        
        matcherLog.info("📊 Text accuracy: \(Int(accuracy * 100))%")
        
        return accuracy
    }
    
    // MARK: - Static Helpers
    
    /// Normalizes and tokenizes text into words
    /// - Parameter text: Input text
    /// - Returns: Array of normalized words
    static func normalizeAndTokenize(_ text: String) -> [String] {
        // Expand common contractions
        let expanded = expandContractions(text)
        
        // Remove punctuation and convert to lowercase, then split into words
        let words = expanded
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        
        return words
    }
    
    /// Expands common English contractions
    private static func expandContractions(_ text: String) -> String {
        var result = text.lowercased()
        
        // Common contractions map
        let contractions: [String: String] = [
            // Pronoun contractions
            "i'm": "i am",
            "i've": "i have",
            "i'll": "i will",
            "i'd": "i would",
            "you're": "you are",
            "you've": "you have",
            "you'll": "you will",
            "you'd": "you would",
            "he's": "he is",
            "he'll": "he will",
            "he'd": "he would",
            "she's": "she is",
            "she'll": "she will",
            "she'd": "she would",
            "it's": "it is",
            "it'll": "it will",
            "we're": "we are",
            "we've": "we have",
            "we'll": "we will",
            "we'd": "we would",
            "they're": "they are",
            "they've": "they have",
            "they'll": "they will",
            "they'd": "they would",
            "that's": "that is",
            "that'll": "that will",
            "that'd": "that would",
            "who's": "who is",
            "who'll": "who will",
            "who'd": "who would",
            "what's": "what is",
            "what'll": "what will",
            "what'd": "what would",
            "where's": "where is",
            "where'll": "where will",
            "where'd": "where would",
            "when's": "when is",
            "why's": "why is",
            "how's": "how is",
            "here's": "here is",
            "there's": "there is",
            "there'll": "there will",
            "there'd": "there would",
            
            // Negative contractions
            "isn't": "is not",
            "aren't": "are not",
            "wasn't": "was not",
            "weren't": "were not",
            "haven't": "have not",
            "hasn't": "has not",
            "hadn't": "had not",
            "won't": "will not",
            "wouldn't": "would not",
            "don't": "do not",
            "doesn't": "does not",
            "didn't": "did not",
            "can't": "cannot",
            "couldn't": "could not",
            "shouldn't": "should not",
            "mightn't": "might not",
            "mustn't": "must not",
            "needn't": "need not",
            "shan't": "shall not",
            
            // Other common contractions
            "let's": "let us",
            "ain't": "is not",
            "y'all": "you all",
            "ma'am": "madam",
            "o'clock": "of the clock",
        ]
        
        // Apply contractions (with word boundaries)
        for (contraction, expansion) in contractions {
            // Match whole word only
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: contraction))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: expansion)
            }
        }
        
        return result
    }
}

// MARK: - WordMatchResult

/// Result of word matching for a single update
struct WordMatchResult: Sendable {
    /// Words that were newly matched in this update
    let newMatches: [String]
    
    /// Total matched words so far
    let totalMatched: Int
    
    /// Total expected words
    let totalExpected: Int
    
    /// Progress percentage (0-100)
    var progressPercent: Int {
        guard totalExpected > 0 else { return 100 }
        return Int(Float(totalMatched) / Float(totalExpected) * 100)
    }
    
    /// Whether matching is complete
    var isComplete: Bool {
        totalMatched >= totalExpected
    }
}

// MARK: - Debug Extensions

extension SimpleWordMatcher {
    
    /// Debug description
    var debugDescription: String {
        """
        SimpleWordMatcher Debug:
        - Expected: "\(expectedText)"
        - Expected words (\(expectedWords.count)): \(expectedWords.joined(separator: ", "))
        - Matched words (\(matchedWords.count)): \(matchedWords.sorted().joined(separator: ", "))
        - Unmatched words (\(unmatchedWords.count)): \(unmatchedWords.joined(separator: ", "))
        - Progress: \(Int(progress * 100))%
        - Current transcription: "\(currentTranscription)"
        - Last update: \(lastUpdateTime)
        """
    }
}
