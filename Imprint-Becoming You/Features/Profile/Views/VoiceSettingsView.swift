//
//  VoiceSettingsView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/25/26.
//

import SwiftUI
import SwiftData
import AVFoundation

// MARK: - Voice Settings View

/// Voice selection view pushed from Profile settings.
///
/// Features:
/// - Tap to select voice (selection is separate from preview)
/// - Tap play button to preview voice
/// - Shows engine status (Kokoro ready / System fallback)
/// - Groups voices by accent and gender
/// - Responsive cancellation on rapid tap-through
///
/// ## Navigation
/// This view is pushed onto the Profile navigation stack.
/// Uses standard back navigation via the navigation bar.
struct VoiceSettingsView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dependencies) private var dependencies
    @Environment(\.appState) private var appState
    
    // MARK: - State
    
    /// Currently selected voice ID (full Voice.id format)
    @State private var selectedVoiceId: String = Voice.defaultVoice.id
    
    /// Voice currently being previewed (by full Voice.id)
    @State private var previewingVoiceId: String?
    
    /// Current playback state for the previewing voice
    @State private var playbackState: VoiceChipPlaybackState = .idle
    
    /// Whether Kokoro engine is ready
    @State private var isKokoroReady = false
    
    /// Audio player for preview playback
    @State private var audioPlayer: AVAudioPlayer?
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Engine status
                engineStatusBanner
                
                // Current voice display
                currentVoiceHeader
                
                // Voice list
                ScrollView {
                    voiceListContent
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.bottom, AppTheme.Spacing.xl)
                }
            }
        }
        .navigationTitle("Voice Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadCurrentVoice()
            checkEngineStatus()
        }
        .onDisappear {
            stopPreview()
        }
    }
    
    // MARK: - Engine Status Banner
    
    private var engineStatusBanner: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: isKokoroReady ? "checkmark.circle.fill" : "info.circle.fill")
                .foregroundStyle(isKokoroReady ? AppColors.success : AppColors.textSecondary)
            
            Text(isKokoroReady ? "Neural voice ready" : "Using system voice")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
            
            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppColors.backgroundSecondary)
    }
    
    // MARK: - Current Voice Header
    
    private var currentVoiceHeader: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Text("Current Voice")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
            
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.accent)
                
                Text(Voice.voice(forId: selectedVoiceId).displayNameWithDefault)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
            }
            
            Text("Tap a voice to select, tap play to preview")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(.vertical, AppTheme.Spacing.lg)
    }
    
    // MARK: - Voice List Content
    
    private var voiceListContent: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            ForEach(Voice.englishVoicesByDisplayGroup, id: \.group) { groupData in
                voiceGroupSection(group: groupData.group, voices: groupData.voices)
            }
        }
    }
    
    // MARK: - Voice Group Section
    
    private func voiceGroupSection(group: VoiceDisplayGroup, voices: [Voice]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // Group header
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: group.iconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                
                Text(group.displayName)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.leading, AppTheme.Spacing.xs)
            
            // Voice chips
            VStack(spacing: AppTheme.Spacing.sm) {
                ForEach(voices) { voice in
                    VoiceChip(
                        voice: voice,
                        isSelected: selectedVoiceId == voice.id,
                        playbackState: playbackStateFor(voice),
                        onPlayTapped: { handlePlayTapped(voice) },
                        onSelectTapped: { handleSelectTapped(voice) }
                    )
                }
            }
        }
    }
    
    // MARK: - Playback State
    
    private func playbackStateFor(_ voice: Voice) -> VoiceChipPlaybackState {
        guard previewingVoiceId == voice.id else { return .idle }
        return playbackState
    }
    
    // MARK: - Actions
    
    private func handlePlayTapped(_ voice: Voice) {
        // If this voice is already playing, stop it
        if previewingVoiceId == voice.id && playbackState == .playing {
            stopPreview()
            return
        }
        
        // Cancel any in-flight synthesis
        dependencies.voicePreviewCacheService.cancelSynthesis()
        stopAudioPlayback()
        
        // Start preview for this voice
        playPreview(for: voice)
    }
    
    private func handleSelectTapped(_ voice: Voice) {
        // Toggle selection
        if selectedVoiceId == voice.id {
            // Already selected - do nothing (or could deselect)
            return
        }
        
        // Select new voice
        selectedVoiceId = voice.id
        saveVoiceSelection(voice.id)
        
        #if DEBUG
        print("🎤 VoiceSettingsView: Selected voice \(voice.id)")
        #endif
    }
    
    // MARK: - Preview Playback
    
    private func playPreview(for voice: Voice) {
        // Get raw TTS voice ID
        guard let ttsVoiceId = voice.ttsVoiceId else {
            #if DEBUG
            print("⚠️ VoiceSettingsView: Could not get ttsVoiceId for \(voice.id)")
            #endif
            return
        }
        
        // Set state
        previewingVoiceId = voice.id
        playbackState = .synthesizing
        
        // Capture for async closure
        let capturedVoiceId = voice.id
        let capturedTtsVoiceId = ttsVoiceId
        
        Task { @MainActor in
            // Verify still previewing this voice
            guard previewingVoiceId == capturedVoiceId else { return }
            
            do {
                let service = dependencies.voicePreviewCacheService
                
                #if DEBUG
                print("🎤 VoiceSettingsView: Synthesizing \(capturedTtsVoiceId)")
                #endif
                
                let audioData = try await service.synthesizePreview(voiceId: capturedTtsVoiceId)
                
                // Verify still previewing same voice
                guard previewingVoiceId == capturedVoiceId else { return }
                
                // Transition to playing
                playbackState = .playing
                try playAudioData(audioData)
                
            } catch is CancellationError {
                #if DEBUG
                print("🎤 VoiceSettingsView: Synthesis cancelled for \(capturedTtsVoiceId)")
                #endif
            } catch {
                #if DEBUG
                print("⚠️ VoiceSettingsView: Preview failed for \(capturedTtsVoiceId): \(error)")
                #endif
            }
            
            // Only clear state if still on this voice and synthesis failed/cancelled
            if previewingVoiceId == capturedVoiceId && playbackState == .synthesizing {
                previewingVoiceId = nil
                playbackState = .idle
            }
        }
    }
    
    private func playAudioData(_ data: Data) throws {
        // Stop any existing playback
        stopAudioPlayback()
        
        // Configure audio session
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try session.setActive(true)
        
        // Create and play
        audioPlayer = try AVAudioPlayer(data: data)
        audioPlayer?.delegate = AudioPlayerDelegateHandler.shared
        audioPlayer?.prepareToPlay()
        
        // Set up completion handler
        AudioPlayerDelegateHandler.shared.onFinished = { [weak audioPlayer] in
            if self.audioPlayer === audioPlayer {
                self.previewingVoiceId = nil
                self.playbackState = .idle
            }
        }
        
        guard audioPlayer?.play() == true else {
            throw AppError.ttsError("Failed to start audio playback")
        }
        
        #if DEBUG
        print("🎤 VoiceSettingsView: Playing audio (\(data.count) bytes)")
        #endif
    }
    
    private func stopPreview() {
        dependencies.voicePreviewCacheService.cancelSynthesis()
        stopAudioPlayback()
        previewingVoiceId = nil
        playbackState = .idle
    }
    
    private func stopAudioPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        dependencies.ttsService.stopSpeaking()
    }
    
    // MARK: - Persistence
    
    private func loadCurrentVoice() {
        if let voiceId = appState.userProfile?.selectedVoiceId, !voiceId.isEmpty {
            selectedVoiceId = voiceId
        }
    }
    
    private func saveVoiceSelection(_ voiceId: String) {
        appState.userProfile?.selectedVoiceId = voiceId
        try? modelContext.save()
    }
    
    private func checkEngineStatus() {
        Task {
            await dependencies.ttsService.warmUp()
            await MainActor.run {
                isKokoroReady = dependencies.ttsService.isKokoroReady
            }
        }
    }
}

// MARK: - Audio Player Delegate Handler

/// Shared delegate handler for AVAudioPlayer completion callbacks.
private class AudioPlayerDelegateHandler: NSObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayerDelegateHandler()
    
    var onFinished: (() -> Void)?
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.onFinished?()
            self.onFinished = nil
        }
    }
}

// MARK: - Previews

#Preview("Voice Settings") {
    NavigationStack {
        VoiceSettingsView()
    }
    .previewEnvironment()
}
