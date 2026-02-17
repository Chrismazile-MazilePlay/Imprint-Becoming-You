//
//  MusicCategory.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/14/26.
//

import Foundation

// MARK: - MusicCategory

/// Background music categories for practice sessions.
///
/// Each category contains 1–3 bundled loop-ready MP3 tracks stored in
/// `Resources/Audio/BackgroundMusic/{category}/`. Tracks are pre-processed
/// with 2-second fade edges for seamless crossfade looping.
///
/// ## Track Loading
/// ```swift
/// let category: MusicCategory = .coffee
/// let fileName = category.randomTrackFileName()
/// let url = Bundle.main.url(
///     forResource: fileName,
///     withExtension: nil,
///     subdirectory: "BackgroundMusic/\(category.rawValue)"
/// )
/// ```
enum MusicCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case coffee
    case driving
    case exercise
    case focus
    case meditation
    case morning
    case nature
    case piano
    case sleep

    var id: String { rawValue }

    // MARK: - Display Properties

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .coffee: return "Coffee & Cozy"
        case .driving: return "Driving"
        case .exercise: return "Exercise"
        case .focus: return "Deep Focus"
        case .meditation: return "Meditation"
        case .morning: return "Morning"
        case .nature: return "Nature"
        case .piano: return "Gentle Piano"
        case .sleep: return "Sleep"
        }
    }

    /// SF Symbol icon name
    var iconName: String {
        switch self {
        case .coffee: return "cup.and.saucer.fill"
        case .driving: return "car.fill"
        case .exercise: return "figure.run"
        case .focus: return "brain.head.profile"
        case .meditation: return "figure.mind.and.body"
        case .morning: return "sun.horizon.fill"
        case .nature: return "leaf.fill"
        case .piano: return "pianokeys"
        case .sleep: return "moon.stars.fill"
        }
    }

    // MARK: - Track Files

    /// All bundled track filenames for this category.
    ///
    /// Filenames match the files in `Resources/Audio/BackgroundMusic/{category}/`.
    var trackFileNames: [String] {
        switch self {
        case .coffee:
            return [
                "coffee_01_lofi_chill.mp3",
                "coffee_02_jazzy_love.mp3",
                "coffee_03_lofi_retro.mp3"
            ]
        case .driving:
            return [
                "driving_01_neon_odyssey.mp3",
                "driving_02_progressive_retrowave.mp3",
                "driving_03_retro_lounge.mp3"
            ]
        case .exercise:
            return [
                "exercise_01_gym_workout.mp3",
                "exercise_02_sport_gym.mp3",
                "exercise_03_rock_motivation.mp3"
            ]
        case .focus:
            return [
                "focus_01_ambient_background.mp3",
                "focus_02_minimalism_lofi.mp3"
            ]
        case .meditation:
            return [
                "meditation_01_stillness.mp3"
            ]
        case .morning:
            return [
                "morning_01_small_miracle.mp3"
            ]
        case .nature:
            return [
                "nature_01_ocean_waves_birds.mp3",
                "nature_02_forest_birds.mp3",
                "nature_03_chirping_birds.mp3"
            ]
        case .piano:
            return [
                "piano_01_inspirational.mp3"
            ]
        case .sleep:
            return [
                "sleep_01_shimmer.mp3",
                "sleep_02_healing_drone.mp3",
                "sleep_03_zen_drone.mp3"
            ]
        }
    }

    /// Number of tracks in this category.
    var trackCount: Int { trackFileNames.count }

    /// Returns the track filename at the given index, wrapping safely.
    ///
    /// Handles both positive overflow and negative indices via modular
    /// arithmetic, enabling sequential skip-forward and skip-backward
    /// without bounds checking at the call site.
    ///
    /// - Parameter index: Any integer index (wraps to valid range).
    /// - Returns: The track filename at the wrapped index.
    func trackFileName(at index: Int) -> String {
        let count = trackCount
        let wrappedIndex = ((index % count) + count) % count
        return trackFileNames[wrappedIndex]
    }

    /// Returns a random track filename from this category.
    func randomTrackFileName() -> String {
        trackFileNames.randomElement() ?? trackFileNames[0]
    }

    /// Bundle subdirectory path for this category's tracks.
    var subdirectory: String {
        "BackgroundMusic/\(rawValue)"
    }
}
