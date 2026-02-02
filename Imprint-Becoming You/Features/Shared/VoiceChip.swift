//
//  VoiceChip.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/1/26.
//

import SwiftUI

// MARK: - Voice Chip Playback State

/// Playback state for the voice chip play button.
enum VoiceChipPlaybackState: Equatable, Sendable {
    /// Idle state - shows play icon
    case idle
    /// Synthesizing TTS - shows loading spinner
    case synthesizing
    /// Audio is playing - shows stop icon
    case playing
}

// MARK: - Voice Chip

/// A capsule-shaped pill for voice selection with integrated preview playback.
///
/// ## Layout
/// ```
/// ┌──────────────────────────────────────────────────────┐
/// │   ┌─────┐   Name (US)                     ┌─────┐    │
/// │   │  ▶  │   Warm, Expressive              │  ⚙  │    │
/// │   └─────┘                                 └─────┘    │
/// └──────────────────────────────────────────────────────┘
/// ```
///
/// ## Interaction
/// - **Tap play button:** Triggers synthesis and playback
/// - **Tap gear button:** Opens voice modification settings (when selected)
/// - **Tap anywhere else:** Selects/deselects the voice
///
/// ## States
/// - Play button: idle (▶) → synthesizing (⟳) → playing (■) → idle
/// - Selection: Border appears when selected, gear icon becomes visible
struct VoiceChip: View {
    
    // MARK: - Properties
    
    /// The voice to display
    let voice: Voice
    
    /// Whether this voice is currently selected
    let isSelected: Bool
    
    /// Whether this voice has custom settings (shows indicator dot)
    var hasCustomSettings: Bool = false
    
    /// Current playback state for the play button
    let playbackState: VoiceChipPlaybackState
    
    /// Called when the play button is tapped
    let onPlayTapped: () -> Void
    
    /// Called when the chip (non-play area) is tapped
    let onSelectTapped: () -> Void
    
    /// Called when the settings gear is tapped (only visible when selected)
    var onSettingsTapped: (() -> Void)? = nil
    
    // MARK: - Constants
    
    private enum Layout {
        static let chipHeight: CGFloat = 56
        static let playButtonSize: CGFloat = 36
        static let playIconSize: CGFloat = 14
        static let settingsButtonSize: CGFloat = 32
        static let settingsIconSize: CGFloat = 14
        static let horizontalPadding: CGFloat = 12
        static let contentSpacing: CGFloat = 12
        static let borderWidth: CGFloat = 2
        static let indicatorDotSize: CGFloat = 6
    }
    
    // MARK: - Body
    
