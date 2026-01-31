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
        /// Number of affirmations fetched from database per batch.
        /// This is the pool of affirmations available for practice.
        static let batchSize = 30
        
        /// Number of affirmations per non-default mode session.
        /// After completing this many, the session ends and user returns to home.
        static let sessionSize = 10
        
        /// Index at which to trigger next batch fetch (proactive refresh).
        /// When batchConsumed >= this value, fetch next batch in background.
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
    
    // MARK: - Session Preparation (TTS Pre-Synthesis)
    
    /// Configuration for session TTS pre-synthesis with bounded parallel execution.
    ///
    /// ## Design Rationale
    /// The Apple Neural Engine (ANE) performs best with controlled parallelism.
    /// Based on WWDC 2023 guidance and empirical testing:
    /// - 3 concurrent tasks provides optimal ANE throughput
    /// - Higher concurrency causes resource contention and thermal throttling
    /// - ~3 affirmations/second synthesis rate with parallel execution
    ///
    /// ## Progress Bar Phases
    /// ```
    /// Phase 0: Immediate       0% → 2%     Instant (feels responsive)
    /// Phase 1: Kokoro Warmup   2% → 15%    ~1-9 seconds (depending on state)
    /// Phase 2: Synthesis      15% → 99%    totalAffirmations / 3.0 seconds
    /// Phase 3: Complete       99% → 100%   On true completion only
    /// ```
    ///
    /// ## Buffer Safety Math
    /// ```
    /// Synthesis rate: ~3 affirmations/second (with 3 concurrent tasks)
    /// User consumption: ~1 affirmation/second (absolute maximum)
    /// Net buffer growth: +2 affirmations/second
    ///
    /// Starting with 15 ready: User can NEVER catch up to unsynthesized content
    /// ```
    enum SessionPreparation {
        /// Maximum concurrent TTS synthesis tasks.
        /// Tuned for ANE (Apple Neural Engine) throughput - 3 provides optimal
        /// parallelism without resource contention or thermal throttling.
        static let maxConcurrency = 3
        
        /// Number of affirmations required before "Start Now" button enables.
        /// At 3 concurrent synthesis (~3/sec), this takes ~5 seconds to reach.
        static let readyToStartThreshold = 15
        
        /// Session size threshold for showing "Start Now" button.
        /// Sessions with more than this many affirmations show the early start option.
        /// Sessions ≤30 can fully synthesize within the 10-second timeout.
        static let largeSessionThreshold = 30
        
        /// Maximum wait time for initial preparation (seconds).
        /// After this timeout, session starts with whatever is ready.
        /// At 3 concurrent synthesis rate (~3/sec), this yields ~30 affirmations.
        static let timeoutSeconds: TimeInterval = 10.0
        
        /// Maximum wait time for Kokoro warm-up before showing fallback options (seconds).
        static let kokoroWarmupTimeout: TimeInterval = 12.0
        
        /// Estimated Kokoro warm-up duration for progress estimation (seconds).
        static let estimatedKokoroWarmupSeconds: TimeInterval = 9.0
        
        /// Duration to animate warm-up phase when Kokoro is already ready (seconds).
        /// Provides a quick but visible animation instead of jumping.
        static let fastWarmupAnimationDuration: TimeInterval = 1.5
        
        /// Expected synthesis rate (affirmations per second) with parallel execution.
        /// Used for progress estimation and buffer calculations.
        static let expectedSynthesisRate: Double = 3.0
        
        /// Minimum delay between background synthesis tasks (milliseconds).
        /// Prevents overwhelming the system during background synthesis.
        static let backgroundThrottleMs: Int = 50
        
        /// Progress bar animation update interval (60fps).
        static let progressAnimationInterval: TimeInterval = 1.0 / 60.0
        
        /// Progress bar easing factor for smooth catch-up animation.
        /// Higher = faster catch-up, lower = smoother.
        static let progressEasingFactor: CGFloat = 0.08
        
        // MARK: - Progress Phase Weights
        
        /// Immediate start progress (feels responsive).
        static let immediateProgress: CGFloat = 0.02
        
        /// Progress allocated to warm-up phase (0% → 15%).
        static let warmupPhaseWeight: CGFloat = 0.13  // 2% → 15%
        
        /// Progress allocated to synthesis phase (15% → 99%).
        static let synthesisPhaseWeight: CGFloat = 0.84  // 15% → 99%
        
        /// Maximum progress before completion (never show 100% until truly done).
        static let maxPreCompleteProgress: CGFloat = 0.99
        
        // MARK: - Status Messages
        
        /// Status messages shown during Kokoro warm-up phase.
        static let warmupStatusMessages: [String] = [
            "Getting things ready...",
            "Just a moment...",
            "Preparing your experience..."
        ]
        
        /// Status messages shown during synthesis phase.
        static let synthesisStatusMessages: [String] = [
            "Building your session...",
            "Almost there...",
            "Putting finishing touches..."
        ]
        
        /// Interval between status message changes (seconds).
        static let statusMessageInterval: TimeInterval = 2.5
    }
    
    // MARK: - Background & Lifecycle
    
    /// Constants for app background behavior and lifecycle management.
    ///
    /// These values control how the app responds when returning from background
    /// after various durations. Memory management and session state are affected.
    enum Background {
        /// Time in background after which active sessions are reset to home.
        /// Summary view is always dismissed on background return regardless of duration.
        static let sessionTimeout: TimeInterval = 600 // 10 minutes
        
        /// Time in background after which we release heavy resources (Kokoro ML models).
        /// This is shorter than session timeout to free memory proactively.
        static let memoryReleaseThreshold: TimeInterval = 300 // 5 minutes
        
        /// Time in background before considering app as "cold started".
        /// After this duration, app may need full re-initialization.
        static let coldStartThreshold: TimeInterval = 1800 // 30 minutes
    }
    
    // MARK: - UI Timing
    
    /// Timing constants for UI animations and interactions.
    ///
    /// These values ensure consistent feel across the app for animations,
    /// debouncing, and loading indicators.
    enum UITiming {
        /// Duration for standard animations (e.g., dock selector transitions).
        static let standardAnimationDuration: TimeInterval = 0.35
        
        /// Duration for slow/emphasized animations.
        static let slowAnimationDuration: TimeInterval = 0.5
        
        /// Debounce delay for search/filter inputs.
        static let debounceDelay: TimeInterval = 0.3
        
        /// Delay before showing loading indicators.
        static let loadingIndicatorDelay: TimeInterval = 0.5
        
        /// Spring animation response for selector animations.
        static let springResponse: Double = 0.35
        
        /// Spring animation damping fraction for selector animations.
        static let springDamping: Double = 0.8
    }
    
    // MARK: - Dock Component Sizes
    
    /// Layout constants for the adaptive dock component.
    ///
    /// These values control sizing and alignment within the dock.
    enum DockSizes {
        /// Alignment inset for progress/button edges.
        /// Small value keeps alignment subtle while maintaining width.
        static let alignmentInset: CGFloat = 4
        
        /// Minimum width for center content slot (waveform area).
        static let centerContentMinWidth: CGFloat = 80
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
        
        /// Maximum number of saved sessions for free users.
        /// Premium users have unlimited saved sessions.
        static let maxSavedSessions = 3
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
        
        /// Counter for auto-generating saved session names ("Session 1", "Session 2", etc.)
        /// Persists across app launches and saved session deletions.
        static let savedSessionCounter = "savedSessionCounter"
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
        static let kokoroTTSReady = Notification.Name("kokoroTTSReady")
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
    
    // MARK: - Content Refresh
    
    enum ContentRefresh {
        /// Minimum view count before category is considered "depleted"
        /// When all affirmations in a category have viewCount >= this value,
        /// the app will generate fresh content when online.
        static let depletedViewCountThreshold = 3
    }
}

