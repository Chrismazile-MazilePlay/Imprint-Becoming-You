//
//  UserProfile.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import Foundation
import SwiftData

// MARK: - UserProfile

/// The user's profile containing preferences, settings, and subscription status.
///
/// This is the central model for user-specific data that persists across sessions
/// and syncs to Firebase when the user is authenticated.
///
/// ## Related Types
/// - `SessionMode` - Defined in Domain/Models/SessionMode.swift
/// - `BinauralPreset` - Defined in Domain/Models/BinauralPreset.swift
/// - `CalibrationData` - Voice calibration data (defined below)
@Model
final class UserProfile {
    
    // MARK: - Properties
    
    /// Unique identifier for the profile
    @Attribute(.unique)
    var id: UUID
    
    /// Date the profile was created
    var createdAt: Date
    
    /// Array of selected goal category identifiers
    var selectedGoals: [String]
    
    /// Date when goals were last modified (for 3-month lock)
    var goalsLastChangedAt: Date
    
    /// ElevenLabs voice ID if user has cloned their voice
    var voiceProfileId: String?
    
    /// Whether the user has used their free voice clone
    var hasUsedFreeVoiceClone: Bool
    
    /// Calibration data from onboarding voice calibration
    var calibrationData: CalibrationData?
    
    /// User's preferred session mode
    var preferredMode: SessionMode
    
    /// User's preferred binaural beat preset
    var binauralPreset: BinauralPreset
    
    /// Whether the user has an active premium subscription
    var isPremium: Bool
    
    /// Expiration date of premium subscription (nil if lifetime or not premium)
    var premiumExpiresAt: Date?
    
    /// Last time data was synced with Firebase
    var lastSyncedAt: Date?
    
    /// Firebase user ID when authenticated
    var firebaseUserId: String?
    
    /// Whether onboarding has been completed
    var hasCompletedOnboarding: Bool
    
    // MARK: - Initialization
    
    /// Creates a new user profile with default values
    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        selectedGoals: [String] = [],
        goalsLastChangedAt: Date = Date(),
        voiceProfileId: String? = nil,
        hasUsedFreeVoiceClone: Bool = false,
        calibrationData: CalibrationData? = nil,
        preferredMode: SessionMode = .readOnly,
        binauralPreset: BinauralPreset = .off,
        isPremium: Bool = false,
        premiumExpiresAt: Date? = nil,
        lastSyncedAt: Date? = nil,
        firebaseUserId: String? = nil,
        hasCompletedOnboarding: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.selectedGoals = selectedGoals
        self.goalsLastChangedAt = goalsLastChangedAt
        self.voiceProfileId = voiceProfileId
        self.hasUsedFreeVoiceClone = hasUsedFreeVoiceClone
        self.calibrationData = calibrationData
        self.preferredMode = preferredMode
        self.binauralPreset = binauralPreset
        self.isPremium = isPremium
        self.premiumExpiresAt = premiumExpiresAt
        self.lastSyncedAt = lastSyncedAt
        self.firebaseUserId = firebaseUserId
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
}

// MARK: - Computed Properties

extension UserProfile {
    
    /// Whether the user has a voice profile configured (cloned or system)
    var hasVoiceProfile: Bool {
        voiceProfileId != nil
    }
    
    /// Whether the user can create a new voice clone
    var canCreateVoiceClone: Bool {
        isPremium || !hasUsedFreeVoiceClone
    }
    
    /// Whether the user can change their goals
    var canChangeGoals: Bool {
        guard !isPremium else { return true }
        let lockDuration = TimeInterval(Constants.FreeTier.goalLockDays * 24 * 60 * 60)
        return Date().timeIntervalSince(goalsLastChangedAt) >= lockDuration
    }
    
    /// Date when goals will be unlocked (nil if already unlocked or premium)
    var goalsUnlockDate: Date? {
        guard !canChangeGoals else { return nil }
        let lockDuration = TimeInterval(Constants.FreeTier.goalLockDays * 24 * 60 * 60)
        return goalsLastChangedAt.addingTimeInterval(lockDuration)
    }
    
    /// Days remaining until goals can be changed
    var daysUntilGoalsUnlock: Int? {
        guard let unlockDate = goalsUnlockDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: unlockDate).day
        return max(0, days ?? 0)
    }
    
    /// Whether the user is authenticated with Firebase
    var isAuthenticated: Bool {
        firebaseUserId != nil
    }
    
    /// Whether calibration has been completed
    var isCalibrated: Bool {
        calibrationData != nil
    }
    
    /// Selected goals as GoalCategory objects
    var selectedGoalCategories: [GoalCategory] {
        selectedGoals.compactMap { GoalCategory(rawValue: $0) }
    }
}

// MARK: - CalibrationData

/// Voice calibration data captured during onboarding.
///
/// This data is used to personalize the Resonance Score calculation
/// based on the user's natural vocal characteristics.
struct CalibrationData: Codable, Equatable, Sendable {
    
    /// Average RMS energy level from calibration samples
    var baselineRMS: Float
    
    /// Minimum detected pitch (Hz)
    var pitchMin: Float
    
    /// Maximum detected pitch (Hz)
    var pitchMax: Float
    
    /// Minimum detected volume (dB)
    var volumeMin: Float
    
    /// Maximum detected volume (dB)
    var volumeMax: Float
    
    /// Date when calibration was performed
    var calibratedAt: Date
    
    /// Creates new calibration data
    init(
        baselineRMS: Float,
        pitchMin: Float,
        pitchMax: Float,
        volumeMin: Float,
        volumeMax: Float,
        calibratedAt: Date = Date()
    ) {
        self.baselineRMS = baselineRMS
        self.pitchMin = pitchMin
        self.pitchMax = pitchMax
        self.volumeMin = volumeMin
        self.volumeMax = volumeMax
        self.calibratedAt = calibratedAt
    }
    
    /// Average pitch based on range
    var averagePitch: Float {
        (pitchMin + pitchMax) / 2.0
    }
    
    /// Pitch range span
    var pitchRange: Float {
        pitchMax - pitchMin
    }
}

// NOTE: SessionMode and BinauralPreset enums have been moved to their own files:
// - Domain/Models/SessionMode.swift
// - Domain/Models/BinauralPreset.swift
