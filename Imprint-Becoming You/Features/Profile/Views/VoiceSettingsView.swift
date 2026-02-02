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
/// - Tap to select voice (pending selection until Save is tapped)
/// - Tap play button to preview voice
/// - Tap gear icon on selected voice to customize settings
/// - Save button appears only when selection differs from saved voice
/// - Shows engine status (Kokoro ready / System fallback)
/// - Groups voices by accent and gender
/// - Responsive cancellation on rapid tap-through
///
/// ## Navigation
/// This view is pushed onto the Profile navigation stack.
/// Uses standard back navigation via the navigation bar.
/// Gear icon pushes to `VoiceModificationView` for voice customization.
struct VoiceSettingsView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dependencies) private var dependencies
    @Environment(\.appState) private var appState
    
    // MARK: - State
    
    /// The voice ID that was saved when the view appeared (the "committed" selection)
    @State private var originalVoiceId: String = Voice.defaultVoice.id
    
    /// Currently selected voice ID (pending selection, not yet saved)
    @State private var selectedVoiceId: String = Voice.defaultVoice.id
    
    /// Voice currently being previewed (by full Voice.id)
    @State private var previewingVoiceId: String?
    
    /// Current playback state for the previewing voice
    @State private var playbackState: VoiceChipPlaybackState = .idle
    
    /// Whether Kokoro engine is ready
    @State private var isKokoroReady = false
    
    /// Audio player for preview playback
    @State private var audioPlayer: AVAudioPlayer?
    
    /// Voice selected for modification (triggers navigation)
    @State private var voiceForModification: Voice?
    
    /// Set of voice IDs that have custom settings (for indicator dots)
    @State private var voicesWithCustomSettings: Set<String> = []
    
    // MARK: - Computed Properties
    
    /// Whether the user has made a change that differs from the saved voice
    private var hasUnsavedChanges: Bool {
        selectedVoiceId != originalVoiceId
    }
    
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if hasUnsavedChanges {
                    Button("Save") {
                        saveVoiceSelection()
                    }
                    .foregroundStyle(AppColors.accent)
                    .accessibilityLabel("Save voice selection")
                    .accessibilityHint("Saves \(Voice.voice(forId: selectedVoiceId).name) as your voice")
                }
            }
        }
        .navigationDestination(item: $voiceForModification) { voice in
            VoiceModificationView(voice: voice) { _ in
                // Refresh custom settings state when returning
                refreshCustomSettingsState()
            }
        }
        .onAppear {
            loadCurrentVoice()
            checkEngineStatus()
            refreshCustomSettingsState()
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
        let selectedVoice = Voice.voice(forId: selectedVoiceId)
        
        return VStack(spacing: AppTheme.Spacing.sm) {
            Text(hasUnsavedChanges ? "Selected Voice" : "Current Voice")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
            
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.accent)
                
                Text(selectedVoice.displayNameWithDefault)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                
                // Custom settings indicator
                if voicesWithCustomSettings.contains(selectedVoiceId) {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 10))
                        Text("Tuned")
                            .font(AppTypography.caption2)
                    }
                    .foregroundStyle(AppColors.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(AppColors.accent.opacity(0.15))
                    )
                }
            }
            
            Text(hasUnsavedChanges ? "Tap Save to confirm your selection" : "Tap a voice to select, tap play to preview")
                .font(AppTypography.caption1)
                .foregroundStyle(hasUnsavedChanges ? AppColors.accent : AppColors.textTertiary)
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
                        hasCustomSettings: voicesWithCustomSettings.contains(voice.id),
                        playbackState: playbackStateFor(voice),
                        onPlayTapped: { handlePlayTapped(voice) },
                        onSelectTapped: { handleSelectTapped(voice) },
                        onSettingsTapped: selectedVoiceId == voice.id ? { handleSettingsTapped(voice) } : nil
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
            // Already selected - do nothing
            return
        }
        
        // Update pending selection (does NOT save until Save button is tapped)
        selectedVoiceId = voice.id
        
        #if DEBUG
        print("VoiceSettingsView: Pending selection \(voice.id)")
        #endif
    }
    
    private func handleSettingsTapped(_ voice: Voice) {
        #if DEBUG
        print("VoiceSettingsView: Opening settings for \(voice.id)")
        #endif
        
        // Stop any preview before navigating
        stopPreview()
        
        // Navigate to modification view
        voiceForModification = voice
    }
    
    // MARK: - Preview Playback
    
    private func playPreview(for voice: Voice) {
        // Get raw TTS voice ID
        guard let ttsVoiceId = voice.ttsVoiceId else {
            #if DEBUG
            print("VoiceSettingsView: Could not get ttsVoiceId for \(voice.id)")
            #endif
            return
        }
        
        // Set state
        previewingVoiceId = voice.id
        playbackState = .synthesizing
        
        // Capture for async closure
        let capturedVoiceId = voice.id
        let capturedTtsVoiceId = ttsVoiceId
        
        // Get voice settings for preview
        let settings = VoiceSettingsManager.shared.settings(for: voice.id)
        
        Task { @MainActor in
            // Verify still previewing this voice
            guard previewingVoiceId == capturedVoiceId else { return }
            
            do {
                #if DEBUG
                print("VoiceSettingsView: Synthesizing \(capturedTtsVoiceId) with settings: speed=\(settings.speed), pitch=\(settings.pitchShiftSemitones), range=\(settings.pitchRangeScale)")
                #endif
                
                // Use custom settings for preview
                let audioData = try await dependencies.ttsService.synthesize(
                    text: Voice.previewPhrase,
                    voiceId: capturedTtsVoiceId,
                    speed: settings.speed,
                    pitchShiftSemitones: settings.pitchShiftFloat,
                    pitchRangeScale: settings.pitchRangeScale
                )
                
                // Verify still previewing same voice
                guard previewingVoiceId == capturedVoiceId else { return }
                
                // Transition to playing
                playbackState = .playing
                try playAudioData(audioData)
                
            } catch is CancellationError {
                #if DEBUG
                print("VoiceSettingsView: Synthesis cancelled for \(capturedTtsVoiceId)")
                #endif
            } catch {
                #if DEBUG
                print("VoiceSettingsView: Preview failed for \(capturedTtsVoiceId): \(error)")
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
        print("VoiceSettingsView: Playing audio (\(data.count) bytes)")
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
            originalVoiceId = voiceId
            selectedVoiceId = voiceId
        }
    }
    
    private func saveVoiceSelection() {
        appState.userProfile?.selectedVoiceId = selectedVoiceId
        try? modelContext.save()
        
        // Update original to match - no longer has unsaved changes
        originalVoiceId = selectedVoiceId
        
        #if DEBUG
        print("VoiceSettingsView: Saved voice \(selectedVoiceId)")
        #endif
    }
    
    private func checkEngineStatus() {
        Task {
            await dependencies.ttsService.warmUp()
            await MainActor.run {
                isKokoroReady = dependencies.ttsService.isKokoroReady
            }
        }
    }
    
    private func refreshCustomSettingsState() {
        voicesWithCustomSettings = Set(VoiceSettingsManager.shared.voiceIdsWithCustomSettings())
        
        #if DEBUG
        print("VoiceSettingsView: \(voicesWithCustomSettings.count) voices have custom settings")
        #endif
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
