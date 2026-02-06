//
//  PracticeStore+LoopSession.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/12/26.
//

import SwiftUI

// MARK: - Shuffle Logic

extension PracticeStore {
    
    /// Shuffles the session affirmations in place.
    ///
    /// Called at the start of each loop iteration when shuffle is enabled.
    /// Creates a new unique random ordering for variety.
    func shuffleSessionAffirmations() {
        guard sessionAffirmations.count > 1 else { return }
        
        var shuffled = sessionAffirmations
        shuffled.shuffle()
        
        // Update session state with shuffled order (don't update originalSessionAffirmationIds)
        setSessionAffirmationsForShuffle(shuffled)
        
        #if DEBUG
        AppLogger.info("Shuffled session affirmations for new loop", category: .practice)
        #endif
    }
}

// MARK: - Saved Session Playback

extension PracticeStore {
    
    /// Starts playback of a saved session.
    ///
    /// Loads the saved session's affirmations and starts a new session
    /// with the saved session's default mode.
    ///
    /// **Note:** Loop configuration should be set BEFORE calling this method.
    /// The caller (SavedSessionsSection) sets loop count and shuffle from the card controls.
    ///
    /// - Parameter savedSession: The saved session to play
    func handleStartSavedSession(_ savedSession: SavedSession) {
        // Close any open menus
        send(.closeSelectors)
        
        cancelCurrentActivity()
        flowGeneration += 1
        setSegmentProgress(0)
        
        // Note: Do NOT reset loop configuration here - it's already set by the caller
        // Reset only the iteration counter for a fresh start
        resetLoopIteration()
        
        // Set saved session context
        setSavedSessionContext(id: savedSession.id, title: savedSession.name)
        
        // Load affirmations from saved session
        guard let repo = savedSessionRepository else {
            #if DEBUG
            AppLogger.warning("No saved session repository", category: .practice)
            #endif
            return
        }

        do {
            let affirmations = try repo.fetchAffirmations(byIds: savedSession.affirmationIds)

            guard !affirmations.isEmpty else {
                #if DEBUG
                AppLogger.warning("Saved session has no valid affirmations", category: .practice)
                #endif
                setError(.dataLoadError("This saved session's affirmations are no longer available."))
                clearSavedSessionContext()
                return
            }
            
            // Set up session with saved affirmations
            clearOriginalSessionAffirmationIds()
            setSessionState(affirmations: affirmations)
            
            // Record playback
            try? repo.recordPlayback(sessionId: savedSession.id)
            
            #if DEBUG
            AppLogger.info("Starting saved session '\(savedSession.name)' with \(affirmations.count) affirmations", category: .practice)
            #endif
            
            // Start the session with TTS preparation for modes that use it
            prepareAndStartSession(mode: savedSession.defaultMode)
            
        } catch {
            #if DEBUG
            AppLogger.error("Failed to load saved session affirmations: \(error)", category: .practice)
            #endif
            setError(.dataLoadError("Failed to load saved session: \(error.localizedDescription)"))
            clearSavedSessionContext()
        }
    }
}

// MARK: - Save Session

extension PracticeStore {
    
    /// Saves the current session as a new saved session.
    ///
    /// Uses the original (pre-shuffle) affirmation order for consistency.
    /// Only available when NOT playing a saved session.
    ///
    /// ## Validation
    /// - Cannot save while playing a saved session
    /// - Cannot save if at free tier limit (3 sessions)
    /// - Cannot save duplicate (same affirmations) session
    ///
    /// - Parameter name: The name for the saved session
    func handleSaveSession(name: String) {
        guard !isPlayingSavedSession else {
            #if DEBUG
            AppLogger.warning("Cannot save while playing a saved session", category: .practice)
            #endif
            return
        }
        
        guard let repo = savedSessionRepository else {
            #if DEBUG
            AppLogger.warning("No saved session repository", category: .practice)
            #endif
            return
        }

        // Check free tier limit (defense in depth - UI also checks)
        do {
            let currentCount = try repo.count()
            if currentCount >= Constants.FreeTier.maxSavedSessions {
                // TODO: Check if user is premium before blocking
                // For now, enforce the limit for all users
                #if DEBUG
                AppLogger.warning("At saved session limit (\(currentCount)/\(Constants.FreeTier.maxSavedSessions))", category: .practice)
                #endif
                setError(.dataLoadError("You've reached the maximum number of saved sessions."))
                return
            }
        } catch {
            #if DEBUG
            AppLogger.warning("Failed to check session count: \(error)", category: .practice)
            #endif
            // Continue anyway - UI should have validated
        }
        
        // Use original order if available, otherwise current order
        let affirmationIds = originalSessionAffirmationIds.isEmpty
            ? sessionAffirmations.map(\.id)
            : originalSessionAffirmationIds
        
        guard !affirmationIds.isEmpty else {
            #if DEBUG
            AppLogger.warning("No affirmations to save", category: .practice)
            #endif
            return
        }
        
        // Check for duplicates
        do {
            if try repo.exists(withAffirmationIds: affirmationIds) {
                #if DEBUG
                AppLogger.warning("Session with same affirmations already exists", category: .practice)
                #endif
                setError(.dataLoadError("A session with these same affirmations already exists."))
                return
            }
        } catch {
            #if DEBUG
            AppLogger.warning("Failed to check for duplicate session: \(error)", category: .practice)
            #endif
        }
        
        // Create saved session
        let savedSession = SavedSession(
            name: name,
            affirmationIds: affirmationIds,
            defaultMode: sessionMode,
            affirmations: sessionAffirmations
        )
        
        do {
            try repo.save(savedSession)
            
            // Mark session as saved to disable save button
            setHasSessionBeenSaved(true)
            
            // Increment the session counter only after successful save
            PracticeStore.incrementSessionCounter()
            
            HapticFeedback.notification(.success)
            
            #if DEBUG
            AppLogger.info("Saved session '\(name)' with \(affirmationIds.count) affirmations", category: .practice)
            #endif
            
        } catch {
            #if DEBUG
            AppLogger.error("Failed to save session: \(error)", category: .practice)
            #endif
            setError(.dataLoadError("Failed to save session: \(error.localizedDescription)"))
        }
    }
    
    /// Generates a default name for a new saved session.
    ///
    /// Format: "Session X - Jan 11" where X is the next counter value.
    /// **Note:** This does NOT increment the counter. Call `incrementSessionCounter()`
    /// after a successful save to increment.
    ///
    /// - Returns: A default session name
    static func generateDefaultSessionName() -> String {
        // Peek at next counter value without incrementing
        let counter = UserDefaults.standard.integer(forKey: Constants.StorageKeys.savedSessionCounter) + 1
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let dateString = formatter.string(from: Date())
        
        return "Session \(counter) - \(dateString)"
    }
    
    /// Increments the session counter after a successful save.
    ///
    /// Should be called only after `handleSaveSession` successfully saves.
    static func incrementSessionCounter() {
        let counter = UserDefaults.standard.integer(forKey: Constants.StorageKeys.savedSessionCounter) + 1
        UserDefaults.standard.set(counter, forKey: Constants.StorageKeys.savedSessionCounter)
    }
}
