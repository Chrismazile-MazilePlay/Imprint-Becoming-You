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
/// ┌──────────────────────────────────────────────┐
/// │   ┌─────┐   Name (US)                        │
/// │   │  ▶  │   Warm, Expressive                 │
/// │   └─────┘                                    │
/// └──────────────────────────────────────────────┘
/// ```
///
/// ## Interaction
/// - **Tap play button:** Triggers synthesis and playback
/// - **Tap anywhere else:** Selects/deselects the voice
///
/// ## States
/// - Play button: idle (▶) → synthesizing (⟳) → playing (■) → idle
/// - Selection: Border appears when selected
struct VoiceChip: View {
    
    // MARK: - Properties
    
    /// The voice to display
    let voice: Voice
    
    /// Whether this voice is currently selected
    let isSelected: Bool
    
    /// Current playback state for the play button
    let playbackState: VoiceChipPlaybackState
    
    /// Called when the play button is tapped
    let onPlayTapped: () -> Void
    
    /// Called when the chip (non-play area) is tapped
    let onSelectTapped: () -> Void
    
    // MARK: - Constants
    
    private enum Layout {
        static let chipHeight: CGFloat = 56
        static let playButtonSize: CGFloat = 36
        static let playIconSize: CGFloat = 14
        static let horizontalPadding: CGFloat = 12
        static let contentSpacing: CGFloat = 12
        static let borderWidth: CGFloat = 2
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
                    // Name with origin
                    HStack(spacing: 4) {
                        Text(voice.name)
                            .font(AppTypography.headline)
                            .foregroundStyle(isSelected ? AppColors.accent : AppColors.textPrimary)
                        
                        if !voice.originCode.isEmpty {
                            Text("(\(voice.originCode))")
                                .font(AppTypography.caption1)
                                .foregroundStyle(AppColors.textSecondary)
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
            .padding(.trailing, Layout.horizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        if isSelected {
            label += ", selected"
        }
        return label
    }
    
    private var accessibilityHint: String {
        switch playbackState {
        case .idle:
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
        
        // Idle, selected
        VoiceChip(
            voice: Voice.defaultVoice,
            isSelected: true,
            playbackState: .idle,
            onPlayTapped: {},
            onSelectTapped: {}
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
            onSelectTapped: {}
        )
        
        // British voice
        VoiceChip(
            voice: Voice.allEnglishKokoroVoices.first { $0.languageCode == "en-GB" }!,
            isSelected: false,
            playbackState: .idle,
            onPlayTapped: {},
            onSelectTapped: {}
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
            playbackState: .playing,
            onPlayTapped: {},
            onSelectTapped: {}
        )
    }
    .padding()
    .background(AppColors.backgroundPrimary)
    .preferredColorScheme(.dark)
}
