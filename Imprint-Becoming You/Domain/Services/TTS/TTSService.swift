//
//  TTSService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

#if !targetEnvironment(simulator)
import Foundation
import AVFoundation
import iOS_TTS

// MARK: - TTS Service

/// Production implementation of text-to-speech service.
///
/// Integrates Kokoro neural TTS with System TTS fallback for reliable
/// high-quality speech synthesis optimized for affirmation delivery.
///
/// ## Voice Routing
/// - `nil` / empty: Kokoro with default voice (af_heart)
/// - `af_heart`, `am_adam`, etc.: Kokoro with specified voice
/// - `system`: System AVSpeechSynthesizer
///
/// ## Voice Settings
/// Speed, pitch, and expressiveness can be customized per-voice via
/// `VoiceSettingsManager`. Settings are passed through the synthesis chain
/// to the Kokoro engine for F0 curve modification.
///
/// ## Pre-Synthesis
/// Use `preSynthesize()` to prepare the next affirmation while the current
/// one is playing, reducing latency for seamless transitions.
///
/// ## Memory Management
/// Use `releaseForBackground()` when entering background to free ML pipelines (~500MB-1GB).
/// Call `warmUp()` again when returning to foreground.
/// The synthesis idle timer automatically releases pipelines after 30s of
/// inactivity, keeping the app's steady-state memory footprint minimal (~90-100MB).
///
/// ## Audio Session Pre-Configuration
/// The audio session is pre-configured during `warmUp()` on a background queue
/// to avoid blocking the main thread. This reduces UI jank during TTS playback
/// initialization from ~50-200ms to near-zero latency.
///
/// ## Performance Profiling
/// Key operations are instrumented with os_signpost for Instruments profiling:
/// - `TTS Warmup`: ML model loading time
/// - `TTS Synthesis`: Per-affirmation synthesis duration
/// - `Audio Session Config`: Audio session setup latency
///
/// ## Architecture
/// ```
/// TTSService
/// +-- KokoroTTSEngine (primary - high quality neural TTS)
/// |   +-- Falls back to SystemTTS if:
/// |       - Engine not initialized
/// |       - Synthesis fails
/// |       - Invalid voice ID
/// +-- SystemTTSService (fallback - always available)
/// ```
@MainActor
final class TTSService: TTSServiceProtocol {
    
    // MARK: - Dependencies
    
    /// Kokoro neural TTS engine (primary)
    private var kokoroEngine: KokoroTTSEngine
    
    /// System TTS service for fallback
    private let systemTTS: SystemTTSService
    
    /// Audio player service for unified engine playback.
    ///
    /// Set by `DependencyContainer` after construction. Routes TTS audio through
    /// the same `AVAudioEngine` as background music, eliminating dual-render-client
    /// contention that caused static on first playback.
    var audioPlayerService: (any AudioPlayerServiceProtocol)?

    /// Audio service for engine lifecycle (ensures engine is running before playback).
    var audioService: (any AudioServiceProtocol)?

    /// Audio cache manager
    private let cacheManager: AudioCacheManager
    
    /// Active pre-synthesis task
    private var preSynthesisTask: Task<Void, Never>?
    
    // MARK: - State
    
    /// Whether Kokoro or System TTS is currently speaking
    private var _isSpeaking: Bool = false
    
    /// Whether Kokoro engine is ready
    private var _isKokoroReady: Bool = false
    
    /// Whether we've released resources for background
    private var _isReleasedForBackground: Bool = false
    
    /// Whether the idle timer is suppressed during an active session.
    ///
    /// When `true`, `resetSynthesisIdleTimer()` becomes a no-op, preventing
    /// the idle timer from firing mid-session. Set by `suppressSynthesisIdleTimer()`,
    /// cleared by `resumeSynthesisIdleTimer()`.
    private var _isIdleTimerSuppressed: Bool = false
    
    // (Audio session state removed — AudioService/AudioSessionController now owns session config)
    
    // MARK: - Synthesis Idle Timer
    
    /// Task that counts down to automatic pipeline memory release.
    ///
    /// Resets after every Kokoro synthesis completes. When the timer fires
    /// (no synthesis for `synthesisIdleTimeout` seconds), pipeline memory
    /// is automatically released to free ~800MBâ€“1.5GB of CoreML buffers.
    ///
    /// This solves the memory retention problem in voice preview flows
    /// (Voice Settings, Voice Modification, Onboarding) where synthesis
    /// loads the pipeline but no explicit cleanup ever fires on navigation.
    private var synthesisIdleTimer: Task<Void, Never>?
    
