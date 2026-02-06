//
//  PracticeStore+FlowExecution.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/11/26.
//

import SwiftUI

// MARK: - Flow Execution

extension PracticeStore {
    
    func startFlowForCurrentAffirmation() {
        guard currentAffirmation != nil else { return }
        
        // Use centralized task management for proper cleanup
        cancelFlowTask()
        flowGeneration += 1
        
        recordAffirmationView()
        recordEngagement(.view)
        
        if sessionMode != .readOnly {
            recordAffirmationForSession()
        }
        
        let generation = flowGeneration
        
        activeFlowTask = Task { [weak self] in
            guard let self = self else { return }
            await self.executeCurrentFlow(generation: generation)
        }
    }
    
    func executeCurrentFlow(generation: Int) async {
        guard shouldContinueFlow(generation: generation) else { return }

        // DRAIN: Guarantee a clean AudioPlayerService state before starting
        // new playback. This serializes behind any pending fire-and-forget
        // stop() Tasks from cancelCurrentActivity(), ensuring the actor
        // processes them first. Uses stop() (not cancelAndStop()) because
        // we want resume(returning: ()) semantics — the previous caller
        // gets a clean completion, not a CancellationError.
        await dependencies.audioPlayerService.stop()

        // Re-check generation after the await — a navigation event during
        // the drain should abort this flow.
        guard shouldContinueFlow(generation: generation) else { return }

        // Measure flow execution with signpost
        let signpostID = AppLogger.makeSignpostID(for: .practice)
        AppLogger.beginInterval(AppLogger.SignpostName.flowExecution, id: signpostID, category: .practice)
        
        defer {
            AppLogger.endInterval(AppLogger.SignpostName.flowExecution, id: signpostID, category: .practice)
        }
        
        switch flow {
        case .home:
            break
        case .readAloud:
            await executeReadAloudFlow(generation: generation)
        case .readAndSpeak:
            await executeReadAndSpeakFlow(generation: generation)
        case .speakOnly:
            await executeSpeakOnlyFlow(generation: generation)
        }
    }
}

// MARK: - TTS Helpers

extension PracticeStore {
    
    /// Plays audio for the current affirmation via the playback coordinator.
    ///
    /// Captures `sessionIndex` and affirmation UUID atomically at the call site,
    /// making the async chain immune to concurrent `sessionIndex` mutations
    /// from rapid skipping.
    ///
    /// - Parameter text: The text to speak (used for on-demand synthesis fallback)
    /// - Throws: `TTSError` if synthesis or playback fails
    private func speakText(_ text: String) async throws {
        // Capture session index and affirmation ID at entry. sessionIndex is a
        // live @Observable property that changes during rapid skipping. Capturing
        // both values ensures the coordinator uses stable references throughout.
        let currentIndex = sessionIndex
        let affirmationID = sessionAffirmations[currentIndex].id

        try await playbackCoordinator.playAffirmation(
            index: currentIndex,
            affirmationID: affirmationID,
            text: text,
            isSessionActive: isSessionActive,
            selectedVoiceId: selectedVoiceId
        )
    }

    /// Stops any ongoing TTS playback immediately via the playback coordinator.
    private func stopTTSPlayback() {
        playbackCoordinator.stopPlayback()
    }
    
    /// Pre-synthesizes the next affirmation for faster playback.
    ///
    /// This is now handled by SessionTTSQueueService for sessions.
    /// Only used for browse mode where the queue isn't active.
    private func preSynthesizeNextAffirmation() {
        // Queue handles this automatically for sessions
        guard !isSessionActive else { return }
        
        // Only pre-synthesize if there's a next affirmation in browse mode
        let nextIndex = browseIndex + 1
        guard nextIndex < browseAffirmations.count else { return }
        
        let nextText = browseAffirmations[nextIndex].text.strippingTrailingCitation
        
        // Fire-and-forget: pre-synthesis is best-effort, no tracking needed
        Task { [weak self] in
            guard let self = self else { return }
            await self.dependencies.ttsService.preSynthesize(text: nextText, voiceId: self.selectedVoiceId)
        }
    }
}

// MARK: - Read Aloud Flow

extension PracticeStore {
    
