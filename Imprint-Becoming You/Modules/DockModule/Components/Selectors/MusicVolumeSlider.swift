//
//  MusicVolumeSlider.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/14/26.
//

import SwiftUI

// MARK: - MusicVolumeSlider

/// A horizontal volume slider for background music.
///
/// Displays speaker icons on both ends with a draggable thumb that controls
/// music volume from 0.0 to 1.0. The slider snaps back to the default volume
/// (0.15) when released within a threshold, and supports double-tap to reset.
///
/// ## Design
///
/// Matches the dock music selector aesthetic — same background, corner radius,
/// and opacity. The slider track uses `surfaceTertiary` with an accent-colored
/// filled portion and a circular thumb.
///
/// ## Usage
///
/// ```swift
/// MusicVolumeSlider(
///     volume: adapter.musicVolume,
///     onVolumeChange: { newVolume in
///         adapter.setMusicVolume(newVolume)
///     }
/// )
/// ```
public struct MusicVolumeSlider: View {

    // MARK: - Constants

    /// Default volume that the slider snaps back to.
    private static let defaultVolume: Float = 0.15

    /// Snap threshold — release within this distance of default to snap back.
    private static let snapThreshold: Float = 0.03

    /// Height of the slider track.
    private static let trackHeight: CGFloat = 4

    /// Diameter of the draggable thumb.
    private static let thumbSize: CGFloat = 20

    // MARK: - Environment

    @Environment(\.dockDesignTokens) private var tokens
    @Environment(\.dockHapticsProvider) private var haptics

    // MARK: - Properties

    /// The current volume value (0.0–1.0).
    public let volume: Float

    /// Called continuously as the user drags the slider.
    public let onVolumeChange: (Float) -> Void

    // MARK: - Local State

    /// Whether the user is currently dragging.
    @State private var isDragging = false

    // MARK: - Initialization

    public init(
        volume: Float,
        onVolumeChange: @escaping (Float) -> Void
    ) {
        self.volume = volume
        self.onVolumeChange = onVolumeChange
    }

    // MARK: - Body

    public var body: some View {
        HStack(spacing: tokens.spacingSM) {
            // Quiet speaker icon
            Image(systemName: "speaker.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.textTertiary)
                .frame(width: 16)

            // Slider track + thumb
            GeometryReader { geometry in
                let trackWidth = geometry.size.width
                let normalizedVolume = CGFloat(volume)
                let thumbX = normalizedVolume * trackWidth

                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(tokens.surfaceTertiary.opacity(0.5))
                        .frame(height: Self.trackHeight)

                    // Filled track
                    Capsule()
                        .fill(tokens.accent)
                        .frame(
                            width: max(Self.trackHeight, thumbX),
                            height: Self.trackHeight
                        )

                    // Thumb
                    Circle()
                        .fill(tokens.textPrimary)
                        .frame(width: Self.thumbSize, height: Self.thumbSize)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .offset(x: thumbX - Self.thumbSize / 2)
                }
                .frame(height: Self.thumbSize)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                haptics.lightImpact()
                            }
                            let fraction = Float(value.location.x / trackWidth)
                            let clamped = max(0, min(1, fraction))
                            onVolumeChange(clamped)
                        }
                        .onEnded { value in
                            isDragging = false
                            let fraction = Float(value.location.x / trackWidth)
                            let clamped = max(0, min(1, fraction))
                            // Snap to default if close enough
                            if abs(clamped - Self.defaultVolume) <= Self.snapThreshold {
                                onVolumeChange(Self.defaultVolume)
                                haptics.selectionFeedback()
                            } else {
                                onVolumeChange(clamped)
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    // Double-tap resets to default volume
                    onVolumeChange(Self.defaultVolume)
                    haptics.selectionFeedback()
                }
            }
            .frame(height: Self.thumbSize)

            // Loud speaker icon
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.textTertiary)
                .frame(width: 20)
        }
        .padding(.horizontal, tokens.spacingMD)
        .padding(.vertical, tokens.spacingSM + 2)
        .background(
            RoundedRectangle(cornerRadius: tokens.cornerRadiusLarge)
                .fill(tokens.backgroundSecondary.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: tokens.cornerRadiusLarge)
                .stroke(tokens.textTertiary.opacity(0.1), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Music volume")
        .accessibilityValue("\(Int(volume * 100)) percent")
        .accessibilityAdjustableAction { direction in
            let step: Float = 0.05
            switch direction {
            case .increment:
                onVolumeChange(min(1, volume + step))
            case .decrement:
                onVolumeChange(max(0, volume - step))
            @unknown default:
                break
            }
        }
    }
}

// MARK: - Previews

#Preview("Music Volume Slider") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            MusicVolumeSlider(volume: 0.15) { _ in }
                .padding()
        }
    }
}

#Preview("Music Volume Slider - High") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            MusicVolumeSlider(volume: 0.8) { _ in }
                .padding()
        }
    }
}