    /// Idle timeout before automatic pipeline memory release (in seconds).
    ///
    /// Balances competing needs:
    /// - Short enough to free memory promptly after voice preview navigation (~30s)
    /// - Long enough to keep pipeline warm during active voice browsing (2â€“5s gaps)
    /// - Pipeline reload takes ~1â€“2s from CoreML cache, masked by UI indicators
    private let synthesisIdleTimeout: TimeInterval = 30
    
    // MARK: - Initialization
    
    init() {
        self.kokoroEngine = KokoroTTSEngine()
        
        let systemTTS = SystemTTSService()
        systemTTS.speechRate = TTSConfiguration.speechRate
        systemTTS.pitchMultiplier = TTSConfiguration.pitchMultiplier
        self.systemTTS = systemTTS
        
        self.cacheManager = AudioCacheManager.shared
    }
    
    /// Creates a TTS service with injected dependencies (for testing).
    init(kokoroEngine: KokoroTTSEngine, systemTTS: SystemTTSService, cacheManager: AudioCacheManager) {
        self.kokoroEngine = kokoroEngine
        
        systemTTS.speechRate = TTSConfiguration.speechRate
        systemTTS.pitchMultiplier = TTSConfiguration.pitchMultiplier
        self.systemTTS = systemTTS
        
        self.cacheManager = cacheManager
    }
    
    // MARK: - TTSServiceProtocol
    
    var isSpeaking: Bool {
        _isSpeaking || systemTTS.isSpeaking
    }
    
    var isKokoroReady: Bool {
        _isKokoroReady
    }
    
    func warmUp() async {
        // Measure total warm-up time with signpost
        await AppLogger.measureAsync(AppLogger.SignpostName.ttsWarmup, category: .tts) {
            await performWarmUp()
        }
    }
    
    /// Internal warm-up implementation (separated for signpost measurement).
    ///
    /// Eagerly loads the preferred ML pipeline (~300-350MB) for fastest first
    /// synthesis. Starts the synthesis idle timer so the pipeline auto-releases
    /// after 30s if the user doesn't use TTS, returning memory to ~90-100MB.
    private func performWarmUp() async {
        #if DEBUG
        AppLogger.debug("Warming up Kokoro engine...", category: .tts)
        #endif

        // Reset background release flag
        _isReleasedForBackground = false
        
        // Cancel any pending idle timer â€" fresh warm-up should not be released
        cancelSynthesisIdleTimer()

        // Audio session pre-configuration and AVAudioPlayer pre-warming are no longer
        // needed — all audio routes through the unified AVAudioEngine via AudioPlayerService.
        // The engine is configured by AudioService.start() through AudioSessionController.

        do {
            try await kokoroEngine.warmUp()
            _isKokoroReady = true
            
            #if DEBUG
            AppLogger.debug("Kokoro engine ready", category: .tts)
            #endif
            
            // Start idle timer â€” if no synthesis occurs within 30s, the pipeline
            // auto-releases to free ~300-350MB. This makes the eager warm-up
            // self-correcting: instant TTS if needed, minimal memory if not.
            resetSynthesisIdleTimer()
            
            // Post notification that Kokoro is ready
            NotificationCenter.default.post(
                name: Constants.NotificationNames.kokoroTTSReady,
                object: nil
            )
            
        } catch {
            _isKokoroReady = false
            
            #if DEBUG
            AppLogger.debug("Kokoro warm-up failed, will use System TTS fallback", category: .tts, context: ["error": error])
            #endif
        }
    }
    
    func retryKokoroInitialization() async {
        #if DEBUG
        AppLogger.debug("Retrying Kokoro initialization...", category: .tts)
        #endif

        // Reset state
        _isKokoroReady = false
        _isReleasedForBackground = false

        // Create a fresh engine instance
        kokoroEngine = KokoroTTSEngine()
        
        // Attempt warm-up again
        await warmUp()
    }
    
    // MARK: - Synthesis Methods
    