    func executeReadAloudFlow(generation: Int) async {
        guard shouldContinueFlow(generation: generation) else { return }
        
        guard let affirmation = currentAffirmation else { return }
        let affirmationText = affirmation.text
        let speechDuration = affirmation.speechDuration
        
        withAnimation(AppTheme.Animation.quick) {
            setFlow(.readAloud(.playing(progress: 0)))
        }
        
        do {
            let estimatedDuration = max(speechDuration, PracticeTiming.ttsMininumHoldDuration)
            
            // Progress tracking task - local to this flow, cancelled when TTS completes
            let progressTask = Task { [weak self] in
                guard let self = self else { return }
                let startTime = Date()
                while !Task.isCancelled && generation == self.flowGeneration {
                    try? await Task.sleep(for: .milliseconds(50))
                    let elapsed = Date().timeIntervalSince(startTime)
                    let progress = min(elapsed / estimatedDuration, 0.95)
                    
                    guard generation == self.flowGeneration else { return }
                    self.send(.ttsProgress(progress))
                    
                    if elapsed >= estimatedDuration * 0.95 { break }
                }
            }
            
            // Pre-synthesize next affirmation while this one plays
            preSynthesizeNextAffirmation()
            
            try await speakText(affirmationText.strippingTrailingCitation)
            progressTask.cancel()
            
            guard shouldContinueFlow(generation: generation) else { return }
            
            // NOTE: For Read Aloud mode, we do NOT call scheduleAutoAdvance() here.
            // The dock's segment timer handles auto-advance via segmentTimerCompleted event.
            
            withAnimation(AppTheme.Animation.quick) {
                setFlow(.readAloud(.complete))
            }
            
        } catch {
            guard generation == flowGeneration else { return }
            send(.ttsFailed(.ttsError(error.localizedDescription)))
        }
    }
}

// MARK: - Read And Speak Flow

extension PracticeStore {
    
    func executeReadAndSpeakFlow(generation: Int) async {
        guard shouldContinueFlow(generation: generation) else { return }
        
        guard let affirmation = currentAffirmation else { return }
        let affirmationText = affirmation.text
        // Strip citation for speech recognition (user doesn't speak verse references)
        let textForListening = affirmationText.strippingTrailingCitation
        let speechDuration = affirmation.speechDuration
        
        AppLogger.debug(
            "Read and Speak flow started",
            category: .practice,
            context: [
                "hasStrippedCitation": affirmationText != textForListening,
                "wordCount": textForListening.split(separator: " ").count
            ]
        )
        
        // Check permissions
        let speechService = dependencies.speechAnalysisService
        let hasMicPermission = await speechService.requestMicrophonePermission()
        let hasSpeechPermission = await speechService.requestSpeechRecognitionPermission()
        
        guard hasMicPermission && hasSpeechPermission else {
            if !hasMicPermission && !hasSpeechPermission {
                send(.permissionDenied(.both))
            } else if !hasMicPermission {
                send(.permissionDenied(.microphone))
            } else {
                send(.permissionDenied(.speechRecognition))
            }
            return
        }
        
        // Phase 1: TTS Playback (orange waveform)
        withAnimation(AppTheme.Animation.quick) {
            setFlow(.readAndSpeak(.ttsPlaying(progress: 0)))
        }
        
        do {
            let estimatedDuration = max(speechDuration, PracticeTiming.ttsMininumHoldDuration)
            
            // Progress tracking task - local to this flow
            let progressTask = Task { [weak self] in
                guard let self = self else { return }
                let startTime = Date()
                while !Task.isCancelled && generation == self.flowGeneration {
                    try? await Task.sleep(for: .milliseconds(50))
                    let elapsed = Date().timeIntervalSince(startTime)
                    let progress = min(elapsed / estimatedDuration, 0.45)
                    
                    guard generation == self.flowGeneration else { return }
                    self.send(.ttsProgress(progress))
                    
                    if elapsed >= estimatedDuration * 0.95 { break }
                }
            }
            
            // Pre-synthesize next affirmation while this one plays
            preSynthesizeNextAffirmation()
            
            try await speakText(affirmationText.strippingTrailingCitation)
            progressTask.cancel()
            
            guard shouldContinueFlow(generation: generation) else { return }
            
        } catch {
            send(.ttsFailed(.ttsError(error.localizedDescription)))
            return
        }
        
        // Phase 2: Preparing to Listen (green breathing animation)
        // UI shows preparing state while speech engine initializes off main thread
        withAnimation(AppTheme.Animation.quick) {
            setFlow(.readAndSpeak(.preparingToListen))
        }
        
        // Execute listening phase (handles initialization and actual listening)
        listeningStartTime = Date()
        await executeListeningPhase(generation: generation, affirmationText: textForListening, mode: .readAndSpeak)
    }
}

