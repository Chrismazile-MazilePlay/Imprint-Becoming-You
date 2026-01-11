//
//  PracticeStore+Session.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/11/26.
//

import SwiftUI

// MARK: - Session Queue Generation

extension PracticeStore {
    
    func generateSessionQueue(forMode mode: SessionMode) {
        guard let repo = repository else {
            #if DEBUG
            print("[WARN] PracticeStore: No repository for session queue generation")
            #endif
            setSessionState(affirmations: Array(browseAffirmations.prefix(Constants.Session.sessionSize)))
            startSession(mode: mode)
            return
        }
        
        let recentlyBrowsedIds = Set(browseAffirmations.prefix(20).map { $0.id })
        
        do {
            let freshQueue = try repo.fetchSessionQueue(
                forCategories: loadedCategories,
                excluding: recentlyBrowsedIds,
                limit: Constants.Session.sessionSize
            )
            
            let queue = freshQueue.isEmpty
                ? Array(browseAffirmations.prefix(Constants.Session.sessionSize))
                : freshQueue
            
            setSessionState(affirmations: queue)
            
            #if DEBUG
            print("[OK] PracticeStore: Generated session queue with \(queue.count) fresh affirmations")
            #endif
            
        } catch {
            #if DEBUG
            print("[WARN] PracticeStore: Session queue generation failed: \(error)")
            #endif
            setSessionState(affirmations: Array(browseAffirmations.prefix(Constants.Session.sessionSize)))
        }
        
        startSession(mode: mode)
    }
    
    func startSession(mode: SessionMode) {
        setSessionState(index: 0)
        setSessionResults([])
        sessionMode = mode
        sessionStartTime = Date()
        
        withAnimation(AppTheme.Animation.standard) {
            switch mode {
            case .readOnly:
                setFlow(.home)
            case .readAloud:
                setFlow(.readAloud(.idle))
            case .readThenSpeak:
                setFlow(.readAndSpeak(.idle))
            case .speakOnly:
                setFlow(.speakOnly(.idle))
            }
        }
        
        startFlowForCurrentAffirmation()
    }
}

// MARK: - Browse Batch Tracking

extension PracticeStore {
    
    func trackUniqueBrowseView() {
        guard let affirmation = currentAffirmation else { return }
        
        if !viewedBrowseAffirmationIds.contains(affirmation.id) {
            viewedBrowseAffirmationIds.insert(affirmation.id)
            setBrowseState(consumed: browseBatchConsumed + 1)
            checkBrowseBatchRefresh()
        }
    }
    
    func recordAffirmationForSession() {
        guard let affirmation = currentAffirmation else { return }
        guard !sessionResults.contains(where: { $0.affirmationId == affirmation.id }) else { return }
        
        let isFromScoringMode = (sessionMode == .readThenSpeak || sessionMode == .speakOnly)
        let result = SessionAffirmationResult(affirmation: affirmation, isFromScoringMode: isFromScoringMode)
        appendSessionResult(result)
    }
    
    func checkBrowseBatchRefresh() {
        guard browseBatchConsumed >= Constants.Session.regenerationTriggerIndex else { return }
        guard !isBrowseBatchRefreshInProgress else { return }
        guard let repo = repository else { return }
        guard !loadedCategories.isEmpty else { return }
        
        isBrowseBatchRefreshInProgress = true
        let categories = loadedCategories
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            do {
                let newAffirmations = try repo.fetchQueue(
                    forCategories: categories,
                    limit: Constants.Session.batchSize
                )
                
                self.appendToBrowseQueue(newAffirmations)
                self.isBrowseBatchRefreshInProgress = false
            } catch {
                self.isBrowseBatchRefreshInProgress = false
            }
        }
    }
    
    func appendToBrowseQueue(_ newAffirmations: [Affirmation]) {
        let existingIds = Set(browseAffirmations.map { $0.id })
        let uniqueNew = newAffirmations.filter { !existingIds.contains($0.id) }
        
        var updated = browseAffirmations
        updated.append(contentsOf: uniqueNew)
        setBrowseState(affirmations: updated, consumed: 0)
    }
}

// MARK: - Session Summary

extension PracticeStore {
    
    func showSessionSummary() {
        cancelCurrentActivity()
        
        Task { [weak self] in
            guard let self = self else { return }
            
            try? await Task.sleep(for: PracticeTiming.sessionCompletePause)
            guard !Task.isCancelled else { return }
            
            self.setNavigationLocked(true)
            
            withAnimation(.easeInOut(duration: PracticeTiming.summaryTransitionDuration)) {
                self.setShowingSummary(true)
            }
            
            Task { [weak self] in
                guard let self = self else { return }
                try? await Task.sleep(for: .milliseconds(Int(PracticeTiming.summaryTransitionDuration * 1000)))
                self.setNavigationLocked(false)
            }
            
            HapticFeedback.notification(.success)
        }
    }
    
    func handleDismissSummary() {
        setSessionResults([])
        setSessionState(affirmations: [], index: 0)
        
        withAnimation(.easeInOut(duration: PracticeTiming.summaryDismissDuration)) {
            setShowingSummary(false)
        }
        
        setFlow(.home)
        isModeSelectorExpanded = false
        isBinauralSelectorExpanded = false
    }
    
    func handleRetrySession() {
        setSessionState(index: 0)
        setSessionResults([])
        setSegmentProgress(0)
        
        switch sessionMode {
        case .readAloud:
            setFlow(.readAloud(.idle))
        case .readThenSpeak:
            setFlow(.readAndSpeak(.idle))
        case .speakOnly:
            setFlow(.speakOnly(.idle))
        default:
            setFlow(.home)
        }
        
        withAnimation(.easeInOut(duration: PracticeTiming.summaryDismissDuration)) {
            setShowingSummary(false)
        }
        
        Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: .milliseconds(Int(PracticeTiming.summaryDismissDuration * 1000) + 50))
            self.startFlowForCurrentAffirmation()
        }
    }
    
    func handleToggleFavoriteInSummary(affirmationId: UUID) {
        let affirmation = sessionAffirmations.first { $0.id == affirmationId }
            ?? browseAffirmations.first { $0.id == affirmationId }
        
        guard let affirmation = affirmation else { return }
        
        affirmation.isFavorited.toggle()
        affirmation.favoritedAt = affirmation.isFavorited ? Date() : nil
        
        if let index = sessionResults.firstIndex(where: { $0.affirmationId == affirmationId }) {
            updateSessionResult(at: index, isFavorited: affirmation.isFavorited)
        }
        
        if let repository = repository {
            _ = try? repository.toggleFavorite(affirmationId: affirmationId)
        }
    }
}