    func synthesize(
        text: String,
        voiceId: String?,
        speed: Float,
        pitchShiftSemitones: Float,
        pitchRangeScale: Float
    ) async throws -> Data {
        // Measure synthesis time with signpost
        return try await AppLogger.measureAsync(AppLogger.SignpostName.ttsSynthesis, category: .tts) {
            try await performSynthesize(
                text: text,
                voiceId: voiceId,
                speed: speed,
                pitchShiftSemitones: pitchShiftSemitones,
                pitchRangeScale: pitchRangeScale
            )
        }
    }
    
    func synthesize(
        text: String,
        voiceId: String?,
        speed: Float,
        pitchShiftSemitones: Float,
        pitchRangeScale: Float,
        onChunkProgress: ((Int, Int) -> Void)?
    ) async throws -> Data {
        return try await AppLogger.measureAsync(AppLogger.SignpostName.ttsSynthesis, category: .tts) {
            try await performSynthesize(
                text: text,
                voiceId: voiceId,
                speed: speed,
                pitchShiftSemitones: pitchShiftSemitones,
                pitchRangeScale: pitchRangeScale,
                onChunkProgress: onChunkProgress
            )
        }
    }

    /// Internal synthesis implementation (separated for signpost measurement).
    private func performSynthesize(
        text: String,
        voiceId: String?,
        speed: Float,
        pitchShiftSemitones: Float,
        pitchRangeScale: Float,
        onChunkProgress: ((Int, Int) -> Void)? = nil
    ) async throws -> Data {
        #if DEBUG
        AppLogger.debug("Synthesizing", category: .tts, context: ["voiceId": voiceId ?? "nil", "speed": speed, "pitch": pitchShiftSemitones])
        #endif

        // Route based on voiceId
        if voiceId == TTSConfiguration.systemVoiceId {
            onChunkProgress?(1, 1)
            return try await systemTTS.synthesizeToData(text)
        }

        // Try Kokoro for nil, empty, or voice style IDs
        return try await synthesizeWithKokoro(
            text: text,
            voiceId: voiceId,
            speed: speed,
            pitchShiftSemitones: pitchShiftSemitones,
            pitchRangeScale: pitchRangeScale,
            onChunkProgress: onChunkProgress
        )
    }
    
    func synthesizeWithSystemTTS(text: String) async throws -> Data {
        #if DEBUG
        AppLogger.debug("Forcing System TTS", category: .tts)
        #endif
        
        return try await systemTTS.synthesizeToData(text)
    }
    
    // MARK: - Speaking Methods
    
    func speakText(
        _ text: String,
        voiceId: String?,
        speed: Float,
        pitchShiftSemitones: Float,
        pitchRangeScale: Float
    ) async throws {
        #if DEBUG
        AppLogger.debug("Speaking text", category: .tts, context: ["voiceId": voiceId ?? "nil", "speed": speed])
        #endif
        
        stopSpeaking()
        
        _isSpeaking = true
        defer { _isSpeaking = false }
        
        // Route based on voiceId
        if voiceId == TTSConfiguration.systemVoiceId {
            #if DEBUG
            AppLogger.debug("Routing to System TTS", category: .tts)
            #endif
            try await systemTTS.speak(text)
            return
        }
        
        // Try Kokoro for nil, empty, or voice style IDs
        try await speakWithKokoro(
            text: text,
            voiceId: voiceId,
            speed: speed,
            pitchShiftSemitones: pitchShiftSemitones,
            pitchRangeScale: pitchRangeScale
        )
    }
    
    func stopSpeaking() {
        // Stop unified engine playback
        audioPlayerService?.immediateStop()
        Task {
            await audioPlayerService?.cancelAndStop()
        }
        systemTTS.stopSpeaking()
        _isSpeaking = false
    }
    
    // MARK: - Memory Management
    
    /// Releases Kokoro ML pipelines to free memory when app enters background.
    ///
    /// This can free ~500MB-1GB of memory. After calling this method,
    /// `isKokoroReady` will return `false` and all synthesis will fall back
    /// to System TTS until `warmUp()` is called again.
    ///
    /// Call this when:
    /// - App enters background for extended period (>5 min)
    /// - iOS sends memory warning
    func releaseForBackground() async {
        guard !_isReleasedForBackground else {
            #if DEBUG
            AppLogger.debug("Already released for background", category: .tts)
            #endif
            return
        }
        
        #if DEBUG
        AppLogger.debug("Releasing Kokoro for background...", category: .tts)
        #endif

        // Stop any current playback
        stopSpeaking()
        
        // Cancel any pending pre-synthesis
        cancelPreSynthesis()
        
        // Cancel idle timer and clear suppression flag.
        // Without clearing _isIdleTimerSuppressed, the timer stays permanently
        // suppressed after foreground restore and pipelines never auto-release.
        cancelSynthesisIdleTimer()
        _isIdleTimerSuppressed = false

        // Release the Kokoro engine
        await kokoroEngine.releasePipelines()
        
        // Update state
        _isKokoroReady = false
        _isReleasedForBackground = true

        #if DEBUG
        AppLogger.debug("Kokoro released for background", category: .tts)
        #endif
    }
    
