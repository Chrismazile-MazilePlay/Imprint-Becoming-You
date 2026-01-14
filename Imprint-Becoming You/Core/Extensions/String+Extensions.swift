//
//  String+Extensions.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/12/26.
//

import Foundation

// MARK: - String Extensions

extension String {
    
    // MARK: - Citation Stripping
    
    /// Returns the string with any trailing parenthetical citation removed.
    ///
    /// Used primarily for speech recognition to avoid requiring users to speak
    /// Bible verse references like "(Philippians 4:13)".
    ///
    /// Handles multiple parenthesis styles:
    /// - Standard: `(citation)`
    /// - Fullwidth: `（citation）`
    /// - Brackets: `[citation]` or `【citation】`
    ///
    /// ## Examples
    /// ```swift
    /// "I can do all things... (Philippians 4:13)".strippingTrailingCitation
    /// // Returns: "I can do all things..."
    ///
    /// "Be still and know... (Psalm 46:10)".strippingTrailingCitation
    /// // Returns: "Be still and know..."
    ///
    /// "No citation here".strippingTrailingCitation
    /// // Returns: "No citation here"
    ///
    /// "Has (inner) parens but no trailing".strippingTrailingCitation
    /// // Returns: "Has (inner) parens but no trailing"
    /// ```
    ///
    /// - Returns: The string with trailing parenthetical content removed,
    ///            or the original string if no trailing citation exists.
    var strippingTrailingCitation: String {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle different parenthesis styles (Unicode variants)
        let closingParens = [")", "）", "】", "]"]  // Standard, fullwidth, bracket variants
        let openingParens = ["(", "（", "【", "["]
        
        // Check if string ends with any closing parenthesis
        var parenIndex: Int? = nil
        for (index, closer) in closingParens.enumerated() {
            if trimmed.hasSuffix(closer) {
                parenIndex = index
                break
            }
        }
        
        guard let matchIndex = parenIndex else {
            return self
        }
        
        let closer = closingParens[matchIndex]
        let opener = openingParens[matchIndex]
        
        // Find the matching opening parenthesis from the end
        var depth = 0
        var openParenPosition: String.Index?
        
        for index in trimmed.indices.reversed() {
            let char = String(trimmed[index])
            
            if char == closer {
                depth += 1
            } else if char == opener {
                depth -= 1
                if depth == 0 {
                    openParenPosition = index
                    break
                }
            }
        }
        
        // If we found a matching open paren, strip from there to end
        guard let startIndex = openParenPosition else {
            return self
        }
        
        // Get the text before the citation and trim trailing whitespace
        let result = String(trimmed[..<startIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Return original if stripping would leave empty string
        guard !result.isEmpty else {
            return self
        }
        
        return result
    }
    
    // MARK: - Text Normalization
    
    /// Returns a normalized version of the string for text comparison.
    ///
    /// Useful for comparing user speech transcription against expected text
    /// where punctuation and case differences shouldn't matter.
    ///
    /// - Returns: Lowercase string with punctuation removed
    var normalizedForComparison: String {
        self.lowercased()
            .components(separatedBy: CharacterSet.punctuationCharacters)
            .joined()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
