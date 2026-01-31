//
//  TTSTestView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/24/26.
//

import SwiftUI
import iOS_TTS

// MARK: - TTS Test View

/// Temporary test view for verifying Kokoro TTS integration.
///
/// This view allows manual testing of:
/// - Kokoro warm-up status
/// - Voice selection from available voices
/// - Speech synthesis and playback
/// - System TTS fallback behavior
///
/// ## Usage
/// Navigate here from Profile > Voice Profile to test TTS before
/// connecting to PracticeStore.
///
/// - Note: This is a development/testing view. It will be replaced with
///   a production-ready Voice Selection UI after verification.
struct TTSTestView: View {
    
    // MARK: - Environment
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var dependencies
    
    // MARK: - State
    
    @State private var selectedVoiceId: String = "af_heart"
    @State private var testText: String = "I am confident, capable, and worthy of success."
    @State private var isSpeaking: Bool = false
    @State private var isKokoroReady: Bool = false
    @State private var statusMessage: String = "Checking Kokoro status..."
    @State private var lastSynthesisTime: TimeInterval = 0
    @State private var usedEngine: String = ""
    
    // Voice categories for picker - using VoiceStyle.rawValue format (snake_case)
    private let voiceCategories: [(name: String, voices: [(id: String, name: String)])] = [
        ("American Female", [
            ("af_heart", "Heart (Default)"),
            ("af_alloy", "Alloy"),
            ("af_aoede", "Aoede"),
            ("af_bella", "Bella"),
            ("af_jessica", "Jessica"),
            ("af_kore", "Kore"),
            ("af_nicole", "Nicole"),
            ("af_nova", "Nova"),
            ("af_river", "River"),
            ("af_sarah", "Sarah"),
            ("af_sky", "Sky")
        ]),
        ("American Male", [
            ("am_adam", "Adam"),
            ("am_echo", "Echo"),
            ("am_eric", "Eric"),
            ("am_fenrir", "Fenrir"),
            ("am_liam", "Liam"),
            ("am_michael", "Michael"),
            ("am_onyx", "Onyx"),
            ("am_puck", "Puck"),
            ("am_santa", "Santa")
        ]),
        ("British Female", [
            ("bf_alice", "Alice"),
            ("bf_emma", "Emma"),
            ("bf_isabella", "Isabella"),
            ("bf_lily", "Lily")
        ]),
        ("British Male", [
            ("bm_daniel", "Daniel"),
            ("bm_fable", "Fable"),
            ("bm_george", "George"),
            ("bm_lewis", "Lewis")
        ]),
        ("System", [
            ("system", "System TTS (Fallback)")
        ])
    ]
    