    /// Releases ML pipeline memory without disabling Kokoro.
    ///
    /// Frees ~800MB-1.5GB of CoreML prediction buffers cached inside
    /// `TTSPipeline` objects. Unlike `releaseForBackground()`, this keeps
    /// `isKokoroReady = true` so the next synthesis transparently reloads
    /// the pipeline via `ensurePipeline()` lazy loading.
    ///
    /// Call from `showSessionSummary()` to free memory when the user
    /// no longer needs active synthesis.
    func releasePipelineMemory() async {
        #if DEBUG
        AppLogger.debug("Releasing pipeline memory (session cleanup)...", category: .tts)
        #endif
        
        // Cancel any pending pre-synthesis (no longer needed)
        cancelPreSynthesis()
        
        // Cancel idle timer â€” explicit release supersedes timer
        cancelSynthesisIdleTimer()
        
        // Release ML pipelines but keep Kokoro logically "ready"
        // ensurePipeline() will reload on-demand during next session preparation
        await kokoroEngine.releasePipelines()
        
        // NOTE: We intentionally do NOT set _isKokoroReady = false
        // or _isReleasedForBackground = true. Kokoro stays "ready"
        // and the pipeline will lazy-load on next synthesis call.
        
        #if DEBUG
        AppLogger.debug("Pipeline memory released (Kokoro still marked ready)", category: .tts)
        #endif
    }

    // MARK: - Idle Timer Control
    
    func suppressSynthesisIdleTimer() {
        _isIdleTimerSuppressed = true
        cancelSynthesisIdleTimer()
        
        #if DEBUG
        AppLogger.debug("Idle timer suppressed (active session)", category: .tts)
        #endif
    }
    
    func resumeSynthesisIdleTimer() {
        _isIdleTimerSuppressed = false
        resetSynthesisIdleTimer()
        
        #if DEBUG
        AppLogger.debug("Idle timer resumed", category: .tts)
        #endif
    }
    
    // MARK: - Synthesis Idle Timer
    
