//
//  Constants.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import Foundation

// MARK: - App Constants

/// Centralized app-wide constants
///
/// All magic numbers, configuration values, and string keys should be defined here
/// to ensure consistency and easy modification.
enum Constants {
    
    // MARK: - App Info
    
    enum App {
        static let name = "Imprint"
        static let tagline = "Becoming You"
        static let bundleIdentifier = "MazilePlay.Imprint-Becoming-You"
        static let appStoreId = "" // TODO: Add after App Store submission
    }
    
    // MARK: - Session Configuration
    
    enum Session {
        /// Number of affirmations generated per batch
        static let batchSize = 30
        
        /// Index at which to trigger next batch generation (25 of 30)
        static let regenerationTriggerIndex = 25
        
        /// Number of unseen affirmations before regeneration for custom prompts
        static let promptRegenerationThreshold = 5
        
        /// Timeout before showing "Are you there?" popup (seconds)
        static let inactivityTimeout: TimeInterval = 5.0
        
        /// Countdown duration for "Are you there?" popup (seconds)
        static let popupCountdownDuration: TimeInterval = 10.0
        
        /// Silence detection threshold (seconds)
        static let silenceThreshold: TimeInterval = 1.5
    }
    
    // MARK: - Audio Configuration
    
    enum Audio {
        /// Sample rate for audio processing
        static let sampleRate: Double = 44100.0
        
        /// Buffer size for audio processing
        static let bufferSize: UInt32 = 1024
        
        /// Volume level for binaural beats (0.0 - 1.0)
        static let binauralVolume: Float = 0.15
        
        /// Base carrier frequency for binaural beats (Hz)
        static let binauralCarrierFrequency: Float = 200.0
    }
    
    // MARK: - Binaural Frequencies
    
    enum BinauralFrequencies {
        /// Focus preset - Beta waves (14 Hz difference)
        static let focus: Float = 14.0
        
        /// Relax preset - Alpha waves (10 Hz difference)
        static let relax: Float = 10.0
        
        /// Sleep preset - Theta waves (6 Hz difference)
        static let sleep: Float = 6.0
    }
    
    // MARK: - Resonance Scoring
    
    enum ResonanceScoring {
        /// Weight for text accuracy in final score
        static let textAccuracyWeight: Float = 0.10
        
        /// Weight for vocal energy (RMS) in final score
        static let vocalEnergyWeight: Float = 0.60
        
        /// Weight for pitch stability in final score
        static let pitchStabilityWeight: Float = 0.30
        
        /// Minimum score threshold for "good" resonance
        static let goodThreshold: Float = 0.6
        
        /// Minimum score threshold for "excellent" resonance
        static let excellentThreshold: Float = 0.8
    }
    
    // MARK: - Cache Configuration
    
    enum Cache {
        /// Maximum audio cache size in bytes (500 MB)
        static let maxAudioCacheSize: Int64 = 500 * 1024 * 1024
        
        /// Cache expiration duration (30 days)
        static let expirationDays: Int = 30
        
        /// Audio cache directory name
        static let audioCacheDirectory = "AudioCache"
    }
    
    // MARK: - Free Tier Limits
    
    enum FreeTier {
        /// Maximum number of saved custom prompts for free users
        static let maxPrompts = 3
        
        /// Maximum number of goals a user can select
        static let maxGoals = 5
        
        /// Days before goals can be changed again
        static let goalLockDays = 90
        
        /// Number of free voice clones allowed
        static let freeVoiceClones = 1
    }
    
    // MARK: - Voice Clone Configuration
    
    enum VoiceClone {
        /// Minimum recording duration for voice cloning (seconds)
        static let minimumRecordingDuration: TimeInterval = 60.0
        
        /// Recommended recording duration (seconds)
        static let recommendedRecordingDuration: TimeInterval = 180.0
        
        /// Maximum recording duration (seconds)
        static let maximumRecordingDuration: TimeInterval = 300.0
    }
    
