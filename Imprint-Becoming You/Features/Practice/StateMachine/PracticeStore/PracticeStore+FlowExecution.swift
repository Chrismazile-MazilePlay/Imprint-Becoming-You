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
            
            try await dependencies.ttsService.speakText(affirmationText, voiceId: nil)
            progressTask.cancel()
            
            guard !Task.isCancelled else { return }
            guard generation == flowGeneration else { return }
            
            setSegmentProgress(1.0)
            send(.ttsCompleted)
            
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
        let speechDuration = affirmation.speechDuration
        
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
        
        // Phase 1: TTS Playback
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
            
            try await dependencies.ttsService.speakText(affirmationText, voiceId: nil)
            progressTask.cancel()
            
            guard !Task.isCancelled else { return }
            guard generation == flowGeneration else { return }
            
        } catch {
            send(.ttsFailed(.ttsError(error.localizedDescription)))
            return
        }
        
        // Phase 2: Wait for user
        withAnimation(AppTheme.Animation.quick) {
            setFlow(.readAndSpeak(.waitingForUser))
            setSegmentProgress(0.5)
        }
        
        try? await Task.sleep(for: PracticeTiming.waitForUserDuration)
        guard !Task.isCancelled else { return }
        guard generation == flowGeneration else { return }
        
        // Phase 3: Listening
        listeningStartTime = Date()
        withAnimation(AppTheme.Animation.quick) {
            setFlow(.readAndSpeak(.listening(.initial)))
        }
        
        await executeListeningPhase(generation: generation, affirmationText: affirmationText)
    }
}

// MARK: - Speak Only Flow

extension PracticeStore {
    
    func executeSpeakOnlyFlow(generation: Int) async {
        guard !Task.isCancelled else { return }
        guard generation == flowGeneration else { return }
        
        guard let affirmationText = currentAffirmation?.text else { return }
        
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
        
        listeningStartTime = Date()
        withAnimation(AppTheme.Animation.quick) {
            setFlow(.speakOnly(.listening(.initial)))
        }
        
        await executeListeningPhase(generation: generation, affirmationText: affirmationText)
    }
}

// MARK: - Listening Phase

extension PracticeStore {
    
    func executeListeningPhase(generation: Int, affirmationText: String) async {
        let startTime = Date()
        var lastTranscription = ""
        var lastAudioLevel: Double = 0
        var hasStarted = false
        
        listeningTask = Task { [weak self] in
            guard let self = self else { return }
            
            let stream = self.speechCaptureService.captureStream
            try? await Task.sleep(for: .milliseconds(50))
            
            do {
                try await self.speechCaptureService.startCapture()
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
            
            self.send(.listeningStarted)
            hasStarted = true
            
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
                        if silenceDuration >= PracticeTiming.incompleteSilenceTimeout { break captureLoop }
                    } else {
                        let completion = TextAccuracyCalculator.evaluateCompletion(expected: affirmationText, recognized: lastTranscription)
                        if completion.isComplete {
                            if silenceDuration >= PracticeTiming.completedAffirmationSilenceThreshold { break captureLoop }
                        } else {
                            if silenceDuration >= PracticeTiming.incompleteSilenceTimeout { break captureLoop }
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
        
        let finalText = speechCaptureService.stopCapture()
        if !finalText.isEmpty { lastTranscription = finalText }
        
        guard !Task.isCancelled else { return }
        guard generation == flowGeneration else { return }
        guard hasStarted else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        
        if lastTranscription.isEmpty {
            send(.listeningTimedOut)
            return
        }
        
        let completion = TextAccuracyCalculator.evaluateCompletion(expected: affirmationText, recognized: lastTranscription)
        
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
            
            if self.isSessionActive && self.sessionIndex >= Constants.Session.sessionSize - 1 {
                self.showSessionSummary()
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