// MARK: - Speak Only Flow

extension PracticeStore {
    
    func executeSpeakOnlyFlow(generation: Int) async {
        guard shouldContinueFlow(generation: generation) else { return }
        
        guard let affirmationText = currentAffirmation?.text else { return }
        // Strip citation for speech recognition (user doesn't speak verse references)
        let textForListening = affirmationText.strippingTrailingCitation
        
        AppLogger.debug(
            "Speak Only flow started",
            category: .practice,
            context: [
                "hasStrippedCitation": affirmationText != textForListening,
                "wordCount": textForListening.split(separator: " ").count
            ]
        )
        
        // Check permissions
        let speechService = dependencies.speechAnalysisService
        let hasMicPermission = await speechService.requestMicrophonePermission()
        let hasSpeechPermission = await speechService.requestSpeechRecognitionPermission()
        
        guard hasMicPermission && hasSpeechPermission else {
            if !hasMicPermission && !hasSpeechPermission {
                send(.permissionDenied(.both))
            } else if !hasMicPermission {
                send(.permissionDenied(.microphone))
            } else {
                send(.permissionDenied(.speechRecognition))
            }
            return
        }
        
        // Show preparing state (green breathing animation)
        // UI shows this while speech engine initializes off main thread
        withAnimation(AppTheme.Animation.quick) {
            setFlow(.speakOnly(.preparingToListen))
        }
        
        // Execute listening phase (handles initialization and actual listening)
        listeningStartTime = Date()
        await executeListeningPhase(generation: generation, affirmationText: textForListening, mode: .speakOnly)
    }
}

// MARK: - Listening Phase

extension PracticeStore {
    
    /// Mode for the listening phase (determines which flow state to update)
    enum ListeningMode {
        case readAndSpeak
        case speakOnly
    }
    