    var body: some View {
        HStack(spacing: 0) {
            // Play button area
            playButton
            
            // Divider
            Rectangle()
                .fill(AppColors.separator)
                .frame(width: 1, height: 32)
            
            // Voice info area (tappable for selection)
            voiceInfoButton
            
            // Settings button (only when selected and callback provided)
            if isSelected && onSettingsTapped != nil {
                settingsButton
            }
        }
        .frame(height: Layout.chipHeight)
        .background(chipBackground)
        .clipShape(Capsule())
        .overlay(selectionBorder)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
    
    // MARK: - Play Button
    
    private var playButton: some View {
        Button(action: onPlayTapped) {
            ZStack {
                // Background for touch target
                Color.clear
                    .frame(width: Layout.playButtonSize + Layout.horizontalPadding * 2)
                
                // Icon or spinner
                Group {
                    switch playbackState {
                    case .idle:
                        Image(systemName: "play.fill")
                            .font(.system(size: Layout.playIconSize, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    
                    case .synthesizing:
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(AppColors.accent)
                    
                    case .playing:
                        Image(systemName: "stop.fill")
                            .font(.system(size: Layout.playIconSize, weight: .semibold))
                            .foregroundStyle(AppColors.accent)
                    }
                }
                .frame(width: Layout.playButtonSize, height: Layout.playButtonSize)
                .background(
                    Circle()
                        .fill(AppColors.backgroundTertiary)
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playButtonAccessibilityLabel)
    }
    
    // MARK: - Voice Info
    
    private var voiceInfoButton: some View {
        Button(action: onSelectTapped) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    // Name with origin and custom indicator
                    HStack(spacing: 4) {
                        Text(voice.name)
                            .font(AppTypography.headline)
                            .foregroundStyle(isSelected ? AppColors.accent : AppColors.textPrimary)
                        
                        if !voice.originCode.isEmpty {
                            Text("(\(voice.originCode))")
                                .font(AppTypography.caption1)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        
                        // Custom settings indicator
                        if hasCustomSettings {
                            Circle()
                                .fill(AppColors.accent)
                                .frame(width: Layout.indicatorDotSize, height: Layout.indicatorDotSize)
                                .accessibilityLabel("Has custom settings")
                        }
                    }
                    
                    // Adjectives
                    if !voice.adjectivesDisplay.isEmpty {
                        Text(voice.adjectivesDisplay)
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
                
                Spacer(minLength: Layout.horizontalPadding)
            }
            .padding(.leading, Layout.contentSpacing)
            .padding(.trailing, isSelected && onSettingsTapped != nil ? 0 : Layout.horizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Settings Button
    
    private var settingsButton: some View {
        Button(action: { onSettingsTapped?() }) {
            ZStack {
                // Background for touch target
                Color.clear
                    .frame(width: Layout.settingsButtonSize + Layout.horizontalPadding)
                
                Image(systemName: "gearshape.fill")
                    .font(.system(size: Layout.settingsIconSize, weight: .medium))
                    .foregroundStyle(AppColors.accent)
                    .frame(width: Layout.settingsButtonSize, height: Layout.settingsButtonSize)
                    .background(
                        Circle()
                            .fill(AppColors.accent.opacity(0.15))
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voice settings")
        .accessibilityHint("Opens voice customization options")
    }
    
    // MARK: - Background & Border
    
    private var chipBackground: some View {
        Capsule()
            .fill(isSelected ? AppColors.accent.opacity(0.1) : AppColors.backgroundSecondary)
    }
    
    private var selectionBorder: some View {
        Capsule()
            .stroke(
                isSelected ? AppColors.accent : Color.clear,
                lineWidth: Layout.borderWidth
            )
    }
    
    // MARK: - Accessibility
    
    private var accessibilityLabel: String {
        var label = "\(voice.name) voice"
        if !voice.originCode.isEmpty {
            label += ", \(voice.originCode) accent"
        }
        if !voice.adjectivesDisplay.isEmpty {
            label += ", \(voice.adjectivesDisplay)"
        }
        if hasCustomSettings {
            label += ", has custom settings"
        }
        if isSelected {
            label += ", selected"
        }
        return label
    }
    
    private var accessibilityHint: String {
        switch playbackState {
        case .idle:
            if isSelected && onSettingsTapped != nil {
                return "Double tap play button to preview, or settings button to customize"
            }
            return isSelected ? "Double tap play button to preview" : "Double tap to select, or tap play button to preview"
        case .synthesizing:
            return "Loading preview"
        case .playing:
            return "Double tap play button to stop"
        }
    }
    
    private var playButtonAccessibilityLabel: String {
        switch playbackState {
        case .idle: return "Play preview"
        case .synthesizing: return "Loading"
        case .playing: return "Stop preview"
        }
    }
}

// MARK: - Previews

#Preview("Voice Chip States") {
    VStack(spacing: 16) {
        // Idle, unselected
        VoiceChip(
            voice: Voice.defaultVoice,
            isSelected: false,
            playbackState: .idle,
            onPlayTapped: {},
            onSelectTapped: {}
        )
        
        // Idle, selected (no settings callback)
        VoiceChip(
            voice: Voice.defaultVoice,
            isSelected: true,
            playbackState: .idle,
            onPlayTapped: {},
            onSelectTapped: {}
        )
        
        // Selected with settings button
        VoiceChip(
            voice: Voice.defaultVoice,
            isSelected: true,
            playbackState: .idle,
            onPlayTapped: {},
            onSelectTapped: {},
            onSettingsTapped: {}
        )
        
        // Selected with settings and custom indicator
        VoiceChip(
            voice: Voice.allEnglishKokoroVoices[1],
            isSelected: true,
            hasCustomSettings: true,
            playbackState: .idle,
            onPlayTapped: {},
            onSelectTapped: {},
            onSettingsTapped: {}
        )
        
        // Synthesizing
        VoiceChip(
            voice: Voice.allEnglishKokoroVoices[1],
            isSelected: false,
            playbackState: .synthesizing,
            onPlayTapped: {},
            onSelectTapped: {}
        )
        
        // Playing
        VoiceChip(
            voice: Voice.allEnglishKokoroVoices[2],
            isSelected: true,
            playbackState: .playing,
            onPlayTapped: {},
            onSelectTapped: {},
            onSettingsTapped: {}
        )
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("Voice Chip - Custom Settings") {
    VStack(spacing: 16) {
        // With custom settings indicator
        VoiceChip(
            voice: Voice.defaultVoice,
            isSelected: false,
            hasCustomSettings: true,
            playbackState: .idle,
            onPlayTapped: {},
            onSelectTapped: {}
        )
        
        // Selected with custom settings
        VoiceChip(
            voice: Voice.defaultVoice,
            isSelected: true,
            hasCustomSettings: true,
            playbackState: .idle,
            onPlayTapped: {},
            onSelectTapped: {},
            onSettingsTapped: {}
        )
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("Voice Chip - Dark") {
    VStack(spacing: 16) {
        VoiceChip(
            voice: Voice.defaultVoice,
            isSelected: true,
            hasCustomSettings: true,
            playbackState: .playing,
            onPlayTapped: {},
            onSelectTapped: {},
            onSettingsTapped: {}
        )
    }
    .padding()
    .background(AppColors.backgroundPrimary)
    .preferredColorScheme(.dark)
}
