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
        
        activeFlowTask?.cancel()
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
        guard !Task.isCancelled else { return }
        guard generation == flowGeneration else { return }
        
        try? await Task.sleep(for: PracticeTiming.flowStartDelay)
        
        guard !Task.isCancelled else { return }
        guard generation == flowGeneration else { return }
        
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

// MARK: - Read Aloud Flow

extension PracticeStore {
    
    func executeReadAloudFlow(generation: Int) async {
        guard !Task.isCancelled else { return }
        guard generation == flowGeneration else { return }
        
        guard let affirmation = currentAffirmation else { return }
        let affirmationText = affirmation.text
        let speechDuration = affirmation.speechDuration
        
        withAnimation(AppTheme.Animation.quick) {
            setFlow(.readAloud(.playing(progress: 0)))
        }
        
        do {
            let estimatedDuration = max(speechDuration, PracticeTiming.ttsMininumHoldDuration)
            
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
            
            try await dependencies.ttsService.speakText(affirmationText.strippingTrailingCitation, voiceId: nil)
            progressTask.cancel()
            
            guard !Task.isCancelled else { return }
            guard generation == flowGeneration else { return }
            
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
        guard !Task.isCancelled else { return }
        guard generation == flowGeneration else { return }
        
        guard let affirmation = currentAffirmation else { return }
        let affirmationText = affirmation.text
        // Strip citation for speech recognition (user doesn't speak verse references)
        let textForListening = affirmationText.strippingTrailingCitation
        let speechDuration = affirmation.speechDuration
        
        #if DEBUG
        if affirmationText != textForListening {
            print("[DEBUG] 📖 Citation STRIPPED:")
            print("[DEBUG]   Original: '\(affirmationText.suffix(50))'")
            print("[DEBUG]   Stripped: '\(textForListening.suffix(50))'")
        } else {
            print("[DEBUG] 📖 No citation found to strip (original text unchanged)")
        }
        #endif
        
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
            
            try await dependencies.ttsService.speakText(affirmationText.strippingTrailingCitation, voiceId: nil)
            progressTask.cancel()
            
            guard !Task.isCancelled else { return }
            guard generation == flowGeneration else { return }
            
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
        guard !Task.isCancelled else { return }
        guard generation == flowGeneration else { return }
        
        guard let affirmationText = currentAffirmation?.text else { return }
        // Strip citation for speech recognition (user doesn't speak verse references)
        let textForListening = affirmationText.strippingTrailingCitation
        
        #if DEBUG
        if affirmationText != textForListening {
            print("[DEBUG] 📖 Citation STRIPPED (SpeakOnly):")
            print("[DEBUG]   Original: '\(affirmationText.suffix(50))'")
            print("[DEBUG]   Stripped: '\(textForListening.suffix(50))'")
        } else {
            print("[DEBUG] 📖 No citation found to strip (SpeakOnly, original text unchanged)")
        }
        #endif
        
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
        #if DEBUG
        print("═══════════════════════════════════════════════════════")
        print("[DEBUG] executeListeningPhase STARTED")
        print("[DEBUG] Mode: \(mode)")
        print("[DEBUG] Expected text: '\(affirmationText)'")
        print("[DEBUG] Word count: \(affirmationText.split(separator: " ").count)")
        print("[DEBUG] Ends with ')': \(affirmationText.hasSuffix(")"))")
        print("[DEBUG] Last 30 chars: '\(String(affirmationText.suffix(30)))'")
        print("═══════════════════════════════════════════════════════")
        #endif
        
        let startTime = Date()
        var lastTranscription = ""
        var lastAudioLevel: Double = 0
        var hasStarted = false
        
        // Get speech capture service from store's property
        let captureService = speechCaptureService
        
        listeningTask = Task { [weak self] in
            guard let self = self else { return }
            
            let stream = captureService.captureStream
            
            // Small delay to allow UI to settle
            try? await Task.sleep(for: .milliseconds(50))
            
            // PHASE: Initialize capture (while still in .preparingToListen state)
            // The UI shows green breathing animation during this
            do {
                try await captureService.startCapture()
            } catch {
                guard generation == self.flowGeneration else { return }
                
                if let captureError = error as? SpeechCaptureService.CaptureError {
                    switch captureError {
                    case .microphonePermissionDenied:
                        self.send(.permissionDenied(.microphone))
                    case .speechRecognitionPermissionDenied:
                        self.send(.permissionDenied(.speechRecognition))
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
                            #if DEBUG
                            print("[DEBUG] 🔇 Breaking: Empty transcription + silence \(String(format: "%.1f", silenceDuration))s >= \(PracticeTiming.incompleteSilenceTimeout)s")
                            #endif
                            break captureLoop
                        }
                    } else {
                        let completion = TextAccuracyCalculator.evaluateCompletion(expected: affirmationText, recognized: lastTranscription)
                        #if DEBUG
                        print("[DEBUG] 🔇 Silence \(String(format: "%.1f", silenceDuration))s - Words: \(completion.matchedWordCount)/\(completion.expectedWordCount), Complete: \(completion.isComplete)")
                        #endif
                        if completion.isComplete {
                            if silenceDuration >= PracticeTiming.completedAffirmationSilenceThreshold {
                                #if DEBUG
                                print("[DEBUG] ✅ Breaking: Complete + silence \(String(format: "%.1f", silenceDuration))s >= \(PracticeTiming.completedAffirmationSilenceThreshold)s")
                                #endif
                                break captureLoop
                            }
                        } else {
                            if silenceDuration >= PracticeTiming.incompleteSilenceTimeout {
                                #if DEBUG
                                print("[DEBUG] ❌ Breaking: Incomplete + silence \(String(format: "%.1f", silenceDuration))s >= \(PracticeTiming.incompleteSilenceTimeout)s")
                                #endif
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
        
        // Wait with timeout
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in await self?.listeningTask?.value }
            group.addTask { try? await Task.sleep(for: .seconds(PracticeTiming.maximumListeningDuration)) }
            await group.next()
            group.cancelAll()
        }
        
        listeningTask?.cancel()
        listeningTask = nil
        
        let finalText = captureService.stopCapture()
        if !finalText.isEmpty { lastTranscription = finalText }
        
        guard !Task.isCancelled else { return }
        guard generation == flowGeneration else { return }
        guard hasStarted else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        
        if lastTranscription.isEmpty {
            #if DEBUG
            print("[DEBUG] ❌ TIMEOUT: No transcription received")
            #endif
            send(.listeningTimedOut)
            return
        }
        
        let completion = TextAccuracyCalculator.evaluateCompletion(expected: affirmationText, recognized: lastTranscription)
        
        #if DEBUG
        print("═══════════════════════════════════════════════════════")
        print("[DEBUG] FINAL COMPLETION CHECK")
        print("[DEBUG] Expected text: '\(affirmationText)'")
        print("[DEBUG] Recognized text: '\(lastTranscription)'")
        print("[DEBUG] isComplete: \(completion.isComplete)")
        print("[DEBUG] accuracy: \(String(format: "%.2f", completion.accuracy))")
        print("[DEBUG] wordsCovered: \(String(format: "%.2f", completion.wordsCovered)) (\(completion.matchedWordCount)/\(completion.expectedWordCount) words)")
        print("[DEBUG] Threshold needed: 0.75 (75%)")
        if !completion.isComplete {
            print("[DEBUG] ⚠️ NOT COMPLETE - Need \(Int(0.75 * Float(completion.expectedWordCount))) words, got \(completion.matchedWordCount)")
        }
        print("═══════════════════════════════════════════════════════")
        #endif
        
        if completion.isComplete {
            send(.listeningCompleted(recognizedText: lastTranscription, duration: duration))
        } else {
            send(.listeningTimedOut)
        }
    }
}

// MARK: - Scheduling Helpers

extension PracticeStore {
    
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
    
    func cancelCurrentActivity() {
        activeFlowTask?.cancel()
        activeFlowTask = nil
        pendingAutoAdvance = nil
        
        listeningTask?.cancel()
        listeningTask = nil
        listeningStartTime = nil
        
        // Stop TTS using DI service (synchronous)
        dependencies.ttsService.stopSpeaking()
        
        // Stop speech capture (synchronous)
        speechCaptureService.cancelCapture()
        
        // Cancel speech analysis (async, fire-and-forget)
        Task { [weak self] in
            guard let self = self else { return }
            await self.dependencies.speechAnalysisService.cancelAnalysis()
        }
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
