//
//  CustomPrompt.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import Foundation
import SwiftData

// MARK: - CustomPrompt

/// A user-created prompt for generating custom affirmations.
///
/// Users can create prompts like "Affirmations for overcoming fear of public speaking"
/// and the app generates personalized affirmations based on that prompt.
@Model
final class CustomPrompt {
    
    // MARK: - Properties
    
    /// Unique identifier for the prompt
    @Attribute(.unique)
    var id: UUID
    
    /// The user's prompt text (e.g., "Affirmations for overcoming imposter syndrome")
    var promptText: String
    
    /// Date when the prompt was created
    var createdAt: Date
    
    /// Date when the prompt was last used in a session
    var lastUsedAt: Date?
    
    /// Total number of times this prompt has been used
    var useCount: Int
    
    /// Whether affirmations are currently being generated
    var isGenerating: Bool
    
    /// Error message if generation failed
    var generationError: String?
    
    /// Firebase document ID for syncing
    var firebaseDocumentId: String?
    
    // MARK: - Initialization
    
    /// Creates a new custom prompt
    init(
        id: UUID = UUID(),
        promptText: String,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil,
        useCount: Int = 0,
        isGenerating: Bool = false,
        generationError: String? = nil,
        firebaseDocumentId: String? = nil
    ) {
        self.id = id
        self.promptText = promptText
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
        self.isGenerating = isGenerating
        self.generationError = generationError
        self.firebaseDocumentId = firebaseDocumentId
    }
}

// MARK: - Computed Properties

extension CustomPrompt {
    
    /// Whether there was an error generating affirmations
    var hasError: Bool {
        generationError != nil
    }
    
    /// Preview/truncated version of the prompt text
    var previewText: String {
        if promptText.count <= 50 {
            return promptText
        }
        return String(promptText.prefix(47)) + "..."
    }
    
    /// Formatted date for display
    var formattedCreatedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: createdAt)
    }
    
    /// Formatted last used date for display
    var formattedLastUsedDate: String? {
        guard let lastUsedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastUsedAt, relativeTo: Date())
    }
    
    // Note: Affirmation-related computed properties (unseenCount, totalAffirmationCount, etc.)
    // will be implemented in the ViewModel layer using queries with sourcePromptId
}

// MARK: - Methods

extension CustomPrompt {
    
    /// Marks the prompt as used and increments use count
    func markAsUsed() {
        lastUsedAt = Date()
        useCount += 1
    }
    
    /// Clears the generation error
    func clearError() {
        generationError = nil
    }
    
    /// Sets the generation state
    func setGenerating(_ generating: Bool) {
        isGenerating = generating
        if generating {
            generationError = nil
        }
    }
    
    /// Sets a generation error
    func setError(_ error: String) {
        isGenerating = false
        generationError = error
    }
}

// MARK: - Sample Data

extension CustomPrompt {
    
    /// Sample prompt for previews
    static var sample: CustomPrompt {
        let prompt = CustomPrompt(
            promptText: "Affirmations for overcoming imposter syndrome at work",
            useCount: 5
        )
        return prompt
    }
    
    /// Collection of sample prompts for previews
    static var samples: [CustomPrompt] {
        [
            CustomPrompt(
                promptText: "Affirmations for overcoming imposter syndrome at work",
                useCount: 5
            ),
            CustomPrompt(
                promptText: "Building confidence for public speaking",
                useCount: 3
            ),
            CustomPrompt(
                promptText: "Healing from past relationships",
                useCount: 1
            )
        ]
    }
}
