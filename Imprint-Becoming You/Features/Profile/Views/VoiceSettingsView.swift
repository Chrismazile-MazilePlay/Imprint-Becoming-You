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
/// - Tap to select and preview voice (auto-saves)
/// - Shows engine status (Kokoro ready / System fallback)
/// - Groups voices by accent and gender
/// - On-demand synthesis with central loading indicator
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
    
    /// Voice currently being previewed
    @State private var previewingVoiceId: String?
    
    /// Whether synthesis is in progress (shows loading overlay)
    @State private var isSynthesizing = false
    
    /// Whether preview is playing
    @State private var isPreviewPlaying = false
    
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
            
            // Central loading overlay (non-blocking)
            loadingOverlay
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
    
    // MARK: - Loading Overlay
    
    @ViewBuilder
    private var loadingOverlay: some View {
        if isSynthesizing {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            
            ProgressView()
                .scaleEffect(1.5)
                .tint(AppColors.accent)
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
            
            Text("Tap any voice to select and preview")
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
            FlowLayout(spacing: AppTheme.Spacing.sm) {
                ForEach(voices) { voice in
                    voiceChip(voice: voice)
                }
            }
        }
    }
    
    // MARK: - Voice Chip
    
    private func voiceChip(voice: Voice) -> some View {
        let isSelected = selectedVoiceId == voice.id
        let isPreviewing = previewingVoiceId == voice.id && isPreviewPlaying
        
        return Button {
            selectVoice(voice.id)
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                // Voice name
                Text(voice.displayNameWithDefault)
                    .font(AppTypography.body)
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.textPrimary)
                
                // Status indicator
                Group {
                    if isPreviewing {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.accent)
                            .symbolEffect(.pulse, options: .repeating)
                    } else if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.accent)
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? AppColors.accent.opacity(0.15) : AppColors.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? AppColors.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(voice.name) voice")
        .accessibilityHint(isSelected ? "Selected. Tap to preview" : "Tap to select and preview")
    }
    
    // MARK: - Voice Selection
    
    private func selectVoice(_ voiceId: String) {
        // Cancel any in-flight synthesis
        dependencies.voicePreviewCacheService.cancelSynthesis()
        
        // Stop current playback
        stopPreview()
        
        // Select and save
        selectedVoiceId = voiceId
        saveVoiceSelection(voiceId)
        
        // Play preview (no haptics)
        playPreview(for: voiceId)
        
        #if DEBUG
        print("🎤 VoiceSettingsView: Selected voice \(voiceId)")
        #endif
    }
    
    private func playPreview(for voiceId: String) {
        // Get raw TTS voice ID
        guard let ttsVoiceId = Voice.ttsVoiceId(from: voiceId) else {
            #if DEBUG
            print("⚠️ VoiceSettingsView: Could not get ttsVoiceId for \(voiceId)")
            #endif
            return
        }
        
        // Set preview state BEFORE async work
        previewingVoiceId = voiceId
        isSynthesizing = true
        
        // Capture values for closure
        let capturedVoiceId = voiceId
        let capturedTtsVoiceId = ttsVoiceId
        
        Task { @MainActor in
            // Verify we're still previewing this voice
            guard previewingVoiceId == capturedVoiceId else { return }
            
            do {
                let service = dependencies.voicePreviewCacheService
                
                // Synthesize on-demand (with auto-retry)
                #if DEBUG
                print("🎤 VoiceSettingsView: Synthesizing \(capturedTtsVoiceId)")
                #endif
                let audioData = try await service.synthesizePreview(voiceId: capturedTtsVoiceId)
                
                // Hide loading
                isSynthesizing = false
                
                // Verify still previewing same voice
                guard previewingVoiceId == capturedVoiceId else { return }
                
                // Play audio
                isPreviewPlaying = true
                try playAudioData(audioData)
                
            } catch is CancellationError {
                // User tapped another voice - this is expected
                #if DEBUG
                print("🎤 VoiceSettingsView: Synthesis cancelled for \(capturedTtsVoiceId)")
                #endif
            } catch {
                #if DEBUG
                print("⚠️ VoiceSettingsView: Voice preview failed for \(capturedTtsVoiceId): \(error)")
                #endif
            }
            
            // Clear synthesis state
            isSynthesizing = false
            
            // Clear preview state if still previewing same voice
            if previewingVoiceId == capturedVoiceId {
                isPreviewPlaying = false
                previewingVoiceId = nil
            }
        }
    }
    
    private func playAudioData(_ data: Data) throws {
        // Stop any existing playback
        audioPlayer?.stop()
        audioPlayer = nil
        
        // Configure audio session
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try session.setActive(true)
        
        // Create and play
        audioPlayer = try AVAudioPlayer(data: data)
        audioPlayer?.prepareToPlay()
        
        guard audioPlayer?.play() == true else {
            throw AppError.ttsError("Failed to start audio playback")
        }
        
        #if DEBUG
        print("🎤 VoiceSettingsView: Playing audio (\(data.count) bytes)")
        #endif
    }
    
    private func stopPreview() {
        audioPlayer?.stop()
        audioPlayer = nil
        dependencies.ttsService.stopSpeaking()
        dependencies.voicePreviewCacheService.cancelSynthesis()
        isSynthesizing = false
        isPreviewPlaying = false
        previewingVoiceId = nil
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

// MARK: - Previews

#Preview("Voice Settings") {
    NavigationStack {
        VoiceSettingsView()
    }
    .previewEnvironment()
}