    /// Executes the listening phase with proper initialization sequence.
    ///
    /// Flow:
    /// 1. Currently in `.preparingToListen` state (green breathing)
    /// 2. Initialize speech capture (may involve heavy audio setup)
    /// 3. Transition to `.listening` only after capture is ready
    /// 4. Process audio and transcription
    /// 5. Complete with result
    func executeListeningPhase(generation: Int, affirmationText: String, mode: ListeningMode) async {
        // Measure listening phase with signpost
        let signpostID = AppLogger.makeSignpostID(for: .speech)
        AppLogger.beginInterval(AppLogger.SignpostName.listeningPhase, id: signpostID, category: .speech)
        
        defer {
            AppLogger.endInterval(AppLogger.SignpostName.listeningPhase, id: signpostID, category: .speech)
        }
        
        AppLogger.debug(
            "Listening phase started",
            category: .speech,
            context: [
                "mode": String(describing: mode),
                "wordCount": affirmationText.split(separator: " ").count
            ]
        )
        
        let startTime = Date()
        var lastTranscription = ""
        var lastAudioLevel: Double = 0
        var hasStarted = false
        
        // Get speech capture service from store's property
        let captureService = speechCaptureService
        
        // Use centralized task management for listening task
        listeningTask = Task { [weak self] in
            guard let self = self else { return }
            
            let stream = captureService.captureStream
            
            // PHASE: Initialize capture (while still in .preparingToListen state)
            // The UI shows green breathing animation during this
            do {
                // Measure speech recognition initialization with signpost
                let initSignpostID = AppLogger.makeSignpostID(for: .speech)
                AppLogger.beginInterval(AppLogger.SignpostName.speechRecognitionInit, id: initSignpostID, category: .speech)
                
                do {
                    try await captureService.startCapture()
                } catch {
                    AppLogger.endInterval(AppLogger.SignpostName.speechRecognitionInit, id: initSignpostID, category: .speech)
                    throw error
                }
                
                AppLogger.endInterval(AppLogger.SignpostName.speechRecognitionInit, id: initSignpostID, category: .speech)
                
            } catch {
                guard generation == self.flowGeneration else { return }
                
                if let captureError = error as? SpeechCaptureError {
                    switch captureError {
                    case .microphonePermissionDenied:
                        self.send(.permissionDenied(.microphone))
                    case .speechRecognitionPermissionDenied:
                        self.send(.permissionDenied(.speechRecognition))
                    case .audioSessionUnavailable:
                        self.send(.listeningFailed(.audioSessionBusy))
                    default:
                        self.send(.listeningFailed(.speechRecognitionError(String(describing: captureError))))
                    }
                } else {
                    self.send(.listeningFailed(.speechRecognitionError(error.localizedDescription)))
                }
                return
            }
            
            // PHASE: Capture initialized successfully
            // NOW transition to .listening state (green active waveform + chip)
            await MainActor.run {
                withAnimation(AppTheme.Animation.quick) {
                    switch mode {
                    case .readAndSpeak:
                        self.setFlow(.readAndSpeak(.listening(.initial)))
                    case .speakOnly:
                        self.setFlow(.speakOnly(.listening(.initial)))
                    }
                }
            }
            
            self.send(.listeningStarted)
            hasStarted = true
            
            // PHASE: Active listening loop
            // Measure active speech capture with signpost
            let captureSignpostID = AppLogger.makeSignpostID(for: .speech)
            AppLogger.beginInterval(AppLogger.SignpostName.speechCapture, id: captureSignpostID, category: .speech)
            
            defer {
                AppLogger.endInterval(AppLogger.SignpostName.speechCapture, id: captureSignpostID, category: .speech)
            }
            
            captureLoop: for await update in stream {
                guard !Task.isCancelled else { break captureLoop }
                guard generation == self.flowGeneration else { break captureLoop }
                
                switch update {
                case .transcription(let text, let isFinal):
                    lastTranscription = text
                    if isFinal && !text.isEmpty { break captureLoop }
                    
                case .audioLevel(let level):
                    lastAudioLevel = Double(level)
                    let elapsed = Date().timeIntervalSince(startTime)
                    
                    if elapsed >= PracticeTiming.maximumListeningDuration { break captureLoop }
                    
                    let context = ListeningContext(elapsed: elapsed, audioLevel: lastAudioLevel, recognizedText: lastTranscription)
                    self.send(.listeningUpdate(context))
                    
                case .silenceDetected(let silenceDuration):
                    if lastTranscription.isEmpty {
                        if silenceDuration >= PracticeTiming.incompleteSilenceTimeout {
                            AppLogger.debug(
                                "Breaking: Empty transcription + silence",
                                category: .speech,
                                context: ["silenceDuration": silenceDuration, "threshold": PracticeTiming.incompleteSilenceTimeout]
                            )
                            break captureLoop
                        }
                    } else {
                        let completion = TextAccuracyCalculator.evaluateCompletion(expected: affirmationText, recognized: lastTranscription)
                        AppLogger.debug(
                            "Silence detected",
                            category: .speech,
                            context: [
                                "silenceDuration": silenceDuration,
                                "matchedWords": completion.matchedWordCount,
                                "expectedWords": completion.expectedWordCount,
                                "isComplete": completion.isComplete
                            ]
                        )
                        if completion.isComplete {
                            if silenceDuration >= PracticeTiming.completedAffirmationSilenceThreshold {
                                AppLogger.debug(
                                    "Breaking: Complete + silence",
                                    category: .speech,
                                    context: ["silenceDuration": silenceDuration, "threshold": PracticeTiming.completedAffirmationSilenceThreshold]
                                )
                                break captureLoop
                            }
                        } else {
                            if silenceDuration >= PracticeTiming.incompleteSilenceTimeout {
                                AppLogger.debug(
                                    "Breaking: Incomplete + silence",
                                    category: .speech,
                                    context: ["silenceDuration": silenceDuration, "threshold": PracticeTiming.incompleteSilenceTimeout]
                                )
                                break captureLoop
                            }
                        }
                    }
                    
                case .error(let captureError):
                    switch captureError {
                    case .microphonePermissionDenied:
                        self.send(.permissionDenied(.microphone))
                    case .speechRecognitionPermissionDenied:
                        self.send(.permissionDenied(.speechRecognition))
                    default:
                        self.send(.listeningFailed(.speechRecognitionError(String(describing: captureError))))
                    }
                    return
                    
                case .started, .stopped:
                    if case .stopped = update { break captureLoop }
                }
            }
        }
        
        // Wait with timeout using task group
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in await self?.listeningTask?.value }
            group.addTask { try? await Task.sleep(for: .seconds(PracticeTiming.maximumListeningDuration)) }
            await group.next()
            group.cancelAll()
        }
        
        // Clean up listening task
        cancelListeningTask()
        
        let finalText = captureService.stopCapture()
        if !finalText.isEmpty { lastTranscription = finalText }
        
        guard shouldContinueFlow(generation: generation) else { return }
        guard hasStarted else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        
        if lastTranscription.isEmpty {
            AppLogger.debug("Timeout: No transcription received", category: .speech)
            send(.listeningTimedOut)
            return
        }
        
        let completion = TextAccuracyCalculator.evaluateCompletion(expected: affirmationText, recognized: lastTranscription)
        
        AppLogger.debug(
            "Final completion check",
            category: .speech,
            context: [
                "isComplete": completion.isComplete,
                "accuracy": String(format: "%.2f", completion.accuracy),
                "wordsCovered": String(format: "%.2f", completion.wordsCovered),
                "matchedWords": completion.matchedWordCount,
                "expectedWords": completion.expectedWordCount
            ]
        )
        
        if completion.isComplete {
            send(.listeningCompleted(recognizedText: lastTranscription, duration: duration))
        } else {
            send(.listeningTimedOut)
        }
    }
}