// MARK: - Goal Categories

/// All available goal categories organized by group.
///
/// ## Category Count: 41
/// - Core Identity: 7
/// - Performance & Impact: 7
/// - Well-being: 7
/// - Faith & Bible-Based: 15
/// - Connection: 5
///
/// ## Content per Category
/// - Secular categories: 20 affirmations each
/// - Faith categories: 40 items each (20 affirmations + 20 scripture verses)
enum GoalCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    
    // MARK: - Core Identity (7)
    
    case confidence = "Confidence"
    case purpose = "Purpose"
    case identity = "Identity"
    case growth = "Growth"
    case courage = "Courage"
    case resilience = "Resilience"
    case discipline = "Discipline"
    
    // MARK: - Performance & Impact (7)
    
    case focus = "Focus"
    case creativity = "Creativity"
    case abundance = "Abundance"
    case leadership = "Leadership"
    case success = "Success"
    case influence = "Influence"
    case energy = "Energy"
    
    // MARK: - Well-being (7)
    
    case health = "Health"
    case peace = "Peace"
    case vitality = "Vitality"
    case gratitude = "Gratitude"
    case balance = "Balance"
    case rest = "Rest"
    case clarity = "Clarity"
    
    // MARK: - Faith & Bible-Based (15)
    
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
    case divinePeace = "Divine Peace"
    case love = "Love"
    case patience = "Patience"
    case spirit = "Spirit"
    
    // MARK: - Connection (5)
    
    case relationships = "Relationships"
    case connection = "Connection"
    case unity = "Unity"
    case charisma = "Charisma"
    case forgiveness = "Forgiveness"
    
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
             .authority, .victory, .surrender, .righteousness, .divinePeace,
             .love, .patience, .spirit:
            return .faithBased
        case .relationships, .connection, .unity, .charisma, .forgiveness:
            return .connection
        }
    }
    
    /// SF Symbol icon for the category
    var iconName: String {
        switch self {
        // Core Identity
        case .confidence: return "star.fill"
        case .purpose: return "target"
        case .identity: return "person.fill"
        case .growth: return "leaf.fill"
        case .courage: return "flame.fill"
        case .resilience: return "arrow.up.heart.fill"
        case .discipline: return "checkmark.seal.fill"
        // Performance & Impact
        case .focus: return "scope"
        case .creativity: return "paintbrush.fill"
        case .abundance: return "dollarsign.circle.fill"
        case .leadership: return "crown.fill"
        case .success: return "trophy.fill"
        case .influence: return "person.3.fill"
        case .energy: return "bolt.fill"
        // Well-being
        case .health: return "heart.fill"
        case .peace: return "leaf.circle.fill"
        case .vitality: return "figure.run"
        case .gratitude: return "hands.clap.fill"
        case .balance: return "scale.3d"
        case .rest: return "moon.fill"
        case .clarity: return "eye.fill"
        // Faith & Bible-Based
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
        case .divinePeace: return "bird.fill"  // Fixed: "dove.fill" doesn't exist in SF Symbols
        case .love: return "heart.circle.fill"
        case .patience: return "clock.fill"
        case .spirit: return "wind"
        // Connection
        case .relationships: return "heart.text.square.fill"
        case .connection: return "link"
        case .unity: return "person.2.fill"
        case .charisma: return "sparkle"
        case .forgiveness: return "arrow.uturn.backward.circle.fill"
        }
    }
    
    /// Whether this category is faith-based
    var isFaithBased: Bool {
        group == .faithBased
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