    // MARK: - Calibration
    
    enum Calibration {
        /// Number of affirmations used during calibration
        static let sampleCount = 5
    }
    
    // MARK: - Animation Durations
    
    enum Animation {
        /// Standard transition duration
        static let standard: Double = 0.3
        
        /// Quick micro-interaction duration
        static let quick: Double = 0.15
        
        /// Slow, deliberate animation duration
        static let slow: Double = 0.5
        
        /// Page transition duration for affirmation cards
        static let pageTransition: Double = 0.4
    }
    
    // MARK: - Layout
    
    enum Layout {
        /// Standard horizontal padding
        static let horizontalPadding: CGFloat = 24.0
        
        /// Standard vertical spacing
        static let verticalSpacing: CGFloat = 16.0
        
        /// Card corner radius
        static let cardCornerRadius: CGFloat = 16.0
        
        /// Button corner radius
        static let buttonCornerRadius: CGFloat = 12.0
        
        /// Minimum touch target size (Apple HIG)
        static let minimumTouchTarget: CGFloat = 44.0
    }
    
    // MARK: - Storage Keys
    
    enum StorageKeys {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let preferredSessionMode = "preferredSessionMode"
        static let binauralPreset = "binauralPreset"
        static let lastSessionAffirmationIndex = "lastSessionAffirmationIndex"
        static let lastSessionBatchId = "lastSessionBatchId"
    }
    
    // MARK: - Keychain Keys
    
    enum KeychainKeys {
        static let voiceCloneId = "com.imprint.voiceCloneId"
        static let authToken = "com.imprint.authToken"
    }
    
    // MARK: - Notification Names
    
    enum NotificationNames {
        static let sessionDidComplete = Notification.Name("sessionDidComplete")
        static let affirmationDidChange = Notification.Name("affirmationDidChange")
        static let resonanceScoreUpdated = Notification.Name("resonanceScoreUpdated")
        static let subscriptionStatusChanged = Notification.Name("subscriptionStatusChanged")
    }
    
    // MARK: - API Configuration
    
    enum API {
        /// Request timeout interval (seconds)
        static let requestTimeout: TimeInterval = 30.0
        
        /// Maximum retry attempts for failed requests
        static let maxRetryAttempts = 3
        
        /// Delay between retry attempts (seconds)
        static let retryDelay: TimeInterval = 2.0
    }
    
    // MARK: - Firebase Collection Names
    
    enum FirebaseCollections {
        static let users = "users"
        static let prompts = "prompts"
        static let affirmations = "affirmations"
        static let progress = "progress"
        static let voiceProfiles = "voiceProfiles"
    }
}

// MARK: - Goal Categories

