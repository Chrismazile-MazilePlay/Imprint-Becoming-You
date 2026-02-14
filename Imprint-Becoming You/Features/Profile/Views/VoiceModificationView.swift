//
//  VoiceModificationView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/2/26.
//

import SwiftUI
import AVFoundation

// MARK: - Voice Modification View

/// View for customizing voice TTS settings (speed, pitch, expressiveness).
///
/// ## Features
/// - Speed slider (0.5x to 2.0x)
/// - Pitch shift slider (-12 to +12 semitones)
/// - Pitch range slider (0.5 to 1.5 expressiveness)
/// - Preview button to hear changes
/// - Save button appears when settings differ from saved, disappears after save
/// - Restore to Defaults button
///
/// ## Change Detection
/// The Save button appears whenever current settings differ from the last saved state.
/// After saving, if the user makes additional changes, the button reappears.
/// After restoring defaults, if defaults differ from saved state, the button appears.
///
/// ## Navigation
/// Pushed from `VoiceSettingsView` when the gear icon is tapped on a selected voice.
struct VoiceModificationView: View {
    
    // MARK: - Environment
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var dependencies
    
    // MARK: - Properties
    
    /// The voice being modified
    let voice: Voice
    
    /// Callback when settings are saved
    var onSave: ((VoiceSettings) -> Void)?
    
    // MARK: - State
    
    /// Current speed value (for slider)
    @State private var speed: Double = 1.0
    
    /// Current pitch shift value (for slider)
    @State private var pitchShift: Double = 0.0
    
    /// Current pitch range value (for slider)
    @State private var pitchRange: Double = 1.0
    
    /// Settings as they were when last saved (the "saved" baseline).
    /// Updated each time the user taps Save, so change detection stays reactive.
    @State private var savedSettings: VoiceSettings = .default
    
    /// Whether preview is currently playing
    @State private var isPreviewPlaying: Bool = false
    
    /// Whether preview is synthesizing
    @State private var isPreviewSynthesizing: Bool = false
    
    /// Audio player for preview
    @State private var audioPlayer: AVAudioPlayer?
    
    // MARK: - Computed Properties
    
    /// Current settings based on slider values
    private var currentSettings: VoiceSettings {
        VoiceSettings(
            speed: Float(speed),
            pitchShiftSemitones: Int(pitchShift.rounded()),
            pitchRangeScale: Float(pitchRange)
        )
    }
    
    /// Whether the current values differ from the last saved settings.
    private var hasUnsavedChanges: Bool {
        currentSettings != savedSettings
    }
    