    /// Resets the idle timer after a Kokoro synthesis completes.
    ///
    /// Each call cancels any existing timer and starts a new countdown.
    /// If no new synthesis occurs within `synthesisIdleTimeout`, the pipeline
    /// memory is automatically released via `releasePipelineMemory()`.
    ///
    /// This ensures all synthesis consumers (session, voice preview, onboarding)
    /// benefit from automatic cleanup without explicit per-view teardown.
    private func resetSynthesisIdleTimer() {
        // Skip timer reset while session is active — pipeline must stay warm
        guard !_isIdleTimerSuppressed else { return }
        
        synthesisIdleTimer?.cancel()
        
        let timeout = synthesisIdleTimeout
        synthesisIdleTimer = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(timeout))
                await self?.handleSynthesisIdleTimeout()
            } catch {
                // Task was cancelled â€” new synthesis started or explicit cleanup occurred
            }
        }
    }
    
    /// Cancels the idle timer without releasing memory.
    ///
    /// Call when:
    /// - Synthesis is starting (prevent premature release during active use)
    /// - Explicit cleanup occurs (prevent redundant double-release)
    /// - Warm-up begins (prevent releasing freshly loaded pipeline)
    private func cancelSynthesisIdleTimer() {
        synthesisIdleTimer?.cancel()
        synthesisIdleTimer = nil
    }
    
    /// Handles idle timeout by performing unified memory cleanup.
    ///
    /// Performs the same cleanup as session end to ensure consistent memory
    /// floor (~90-100MB) regardless of which path triggers release:
    /// - Cancels any in-flight pre-synthesis task (may hold WAV Data)
    /// - Releases ML pipelines (~300-350MB weights + ~500MB-1GB prediction buffers)
    /// - Keeps `isKokoroReady = true` so next synthesis transparently reloads
    private func handleSynthesisIdleTimeout() async {
        #if DEBUG
        AppLogger.debug("Synthesis idle timeout — releasing pipeline memory", category: .tts, context: ["timeoutSeconds": synthesisIdleTimeout])
        #endif
        
        // Cancel any lingering pre-synthesis (may hold WAV data in memory)
        cancelPreSynthesis()
        
        // Release ML pipelines (the main memory savings)
        await kokoroEngine.releasePipelines()
        
        #if DEBUG
        AppLogger.debug("Pipeline memory released via idle timeout (Kokoro still marked ready)", category: .tts)
        #endif
    }
    
    // MARK: - Pre-Synthesis
    
    func preSynthesize(
        text: String,
        voiceId: String?,
        speed: Float,
        pitchShiftSemitones: Float,
        pitchRangeScale: Float
    ) async {
        #if DEBUG
        AppLogger.debug("Pre-synthesizing", category: .tts, context: ["voice": voiceId ?? "default"])
        #endif
        
        // Cancel any existing pre-synthesis
        preSynthesisTask?.cancel()
        
        // Synthesize in background (result is cached automatically by the engine/cache manager)
        preSynthesisTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.synthesize(
                    text: text,
                    voiceId: voiceId,
                    speed: speed,
                    pitchShiftSemitones: pitchShiftSemitones,
                    pitchRangeScale: pitchRangeScale
                )
                #if DEBUG
                AppLogger.debug("Pre-synthesis complete", category: .tts)
                #endif
            } catch {
                #if DEBUG
                AppLogger.debug("Pre-synthesis failed", category: .tts, context: ["error": error])
                #endif
            }
        }
    }
    
    func cancelPreSynthesis() {
        preSynthesisTask?.cancel()
        preSynthesisTask = nil
    }
    
    // (Audio session pre-configuration, AVAudioPlayer pre-warming, and ensureAudioSessionActive
    // have been removed — all audio now routes through the unified AVAudioEngine via
    // AudioPlayerService. Session configuration is handled by AudioService/AudioSessionController.)
    
    // MARK: - Kokoro Synthesis
    
    private func synthesizeWithKokoro(
        text: String,
        voiceId: String?,
        speed: Float,
        pitchShiftSemitones: Float,
        pitchRangeScale: Float,
        onChunkProgress: ((Int, Int) -> Void)? = nil
    ) async throws -> Data {
        guard _isKokoroReady else {
            #if DEBUG
            AppLogger.debug("Kokoro not ready, falling back to System TTS", category: .tts)
            #endif
            onChunkProgress?(1, 1)
            return try await systemTTS.synthesizeToData(text)
        }

        // Resolve voice style
        let voiceStyle = resolveVoiceStyle(voiceId: voiceId)

        #if DEBUG
        AppLogger.debug("Resolved voice style", category: .tts, context: ["voiceStyle": voiceStyle.rawValue, "speed": speed, "pitch": pitchShiftSemitones])
        #endif

        // Cancel idle timer — Kokoro synthesis is starting
        cancelSynthesisIdleTimer()

        do {
            let audioData = try await kokoroEngine.synthesizeToData(
                text: text,
                voiceStyle: voiceStyle,
                speed: speed,
                pitchShiftSemitones: pitchShiftSemitones,
                pitchRangeScale: pitchRangeScale,
                onChunkProgress: onChunkProgress
            )

            // Reset idle timer — synthesis complete, start countdown
            resetSynthesisIdleTimer()

            return audioData
        } catch {
            // Reset timer even on failure — pipeline was loaded and has buffers
            resetSynthesisIdleTimer()

            #if DEBUG
            AppLogger.debug("Kokoro synthesis failed, falling back to System TTS", category: .tts, context: ["error": error])
            #endif
            onChunkProgress?(1, 1)
            return try await systemTTS.synthesizeToData(text)
        }
    }
    
    private func speakWithKokoro(
        text: String,
        voiceId: String?,
        speed: Float,
        pitchShiftSemitones: Float,
        pitchRangeScale: Float
    ) async throws {
        #if DEBUG
        AppLogger.debug("Speaking with Kokoro", category: .tts, context: ["voiceId": voiceId ?? "nil", "speed": speed])
        #endif
        
        guard _isKokoroReady else {
            #if DEBUG
            AppLogger.debug("Kokoro not ready, falling back to System TTS", category: .tts)
            #endif
            try await systemTTS.speak(text)
            return
        }
        
        // Resolve voice style
        let voiceStyle = resolveVoiceStyle(voiceId: voiceId)
        
        #if DEBUG
        AppLogger.debug("Resolved voice style", category: .tts, context: ["voiceStyle": voiceStyle.rawValue])
        #endif

        // Cancel idle timer — Kokoro synthesis is starting
        cancelSynthesisIdleTimer()
        
        do {
            let audioData = try await kokoroEngine.synthesizeToData(
                text: text,
                voiceStyle: voiceStyle,
                speed: speed,
                pitchShiftSemitones: pitchShiftSemitones,
                pitchRangeScale: pitchRangeScale
            )
            
            // Reset idle timer â€” synthesis complete, start countdown
            resetSynthesisIdleTimer()
            
            #if DEBUG
            AppLogger.debug("Kokoro synthesis complete, playing audio", category: .tts, context: ["bytes": audioData.count])
            #endif
            
            try await playAudioData(audioData)
            
        } catch {
            // Reset timer even on failure â€” pipeline was loaded and has buffers
            resetSynthesisIdleTimer()
            
            #if DEBUG
            AppLogger.debug("Kokoro playback failed, falling back to System TTS", category: .tts, context: ["error": error])
            #endif
            try await systemTTS.speak(text)
        }
    }
    
    // MARK: - Voice Style Resolution
    
    /// Resolves a voice ID string to a Kokoro VoiceStyle.
    ///
    /// Handles both formats:
    /// - Raw: "af_heart", "am_adam"
    /// - Full: "kokoro_af_heart", "kokoro_am_adam"
    ///
    /// - Parameter voiceId: Voice ID in either format
    /// - Returns: The corresponding VoiceStyle, or .afHeart as default
    private func resolveVoiceStyle(voiceId: String?) -> VoiceStyle {
        guard let voiceId = voiceId, !voiceId.isEmpty else {
            #if DEBUG
            AppLogger.debug("resolveVoiceStyle: nil/empty -> default af_heart", category: .tts)
            #endif
            return .afHeart // Default voice
        }
        
        // Voice ID should match VoiceStyle.rawValue directly (e.g., "af_heart")
        if let voiceStyle = VoiceStyle(rawValue: voiceId) {
            #if DEBUG
            AppLogger.debug("resolveVoiceStyle: matched", category: .tts, context: ["input": voiceId, "resolved": voiceStyle.rawValue])
            #endif
            return voiceStyle
        }
        
        // Legacy support: remove "kokoro_" prefix if present
        if voiceId.hasPrefix(TTSConfiguration.kokoroPrefix) {
            let styleString = String(voiceId.dropFirst(TTSConfiguration.kokoroPrefix.count))
            if let voiceStyle = VoiceStyle(rawValue: styleString) {
                #if DEBUG
                AppLogger.debug("resolveVoiceStyle: legacy prefix matched", category: .tts, context: ["input": voiceId, "resolved": voiceStyle.rawValue])
                #endif
                return voiceStyle
            }
        }
        
        #if DEBUG
        AppLogger.debug("resolveVoiceStyle: not found, using default af_heart", category: .tts, context: ["input": voiceId])
        #endif
        return .afHeart
    }
    
    // MARK: - Audio Playback

    /// Plays audio data through the unified engine via AudioPlayerService.
    ///
    /// Routes TTS audio through the same `AVAudioEngine` as background music,
    /// eliminating the dual-render-client contention (AVAudioPlayer vs AVAudioEngine)
    /// that caused static/glitch on first TTS playback.
    private func playAudioData(_ data: Data) async throws {
        // Measure playback with signpost
        let signpostID = AppLogger.makeSignpostID(for: .tts)
        AppLogger.beginInterval(AppLogger.SignpostName.ttsPlayback, id: signpostID, category: .tts)

        defer {
            AppLogger.endInterval(AppLogger.SignpostName.ttsPlayback, id: signpostID, category: .tts)
        }

        // Ensure engine is running (AudioService owns session configuration)
        if let audioService, !audioService.isRunning {
            try await audioService.start()
        }

        guard let audioPlayerService else {
            throw AppError.ttsError("Audio player service not available — cannot play TTS")
        }

        try await audioPlayerService.playRawPCMData(data, sampleRate: 24000)
    }
}
#endif