/// All available goal categories organized by group
enum GoalCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    
    // Core Identity
    case confidence = "Confidence"
    case purpose = "Purpose"
    case identity = "Identity"
    case growth = "Growth"
    case courage = "Courage"
    case resilience = "Resilience"
    case discipline = "Discipline"
    
    // Performance & Impact
    case focus = "Focus"
    case creativity = "Creativity"
    case abundance = "Abundance"
    case leadership = "Leadership"
    case success = "Success"
    case influence = "Influence"
    case energy = "Energy"
    
    // Well-being
    case health = "Health"
    case peace = "Peace"
    case vitality = "Vitality"
    case gratitude = "Gratitude"
    case balance = "Balance"
    case rest = "Rest"
    case clarity = "Clarity"
    
    // Faith & Bible-Based
    case faith = "Faith"
    case grace = "Grace"
    case wisdom = "Wisdom"
    case strength = "Strength"
    case provision = "Provision"
    case favor = "Favor"
    case healing = "Healing"
    case authority = "Authority"
    case victory = "Victory"
    case surrender = "Surrender"
    case righteousness = "Righteousness"
    case peaceFaith = "Peace (Faith)"
    case love = "Love"
    case patience = "Patience"
    case spirit = "Spirit"
    
    // Connection
    case relationships = "Relationships"
    case connection = "Connection"
    case unity = "Unity"
    case charisma = "Charisma"
    case forgiveness = "Forgiveness"
    case influenceConnection = "Influence (Connection)"
    
    var id: String { rawValue }
    
    /// The group this category belongs to
    var group: GoalGroup {
        switch self {
        case .confidence, .purpose, .identity, .growth, .courage, .resilience, .discipline:
            return .coreIdentity
        case .focus, .creativity, .abundance, .leadership, .success, .influence, .energy:
            return .performanceAndImpact
        case .health, .peace, .vitality, .gratitude, .balance, .rest, .clarity:
            return .wellBeing
        case .faith, .grace, .wisdom, .strength, .provision, .favor, .healing,
             .authority, .victory, .surrender, .righteousness, .peaceFaith,
             .love, .patience, .spirit:
            return .faithBased
        case .relationships, .connection, .unity, .charisma, .forgiveness, .influenceConnection:
            return .connection
        }
    }
    
    /// SF Symbol icon for the category
    var iconName: String {
        switch self {
        case .confidence: return "star.fill"
        case .purpose: return "target"
        case .identity: return "person.fill"
        case .growth: return "leaf.fill"
        case .courage: return "flame.fill"
        case .resilience: return "arrow.up.heart.fill"
        case .discipline: return "checkmark.seal.fill"
        case .focus: return "scope"
        case .creativity: return "paintbrush.fill"
        case .abundance: return "dollarsign.circle.fill"
        case .leadership: return "crown.fill"
        case .success: return "trophy.fill"
        case .influence: return "person.3.fill"
        case .energy: return "bolt.fill"
        case .health: return "heart.fill"
        case .peace: return "leaf.circle.fill"
        case .vitality: return "figure.run"
        case .gratitude: return "hands.clap.fill"
        case .balance: return "scale.3d"
        case .rest: return "moon.fill"
        case .clarity: return "eye.fill"
        case .faith: return "book.closed.fill"
        case .grace: return "sparkles"
        case .wisdom: return "lightbulb.fill"
        case .strength: return "figure.strengthtraining.traditional"
        case .provision: return "basket.fill"
        case .favor: return "hand.thumbsup.fill"
        case .healing: return "cross.circle.fill"
        case .authority: return "shield.fill"
        case .victory: return "flag.fill"
        case .surrender: return "hands.and.sparkles.fill"
        case .righteousness: return "scale.3d"
        case .peaceFaith: return "dove.fill"
        case .love: return "heart.circle.fill"
        case .patience: return "clock.fill"
        case .spirit: return "wind"
        case .relationships: return "heart.text.square.fill"
        case .connection: return "link"
        case .unity: return "person.2.fill"
        case .charisma: return "sparkle"
        case .forgiveness: return "arrow.uturn.backward.circle.fill"
        case .influenceConnection: return "megaphone.fill"
        }
    }
}

// MARK: - Goal Groups

/// Groups for organizing goal categories
enum GoalGroup: String, CaseIterable, Identifiable, Sendable {
    case coreIdentity = "Core Identity"
    case performanceAndImpact = "Performance & Impact"
    case wellBeing = "Well-being"
    case faithBased = "Faith & Bible-Based"
    case connection = "Connection"
    
    var id: String { rawValue }
    
    /// Categories belonging to this group
    var categories: [GoalCategory] {
        GoalCategory.allCases.filter { $0.group == self }
    }
    
    /// Description of the group
    var description: String {
        switch self {
        case .coreIdentity:
            return "Build your foundation of self"
        case .performanceAndImpact:
            return "Achieve and influence"
        case .wellBeing:
            return "Nurture mind and body"
        case .faithBased:
            return "Strengthen your spiritual walk"
        case .connection:
            return "Deepen relationships"
        }
    }
}