    /// Whether the current values differ from defaults.
    ///
    /// Used to show/hide the "Restore Defaults" button.
    private var isModifiedFromDefaults: Bool {
        currentSettings != .default
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    // Voice info header
                    voiceHeader
                    
                    // Settings sliders
                    settingsSection
                    
                    // Preview button
                    previewButton
                    
                    // Restore defaults
                    if isModifiedFromDefaults {
                        restoreDefaultsButton
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.xl)
            }
        }
        .navigationTitle("Voice Tuning")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SaveToolbarButton(
                    hasUnsavedChanges: hasUnsavedChanges,
                    accessibilityHint: "Saves your voice customizations",
                    onSave: { saveSettings() }
                )
            }
        }
        .onAppear {
            loadSettings()
        }
        .onDisappear {
            stopPreview()
        }
    }
    
    // MARK: - Voice Header
    
    private var voiceHeader: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            // Voice icon
            ZStack {
                Circle()
                    .fill(AppColors.accent.opacity(0.15))
                    .frame(width: 64, height: 64)
                
                Image(systemName: "waveform")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(AppColors.accent)
            }
            
            // Voice name
            Text(voice.name)
                .font(AppTypography.title2)
                .foregroundStyle(AppColors.textPrimary)
            
            // Voice description
            if !voice.adjectivesDisplay.isEmpty {
                Text(voice.adjectivesDisplay)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }
            
            // Modified indicator
            if isModifiedFromDefaults {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12))
                    Text("Custom Settings")
                        .font(AppTypography.caption1)
                }
                .foregroundStyle(AppColors.accent)
                .padding(.top, AppTheme.Spacing.xs)
            }
        }
        .padding(.bottom, AppTheme.Spacing.md)
    }
    
    // MARK: - Settings Section
    
    private var settingsSection: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            // Speed slider
            sliderRow(
                title: "Speed",
                value: $speed,
                range: 0.5...2.0,
                step: 0.1,
                displayValue: String(format: "%.1fx", speed),
                description: "Adjust speech rate",
                minLabel: "Slower",
                maxLabel: "Faster"
            )
            
            Divider()
                .background(AppColors.separator)
            
            // Pitch shift slider
            sliderRow(
                title: "Pitch",
                value: $pitchShift,
                range: -12...12,
                step: 1,
                displayValue: pitchShiftDisplayValue,
                description: "Shift voice pitch up or down",
                minLabel: "Lower",
                maxLabel: "Higher"
            )
            
            Divider()
                .background(AppColors.separator)
            
            // Pitch range slider
            sliderRow(
                title: "Expressiveness",
                value: $pitchRange,
                range: 0.5...1.5,
                step: 0.1,
                displayValue: String(format: "%.1f", pitchRange),
                description: "Control pitch variation",
                minLabel: "Monotone",
                maxLabel: "Expressive"
            )
        }
        .padding(AppTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                .fill(AppColors.backgroundSecondary)
        )
    }
    
    // MARK: - Slider Row
    
    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        displayValue: String,
        description: String,
        minLabel: String,
        maxLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            // Title and value
            HStack {
                Text(title)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                
                Spacer()
                
                Text(displayValue)
                    .font(AppTypography.body.monospaced())
                    .foregroundStyle(AppColors.accent)
                    .frame(minWidth: 50, alignment: .trailing)
            }
            
            // Description
            Text(description)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textTertiary)
            
            // Slider
            VStack(spacing: AppTheme.Spacing.xs) {
                Slider(value: value, in: range, step: step)
                    .tint(AppColors.accent)
                
                // Min/max labels
                HStack {
                    Text(minLabel)
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                    
                    Spacer()
                    
                    Text(maxLabel)
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(displayValue)")
        .accessibilityValue(displayValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value.wrappedValue = min(value.wrappedValue + step, range.upperBound)
            case .decrement:
                value.wrappedValue = max(value.wrappedValue - step, range.lowerBound)
            @unknown default:
                break
            }
        }
    }
    
    private var pitchShiftDisplayValue: String {
        let intValue = Int(pitchShift.rounded())
        if intValue > 0 {
            return "+\(intValue)"
        } else if intValue < 0 {
            return "\(intValue)"
        } else {
            return "0"
        }
    }
    
    // MARK: - Preview Button
    
    private var previewButton: some View {
        Button(action: handlePreviewTapped) {
            HStack(spacing: AppTheme.Spacing.sm) {
                if isPreviewSynthesizing {
                    ProgressView()
                        .scaleEffect(0.9)
                        .tint(AppColors.backgroundPrimary)
                } else {
                    Image(systemName: isPreviewPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                
                Text(previewButtonTitle)
                    .font(AppTypography.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(AppColors.backgroundPrimary)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                    .fill(AppColors.accent)
            )
        }
        .buttonStyle(.plain)
        .disabled(isPreviewSynthesizing)
        .accessibilityLabel(previewButtonTitle)
        .accessibilityHint("Plays a sample with current settings")
    }
    
    private var previewButtonTitle: String {
        if isPreviewSynthesizing {
            return "Synthesizing..."
        } else if isPreviewPlaying {
            return "Stop Preview"
        } else {
            return "Preview Voice"
        }
    }
    
    // MARK: - Restore Defaults Button
    
    private var restoreDefaultsButton: some View {
        Button(action: restoreDefaults) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .medium))
                
                Text("Restore Defaults")
                    .font(AppTypography.body)
            }
            .foregroundStyle(AppColors.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Restore to default settings")
        .accessibilityHint("Resets speed, pitch, and expressiveness to original values")
    }
    
    // MARK: - Actions
    
    private func loadSettings() {
        let settings = VoiceSettingsManager.shared.settings(for: voice.id)
        savedSettings = settings
        speed = Double(settings.speed)
        pitchShift = Double(settings.pitchShiftSemitones)
        pitchRange = Double(settings.pitchRangeScale)
        
        #if DEBUG
        print("VoiceModificationView: Loaded settings for \(voice.id): \(settings)")
        #endif
    }
    
    private func saveSettings() {
        let settings = currentSettings
        VoiceSettingsManager.shared.save(settings, for: voice.id)
        
        // Update saved baseline - hasUnsavedChanges becomes false
        savedSettings = settings
        
        // Notify callback
        onSave?(settings)
        
        // Haptic feedback
        HapticFeedback.success()
        
        #if DEBUG
        print("VoiceModificationView: Saved settings for \(voice.id): \(settings)")
        #endif
    }
    
    private func restoreDefaults() {
        // Animate the slider changes
        withAnimation(.easeInOut(duration: 0.3)) {
            speed = 1.0
            pitchShift = 0.0
            pitchRange = 1.0
        }
        
        // Note: We do NOT reset savedSettings here.
        // If saved settings were custom, defaults differ from saved,
        // so hasUnsavedChanges will be true and Save button will appear.
        // If saved settings were already defaults, no change needed.
        
        // Haptic feedback
        HapticFeedback.light()
        
        #if DEBUG
        print("VoiceModificationView: Restored defaults for \(voice.id)")
        print("VoiceModificationView: savedSettings=\(savedSettings), currentSettings=\(currentSettings)")
        print("VoiceModificationView: hasUnsavedChanges=\(hasUnsavedChanges)")
        #endif
    }
    
    // MARK: - Preview Playback
    
    private func handlePreviewTapped() {
        if isPreviewPlaying {
            stopPreview()
        } else {
            playPreview()
        }
    }
    
    private func playPreview() {
        guard let _ = voice.ttsVoiceId else {
            #if DEBUG
            print("VoiceModificationView: No TTS voice ID for \(voice.id)")
            #endif
            return
        }
        
        isPreviewSynthesizing = true
        
        Task { @MainActor in
            do {
                let settings = currentSettings
                
                #if DEBUG
                print("VoiceModificationView: Synthesizing preview with settings: speed=\(settings.speed), pitch=\(settings.pitchShiftSemitones), range=\(settings.pitchRangeScale)")
                #endif
                
                // Pass ALL settings including speed
                let audioData = try await dependencies.ttsService.synthesize(
                    text: Voice.previewPhrase,
                    voiceId: voice.id,  // Use full voice ID
                    speed: settings.speed,
                    pitchShiftSemitones: settings.pitchShiftFloat,
                    pitchRangeScale: settings.pitchRangeScale
                )
                
                // Check we're still wanting to play
                guard isPreviewSynthesizing else { return }
                
                isPreviewSynthesizing = false
                isPreviewPlaying = true
                
                try playAudioData(audioData)
                
            } catch {
                isPreviewSynthesizing = false
                isPreviewPlaying = false
                
                #if DEBUG
                print("VoiceModificationView: Preview failed: \(error)")
                #endif
            }
        }
    }
    
    private func playAudioData(_ data: Data) throws {
        // Stop any existing playback
        stopAudioPlayback()
        
        // Configure audio session
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        
        // Create and play
        audioPlayer = try AVAudioPlayer(data: data)
        audioPlayer?.delegate = VoiceModificationAudioDelegate.shared
        audioPlayer?.prepareToPlay()
        
        // Set up completion handler
        VoiceModificationAudioDelegate.shared.onFinished = { [weak audioPlayer] in
            if self.audioPlayer === audioPlayer {
                self.isPreviewPlaying = false
            }
        }
        
        guard audioPlayer?.play() == true else {
            throw AppError.ttsError("Failed to start audio playback")
        }
        
        #if DEBUG
        print("VoiceModificationView: Playing preview (\(data.count) bytes)")
        #endif
    }
    
    private func stopPreview() {
        isPreviewSynthesizing = false
        isPreviewPlaying = false
        stopAudioPlayback()
    }
    
    private func stopAudioPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
}

// MARK: - Audio Delegate

/// Shared delegate handler for preview audio playback.
private class VoiceModificationAudioDelegate: NSObject, AVAudioPlayerDelegate {
    static let shared = VoiceModificationAudioDelegate()
    
    var onFinished: (() -> Void)?
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.onFinished?()
            self.onFinished = nil
        }
    }
}

// MARK: - Previews

#Preview("Voice Modification") {
    NavigationStack {
        VoiceModificationView(voice: Voice.defaultVoice)
    }
    .previewEnvironment()
}

#Preview("Voice Modification - Dark") {
    NavigationStack {
        VoiceModificationView(voice: Voice.defaultVoice)
    }
    .preferredColorScheme(.dark)
    .previewEnvironment()
}
