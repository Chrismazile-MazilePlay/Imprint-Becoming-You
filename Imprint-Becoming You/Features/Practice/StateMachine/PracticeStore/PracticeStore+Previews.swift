//
//  PracticeStore+Previews.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/11/26.
//

import Foundation

// MARK: - Supporting Types

/// Types of user engagement to track for analytics and personalization.
enum EngagementType: Sendable {
    case view
    case speak
    case skip
    case share
}

/// Background state for the morphing gradient animation.
struct BackgroundState: Equatable {
    let currentCategory: GoalCategory?
    let previousCategory: GoalCategory?
    
    static let `default` = BackgroundState(currentCategory: .confidence, previousCategory: nil)
}

// MARK: - Preview Support

extension PracticeStore {
    
    /// Preview store using mock dependencies with sample affirmations.
    static var preview: PracticeStore {
        let store = PracticeStore(dependencies: .preview)
        store.setBrowseState(affirmations: Affirmation.samples)
        return store
    }
    
    /// Preview store in read-aloud playing state.
    static var previewReadAloud: PracticeStore {
        let store = PracticeStore(dependencies: .preview)
        store.setBrowseState(affirmations: Affirmation.samples)
        store.setFlow(.readAloud(.playing(progress: 0.5)))
        return store
    }
    
    /// Preview store in listening state with partial transcription.
    static var previewListening: PracticeStore {
        let store = PracticeStore(dependencies: .preview)
        store.setBrowseState(affirmations: Affirmation.samples)
        store.setFlow(.readAndSpeak(.listening(ListeningContext(
            elapsed: 1.5,
            audioLevel: 0.6,
            recognizedText: "I am confident...",
            matchedWordCount: 3,
            totalExpectedWords: 5
        ))))
        return store
    }
    
    /// Preview store showing a celebration.
    static var previewCelebrating: PracticeStore {
        let store = PracticeStore(dependencies: .preview)
        store.setBrowseState(affirmations: Affirmation.samples)
        store.setFlow(.readAndSpeak(.celebrating))
        return store
    }
    
    /// Preview store with mode selector expanded.
    static var previewModeSelector: PracticeStore {
        let store = PracticeStore(dependencies: .preview)
        store.setBrowseState(affirmations: Affirmation.samples)
        store.isModeSelectorExpanded = true
        return store
    }
    
    /// Preview store in speak-only listening mode.
    static var previewSpeakOnly: PracticeStore {
        let store = PracticeStore(dependencies: .preview)
        store.setBrowseState(affirmations: Affirmation.samples)
        store.setFlow(.speakOnly(.listening(.initial)))
        return store
    }
    
    /// Preview store with active session.
    static var previewActiveSession: PracticeStore {
        let store = PracticeStore(dependencies: .preview)
        store.setBrowseState(affirmations: Affirmation.samples)
        store.setSessionState(affirmations: Array(Affirmation.samples.prefix(10)), index: 3)
        store.sessionMode = .readThenSpeak
        store.setFlow(.readAndSpeak(.idle))
        return store
    }
}

// MARK: - Convenience Methods

extension PracticeStore {
    
    /// Exits the current session and returns to home.
    func exit() {
        send(.exitSession)
    }
    
    /// Toggles the favorite status of the current affirmation.
    func toggleFavorite() {
        send(.toggleFavorite)
    }
    
    /// Shares the current affirmation.
    func share() {
        send(.shareAffirmation)
    }
    
    /// Dismisses the current error.
    func dismissError() {
        send(.dismissError)
    }
    
    /// Called when the practice view appears.
    func onAppear() {
        send(.viewAppeared)
    }
    
    /// Called when the practice view disappears.
    func onDisappear() {
        send(.viewDisappeared)
    }
    
    /// Continues the flow after auto-advance animation completes.
    func continueFlow() {
        send(.autoAdvanceCompleted)
    }
    
    /// Handles user navigation in a direction.
    ///
    /// - Parameter direction: The navigation direction
    func navigate(_ direction: NavigationDirection) {
        send(.userNavigated(direction))
    }
}
