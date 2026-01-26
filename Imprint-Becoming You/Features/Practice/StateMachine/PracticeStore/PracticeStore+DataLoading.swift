//
//  PracticeStore+DataLoading.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/11/26.
//

import Foundation

// MARK: - Data Loading

extension PracticeStore {
    
    /// Loads affirmations for the given categories into the browse queue.
    ///
    /// - Parameters:
    ///   - repository: The repository to load from
    ///   - categories: Category identifiers to filter by
    func loadAffirmations(
        using repository: any AffirmationRepositoryProtocol,
        forCategories categories: [String]
    ) async {
        self.repository = repository
        self.loadedCategories = categories
        
        do {
            let queue: [Affirmation]
            
            if categories.isEmpty {
                queue = Affirmation.samples
            } else {
                queue = try repository.fetchQueue(forCategories: categories, limit: Constants.Session.batchSize)
            }
            
            send(.affirmationsLoaded(queue.isEmpty ? Affirmation.samples : queue))
            
        } catch {
            send(.affirmationsLoadFailed(.dataLoadError(error.localizedDescription)))
        }
    }
    
    /// Loads user's favorited affirmations into the browse queue.
    ///
    /// - Parameter repository: The repository to load from
    func loadFavorites(using repository: any AffirmationRepositoryProtocol) async {
        self.repository = repository
        
        do {
            let favorites = try repository.fetchFavorites()
            
            guard !favorites.isEmpty else {
                setError(.dataLoadError("No favorites yet. Heart some affirmations first!"))
                return
            }
            
            send(.affirmationsLoaded(favorites))
            send(.exitSession)
            
        } catch {
            send(.affirmationsLoadFailed(.dataLoadError(error.localizedDescription)))
        }
    }
    
    /// Loads user's favorited affirmations as a practice session.
    ///
    /// Unlike `loadFavorites`, this starts a proper session with the selected
    /// mode, allowing scoring, loop tracking, and results summary.
    ///
    /// - Parameters:
    ///   - repository: The repository to load from
    ///   - mode: The practice mode to use
    ///   - shuffle: Whether to shuffle the affirmations
    func loadFavoritesAsSession(
        using repository: any AffirmationRepositoryProtocol,
        mode: SessionMode,
        shuffle: Bool
    ) async {
        self.repository = repository
        
        do {
            let favorites = try repository.fetchFavorites()
            
            guard !favorites.isEmpty else {
                setError(.dataLoadError("No favorites yet. Heart some affirmations first!"))
                return
            }
            
            // Cancel any current activity
            cancelCurrentActivity()
            flowGeneration += 1
            
            // Clear any saved session context (this is not a saved session playback)
            clearSavedSessionContext()
            
            // Mark this as a favorites session
            setFavoritesSession(true)
            
            // Clear original IDs so setSessionState captures fresh ones
            clearOriginalSessionAffirmationIds()
            
            // Set up session state - this captures originalSessionAffirmationIds
            setSessionState(affirmations: favorites, index: 0)
            setSessionResults([])
            setSegmentProgress(0)
            sessionStartTime = Date()
            
            // Shuffle AFTER setting session state (preserves original order in originalSessionAffirmationIds)
            if shuffle {
                shuffleSessionAffirmations()
            }
            
            #if DEBUG
            print("[OK] PracticeStore: Starting favorites session with \(favorites.count) affirmations, mode: \(mode.displayName)")
            #endif
            
            // Use preparation flow for TTS modes
            prepareAndStartSession(mode: mode)
            
        } catch {
            send(.affirmationsLoadFailed(.dataLoadError(error.localizedDescription)))
        }
    }
    
    /// Updates the current index in the active queue.
    ///
    /// Used by VerticalPager when user swipes to a new position.
    ///
    /// - Parameter newIndex: The new index to set
    func updateIndex(_ newIndex: Int) {
        let queue = affirmations
        guard queue.indices.contains(newIndex) else { return }
        
        let currentIdx = isSessionActive ? sessionIndex : browseIndex
        guard newIndex != currentIdx else { return }
        
        flowGeneration += 1
        setSegmentProgress(0)
        
        if isSessionActive {
            resetToIdle()
            setSessionState(index: newIndex)
        } else {
            setBrowseState(index: newIndex)
        }
    }
}

// MARK: - Engagement Tracking

extension PracticeStore {
    
    /// Records an engagement event for the current affirmation.
    ///
    /// - Parameter type: The type of engagement to record
    func recordEngagement(_ type: EngagementType) {
        guard let affirmation = currentAffirmation, let repository = repository else { return }
        
        do {
            switch type {
            case .view:
                try repository.recordView(affirmationId: affirmation.id)
            case .speak:
                try repository.recordSpeak(affirmationId: affirmation.id)
            case .skip:
                try repository.recordSkip(affirmationId: affirmation.id)
            case .share:
                try repository.recordShare(affirmationId: affirmation.id)
            }
        } catch {
            #if DEBUG
            print("[LOG] PracticeStore: Failed to record \(type) engagement")
            #endif
        }
    }
    
    /// Records a resonance score for the current affirmation.
    ///
    /// - Parameter record: The resonance record to persist
    func recordResonance(_ record: ResonanceRecord) {
        guard let affirmation = currentAffirmation, let repository = repository else { return }
        try? repository.addResonanceRecord(affirmationId: affirmation.id, record: record)
    }
}
