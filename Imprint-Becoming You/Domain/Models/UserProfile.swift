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
/// - `MusicCategory` - Defined in Domain/Models/MusicCategory.swift
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
    
    /// User's preferred background music category (nil = Off)
    var backgroundMusicCategory: String?
    
    /// User's preferred waveform visualization style.
    ///
    /// Stored as raw value string for SwiftData compatibility.
    /// Use `waveformType` computed property for type-safe access.
    var preferredWaveformType: String
    
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
    
    /// Whether the user wants faith-based content included in their affirmations.
    ///
    /// - `nil`: User has not made a choice yet (forces decision during onboarding)
    /// - `true`: Include Biblical scripture and faith-based affirmations
    /// - `false`: Secular content only (faith categories hidden)
    ///
    /// - Note: User can change this in Settings.
    /// - TODO: Phase 9 - Add Settings UI for changing this preference
    var includeFaithContent: Bool?
    
    /// Expiration date for trial subscription.
    ///
    /// - `nil`: User has not started a trial or trial has expired
    /// - Non-nil: Trial is active if date is in the future
    ///
    /// Used in conjunction with `isPremium` and `premiumExpiresAt` to determine
    /// the user's `subscriptionTier`.
    var trialExpiresAt: Date?
    
    /// ID of the user's currently selected TTS voice.
    ///
    /// References a `Voice.id` value. If `nil`, the app uses the default voice.
    /// Can be a preset voice ID (e.g., "kokoro_af_heart") or a custom voice ID.
    var selectedVoiceId: String?

    /// User's preferred background style for practice and session views.
    ///
    /// Stored as raw value string for SwiftData compatibility.
    /// Use `backgroundStyle` computed property for type-safe access.
    var backgroundStyleRawValue: String = BackgroundStyle.morphingGradient.rawValue
    
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
        backgroundMusicCategory: String? = nil,
        preferredWaveformType: String = "layeredWaves",
        isPremium: Bool = false,
        premiumExpiresAt: Date? = nil,
        lastSyncedAt: Date? = nil,
        firebaseUserId: String? = nil,
        hasCompletedOnboarding: Bool = false,
        includeFaithContent: Bool? = nil,
        trialExpiresAt: Date? = nil,
        selectedVoiceId: String? = nil,
        backgroundStyleRawValue: String = BackgroundStyle.morphingGradient.rawValue
    ) {
        self.id = id
        self.createdAt = createdAt
        self.selectedGoals = selectedGoals
        self.goalsLastChangedAt = goalsLastChangedAt
        self.voiceProfileId = voiceProfileId
        self.hasUsedFreeVoiceClone = hasUsedFreeVoiceClone
        self.calibrationData = calibrationData
        self.preferredMode = preferredMode
        self.backgroundMusicCategory = backgroundMusicCategory
        self.preferredWaveformType = preferredWaveformType
        self.isPremium = isPremium
        self.premiumExpiresAt = premiumExpiresAt
        self.lastSyncedAt = lastSyncedAt
        self.firebaseUserId = firebaseUserId
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.includeFaithContent = includeFaithContent
        self.trialExpiresAt = trialExpiresAt
        self.selectedVoiceId = selectedVoiceId
        self.backgroundStyleRawValue = backgroundStyleRawValue
    }
}

// MARK: - Computed Properties

extension UserProfile {
    
    // MARK: - Subscription Tier
    
    /// The user's current subscription tier.
    ///
    /// Computed from the stored subscription state:
    /// - `.premium` if `isPremium` is true and not expired
    /// - `.trial` if `trialExpiresAt` is in the future
    /// - `.free` otherwise
    ///
    /// Use this property to gate premium features throughout the app.
    ///
    /// ```swift
    /// if userProfile.subscriptionTier.hasPremiumAccess {
    ///     showAllVoices()
    /// }
    /// ```
    var subscriptionTier: SubscriptionTier {
        // Check premium first (highest priority)
        if isPremium {
            if let expiresAt = premiumExpiresAt {
                if expiresAt > Date() {
                    return .premium
                }
                // Premium expired, fall through to check trial
            } else {
                // No expiration = lifetime premium
                return .premium
            }
        }
        
        // Check trial
        if let trialExpires = trialExpiresAt, trialExpires > Date() {
            return .trial
        }
        
        // Default to free
        return .free
    }
    
    /// Whether the user is currently in a trial period.
    var isInTrial: Bool {
        subscriptionTier == .trial
    }
    
    /// Days remaining in trial, or `nil` if not in trial.
    var trialDaysRemaining: Int? {
        guard let trialExpires = trialExpiresAt, trialExpires > Date() else {
            return nil
        }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: trialExpires).day
        return max(0, days ?? 0)
    }
    
    /// Whether the user has ever had a trial (regardless of expiration).
    var hasHadTrial: Bool {
        trialExpiresAt != nil
    }
    
    /// Starts a trial for the specified duration.
    ///
    /// - Parameter days: Number of days for the trial (default: 7)
    func startTrial(days: Int = 7) {
        trialExpiresAt = Calendar.current.date(
            byAdding: .day,
            value: days,
            to: Date()
        )
    }
    
    // MARK: - Voice Profile
    
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
    
    /// Whether the user has made a faith content preference choice
    var hasMadeFaithPreferenceChoice: Bool {
        includeFaithContent != nil
    }
    
    /// Available goal categories based on faith preference.
    ///
    /// If `includeFaithContent` is `false`, faith-based categories are excluded.
    /// If `includeFaithContent` is `true` or `nil`, all categories are available.
    var availableGoalCategories: [GoalCategory] {
        if includeFaithContent == false {
            return GoalCategory.allCases.filter { !$0.isFaithBased }
        }
        return GoalCategory.allCases
    }
    
    /// Available goal groups based on faith preference.
    ///
    /// If `includeFaithContent` is `false`, the faith-based group is excluded.
    var availableGoalGroups: [GoalGroup] {
        if includeFaithContent == false {
            return GoalGroup.allCases.filter { $0 != .faithBased }
        }
        return GoalGroup.allCases
    }
    
    // MARK: - Waveform Type
    
    /// The user's preferred waveform visualization type.
    ///
    /// Provides type-safe access to the stored `preferredWaveformType` string.
    /// Falls back to `.layeredWaves` if the stored value is invalid.
    var waveformType: DockWaveformType {
        get {
            DockWaveformType(rawValue: preferredWaveformType) ?? .layeredWaves
        }
        set {
            preferredWaveformType = newValue.rawValue
        }
    }

    // MARK: - Background Style

    /// The user's preferred background style for practice and session views.
    ///
    /// Provides type-safe access to the stored `backgroundStyleRawValue` string.
    /// Falls back to `.morphingGradient` if the stored value is invalid.
    var backgroundStyle: BackgroundStyle {
        get {
            BackgroundStyle(rawValue: backgroundStyleRawValue) ?? .morphingGradient
        }
        set {
            backgroundStyleRawValue = newValue.rawValue
        }
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

// NOTE: SessionMode enum has been moved to its own file:
// - Domain/Models/SessionMode.swift

// NOTE: DockWaveformType is defined in DockModule:
// - DockModule/Models/DockWaveformType.swift