// MARK: - Scheduling Helpers

extension PracticeStore {
    
    /// Schedules auto-advance after a delay.
    ///
    /// **Task Lifecycle:** Fire-and-forget with `isCancelled` check.
    /// Short-lived (< 2s), self-terminating, no tracking needed.
    func scheduleAutoAdvance() {
        Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: PracticeTiming.readAloudCompletePause)
            guard !Task.isCancelled else { return }
            
            // Check if we've reached the last affirmation in the session
            if self.isSessionActive && self.sessionIndex >= Constants.Session.sessionSize - 1 {
                // Use handleLoopIterationCompleted to properly check for loops
                // This ensures Read Aloud mode respects loop configuration
                self.handleLoopIterationCompleted()
                return
            }
            
            if self.canGoNext {
                self.pendingAutoAdvance = .next
            }
        }
    }
    
    /// Locks navigation for a brief period (during score display).
    ///
    /// **Task Lifecycle:** Fire-and-forget.
    /// Short-lived (< 3s), self-terminating, no tracking needed.
    func lockNavigation() {
        setNavigationLocked(true)
        
        Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: PracticeTiming.navigationLockDuration)
            self.setNavigationLocked(false)
        }
    }
}

// MARK: - Activity Management

extension PracticeStore {
    
    /// Cancels all current activity and clears pending state.
    ///
    /// This is the primary cleanup method called on:
    /// - Navigation events
    /// - Mode changes
    /// - Session exit
    /// - View disappearance
    func cancelCurrentActivity() {
        // Use centralized task management
        cancelFlowTask()
        cancelListeningTask()
        
        pendingAutoAdvance = nil
        
        // Clear forward navigation flag if set (navigation was interrupted)
        setForwardNavigationPending(false)
        
        // Stop TTS playback
        stopTTSPlayback()
        
        // Cancel pre-synthesis
        dependencies.ttsService.cancelPreSynthesis()
        
        // Stop speech capture (synchronous)
        speechCaptureService.cancelCapture()
        
        // Cancel speech analysis (async, fire-and-forget - instant operation)
        Task { [weak self] in
            guard let self = self else { return }
            await self.dependencies.speechAnalysisService.cancelAnalysis()
        }
        
        AppLogger.debug("Current activity cancelled", category: .practice)
    }
    
    func resetToIdle() {
        setSegmentProgress(0)
        
        withAnimation(AppTheme.Animation.quick) {
            switch flow {
            case .home:
                break
            case .readAloud:
                setFlow(.readAloud(.idle))
            case .readAndSpeak:
                setFlow(.readAndSpeak(.idle))
            case .speakOnly:
                setFlow(.speakOnly(.idle))
            }
        }
    }
}