    // MARK: - Body
    
    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xl) {
                // Status Section
                statusSection
                
                // Voice Selection
                voiceSelectionSection
                
                // Test Text Input
                testTextSection
                
                // Playback Controls
                playbackSection
                
                // Results
                resultsSection
                
                Spacer(minLength: AppTheme.Spacing.xxl)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.top, AppTheme.Spacing.lg)
        }
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("TTS Test")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") {
                    dismiss()
                }
                .foregroundStyle(AppColors.accent)
                .accessibilityLabel("Close")
                .accessibilityHint("Return to voice settings")
            }
        }
        .task {
            await checkKokoroStatus()
        }
    }
    
    // MARK: - Status Section
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            sectionHeader("ENGINE STATUS")
            
            HStack(spacing: AppTheme.Spacing.md) {
                // Status indicator
                Circle()
                    .fill(isKokoroReady ? AppColors.success : AppColors.warning)
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(isKokoroReady ? "Kokoro Ready" : "Kokoro Not Ready")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text(statusMessage)
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(isKokoroReady ? "Kokoro engine ready" : "Kokoro engine not ready")
                .accessibilityValue(statusMessage)
                
                Spacer()
                
                // Refresh button
                Button {
                    Task { await checkKokoroStatus() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppColors.accent)
                }
                .accessibilityLabel("Refresh status")
                .accessibilityHint("Check Kokoro engine status again")
            }
            .padding(AppTheme.Spacing.md)
            .background(AppColors.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
        }
    }
    
    // MARK: - Voice Selection Section
    
    private var voiceSelectionSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            sectionHeader("VOICE SELECTION")
            
            VStack(spacing: AppTheme.Spacing.sm) {
                ForEach(voiceCategories, id: \.name) { category in
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        Text(category.name)
                            .font(AppTypography.caption2)
                            .foregroundStyle(AppColors.textTertiary)
                            .padding(.leading, AppTheme.Spacing.sm)
                            .accessibilityAddTraits(.isHeader)
                        
                        FlowLayout(spacing: AppTheme.Spacing.xs) {
                            ForEach(category.voices, id: \.id) { voice in
                                voiceChip(id: voice.id, name: voice.name, category: category.name)
                            }
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.md)
            .background(AppColors.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
        }
    }
    
    private func voiceChip(id: String, name: String, category: String) -> some View {
        let isSelected = selectedVoiceId == id
        
        return Button {
            selectedVoiceId = id
            #if DEBUG
            print("🎤 TTSTestView: Selected voice: \(id)")
            #endif
        } label: {
            Text(name)
                .font(AppTypography.caption1)
                .foregroundStyle(isSelected ? AppColors.textInverted : AppColors.textPrimary)
                .padding(.horizontal, AppTheme.Spacing.sm)
                .padding(.vertical, AppTheme.Spacing.xs)
                .background(isSelected ? AppColors.accent : AppColors.surfaceTertiary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), \(category)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(isSelected ? "Currently selected voice" : "Double tap to select this voice")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    
    // MARK: - Test Text Section
    
    private var testTextSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            sectionHeader("TEST TEXT")
            
            VStack(spacing: AppTheme.Spacing.sm) {
                TextEditor(text: $testText)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80)
                    .padding(AppTheme.Spacing.sm)
                    .background(AppColors.surfaceTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small))
                    .accessibilityLabel("Test text input")
                    .accessibilityHint("Enter the text you want to hear spoken")
                
                // Quick test phrases
                HStack(spacing: AppTheme.Spacing.xs) {
                    quickPhraseButton("Short", "I am enough.")
                    quickPhraseButton("Medium", "I am confident, capable, and worthy of success.")
                    quickPhraseButton("Long", "Every day I am becoming stronger, wiser, and more aligned with my highest purpose. I trust the journey.")
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Quick phrase buttons")
            }
            .padding(AppTheme.Spacing.md)
            .background(AppColors.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
        }
    }
    
    private func quickPhraseButton(_ label: String, _ text: String) -> some View {
        Button {
            testText = text
        } label: {
            Text(label)
                .font(AppTypography.caption2)
                .foregroundStyle(AppColors.accent)
                .padding(.horizontal, AppTheme.Spacing.sm)
                .padding(.vertical, AppTheme.Spacing.xs)
                .background(AppColors.accent.opacity(0.1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) phrase")
        .accessibilityHint("Set test text to a \(label.lowercased()) example phrase")
    }
    
    // MARK: - Playback Section
    
    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            sectionHeader("PLAYBACK")
            
            HStack(spacing: AppTheme.Spacing.md) {
                // Speak button
                Button {
                    Task { await speak() }
                } label: {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        if isSpeaking {
                            ProgressView()
                                .tint(AppColors.textInverted)
                                .accessibilityHidden(true)
                        } else {
                            Image(systemName: "play.fill")
                                .accessibilityHidden(true)
                        }
                        Text(isSpeaking ? "Speaking..." : "Speak")
                    }
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textInverted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.md)
                    .background(isSpeaking ? AppColors.accent.opacity(0.6) : AppColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
                }
                .disabled(isSpeaking || testText.isEmpty)
                .buttonStyle(.plain)
                .accessibilityLabel(isSpeaking ? "Speaking" : "Speak")
                .accessibilityHint(isSpeaking ? "Audio is playing" : "Play the test text with the selected voice")
                .accessibilityValue(isSpeaking ? "In progress" : "Ready")
                
                // Stop button
                Button {
                    stopSpeaking()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.error)
                        .frame(width: 50, height: 50)
                        .background(AppColors.error.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
                }
                .disabled(!isSpeaking)
                .buttonStyle(.plain)
                .accessibilityLabel("Stop")
                .accessibilityHint("Stop the current speech playback")
            }
        }
    }
    
    // MARK: - Results Section
    
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            sectionHeader("RESULTS")
            
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                resultRow("Engine Used", usedEngine.isEmpty ? "-" : usedEngine)
                resultRow("Synthesis Time", lastSynthesisTime > 0 ? String(format: "%.2fs", lastSynthesisTime) : "-")
                resultRow("Voice ID", selectedVoiceId)
                resultRow("Text Length", "\(testText.count) chars")
            }
            .padding(AppTheme.Spacing.md)
            .background(AppColors.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(resultsAccessibilityLabel)
        }
    }
    
    /// Provides a combined accessibility label for all results.
    private var resultsAccessibilityLabel: String {
        var components: [String] = ["Test results"]
        
        if !usedEngine.isEmpty {
            components.append("Engine: \(usedEngine)")
        }
        
        if lastSynthesisTime > 0 {
            components.append("Time: \(String(format: "%.2f", lastSynthesisTime)) seconds")
        }
        
        components.append("Voice: \(selectedVoiceId)")
        components.append("Text length: \(testText.count) characters")
        
        return components.joined(separator: ". ")
    }
    
    private func resultRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            Text(value)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textPrimary)
        }
    }
    
    // MARK: - Helpers
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppTypography.caption2)
            .fontWeight(.medium)
            .tracking(1.2)
            .foregroundStyle(AppColors.textTertiary)
            .accessibilityAddTraits(.isHeader)
    }
    
    // MARK: - Actions
    
    private func checkKokoroStatus() async {
        statusMessage = "Checking..."
        
        let ttsService = dependencies.ttsService
        isKokoroReady = ttsService.isKokoroReady
        
        if isKokoroReady {
            statusMessage = "Neural TTS engine loaded and ready"
        } else {
            statusMessage = "Will use System TTS fallback"
            
            // Try warming up
            statusMessage = "Warming up Kokoro..."
            await ttsService.warmUp()
            isKokoroReady = ttsService.isKokoroReady
            
            if isKokoroReady {
                statusMessage = "Neural TTS engine loaded and ready"
            } else {
                statusMessage = "Kokoro failed to load - using System TTS"
            }
        }
    }
    
    private func speak() async {
        guard !testText.isEmpty else { return }
        
        isSpeaking = true
        usedEngine = ""
        lastSynthesisTime = 0
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Pass voice ID directly - TTSService handles the routing
        // "system" -> System TTS
        // "af_heart", "am_adam", etc. -> Kokoro with that voice
        let voiceId: String? = selectedVoiceId == "system" ? "system" : selectedVoiceId
        
        #if DEBUG
        print("🎤 TTSTestView.speak: voiceId = \(voiceId ?? "nil")")
        #endif
        
        do {
            try await dependencies.ttsService.speakText(testText, voiceId: voiceId)
            
            let endTime = CFAbsoluteTimeGetCurrent()
            lastSynthesisTime = endTime - startTime
            
            // Determine which engine was used
            if selectedVoiceId == "system" {
                usedEngine = "System AVSpeech"
            } else if isKokoroReady {
                usedEngine = "Kokoro Neural TTS"
            } else {
                usedEngine = "System AVSpeech (Fallback)"
            }
            
        } catch {
            usedEngine = "Error: \(error.localizedDescription)"
        }
        
        isSpeaking = false
    }
    
    private func stopSpeaking() {
        dependencies.ttsService.stopSpeaking()
        isSpeaking = false
    }
}

// MARK: - Preview

#Preview("TTS Test View") {
    NavigationStack {
        TTSTestView()
    }
    .previewEnvironment()
}
