//
//  ServiceProtocols.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import Foundation

// MARK: - TTS Service Protocol

/// Protocol for text-to-speech services (System TTS and ElevenLabs)
protocol TTSServiceProtocol: AnyObject, Sendable {
    
    /// Synthesizes speech for the given text
    /// - Parameters:
    ///   - text: Text to synthesize
    ///   - voiceId: ElevenLabs voice ID (nil for system TTS)
    /// - Returns: Audio data
    /// - Throws: `AppError.elevenLabsError` or `AppError.audioPlaybackFailed`
    func synthesize(text: String, voiceId: String?) async throws -> Data
    
    /// Synthesizes and plays speech immediately
    /// - Parameters:
    ///   - text: Text to synthesize
    ///   - voiceId: ElevenLabs voice ID (nil for system TTS)
    func speakText(_ text: String, voiceId: String?) async throws
    
    /// Stops current speech
    func stopSpeaking() async
    
    /// Whether speech is currently playing
    var isSpeaking: Bool { get }
}

// MARK: - Affirmation Service Protocol

/// Protocol for affirmation generation and management
protocol AffirmationServiceProtocol: AnyObject, Sendable {
    
    /// Generates affirmations based on user's selected goals
    /// - Parameters:
    ///   - goals: Array of goal category identifiers
    ///   - count: Number of affirmations to generate
    /// - Returns: Array of generated affirmation texts
    /// - Throws: `AppError.affirmationGenerationFailed`
    func generateAffirmations(
        forGoals goals: [String],
        count: Int
    ) async throws -> [String]
    
    /// Generates affirmations from a custom prompt
    /// - Parameters:
    ///   - prompt: User's custom prompt text
    ///   - count: Number of affirmations to generate
    /// - Returns: Array of generated affirmation texts
    /// - Throws: `AppError.affirmationGenerationFailed`
    func generateAffirmations(
        fromPrompt prompt: String,
        count: Int
    ) async throws -> [String]
    
    /// Loads offline affirmations for the given categories
    /// - Parameter categories: Categories to load
    /// - Returns: Array of offline affirmation texts
    func loadOfflineAffirmations(
        forCategories categories: [String]
    ) -> [String]
    
    /// Whether online generation is available
    var isOnlineAvailable: Bool { get async }
}

// MARK: - Voice Clone Service Protocol

/// Protocol for voice cloning via ElevenLabs
protocol VoiceCloneServiceProtocol: AnyObject, Sendable {
    
    /// Creates a voice clone from audio data
    /// - Parameters:
    ///   - audioData: Audio recording data
    ///   - name: Name for the voice clone
    /// - Returns: Voice ID from ElevenLabs
    /// - Throws: `AppError.voiceCloningFailed`
    func createVoiceClone(
        from audioData: Data,
        name: String
    ) async throws -> String
    
    /// Deletes a voice clone
    /// - Parameter voiceId: Voice ID to delete
    func deleteVoiceClone(voiceId: String) async throws
    
    /// Validates that a voice clone still exists
    /// - Parameter voiceId: Voice ID to validate
    /// - Returns: Whether the voice exists
    func validateVoiceClone(voiceId: String) async -> Bool
    
    /// Gets a preview audio sample for a voice
    /// - Parameter voiceId: Voice ID to preview
    /// - Returns: Audio data of preview
    func getVoicePreview(voiceId: String) async throws -> Data
}

// MARK: - Auth Service Protocol

/// Protocol for authentication services
protocol AuthServiceProtocol: AnyObject, Sendable {
    
    /// Current user ID (nil if not authenticated)
    var currentUserId: String? { get }
    
    /// Whether user is authenticated
    var isAuthenticated: Bool { get }
    
    /// Signs in with Apple
    /// - Returns: User ID
    func signInWithApple() async throws -> String
    
    /// Signs in with Google
    /// - Returns: User ID
    func signInWithGoogle() async throws -> String
    
    /// Signs in with email/password
    /// - Parameters:
    ///   - email: User email
    ///   - password: User password
    /// - Returns: User ID
    func signIn(email: String, password: String) async throws -> String
    
    /// Creates account with email/password
    /// - Parameters:
    ///   - email: User email
    ///   - password: User password
    /// - Returns: User ID
    func createAccount(email: String, password: String) async throws -> String
    
    /// Signs out current user
    func signOut() async throws
    
    /// Deletes current user account
    func deleteAccount() async throws
    
    /// Sends password reset email
    /// - Parameter email: User email
    func sendPasswordReset(to email: String) async throws
    
    /// Auth state change stream
    var authStateStream: AsyncStream<String?> { get }
}

// MARK: - Sync Service Protocol

/// Protocol for data synchronization with Firebase
protocol SyncServiceProtocol: AnyObject, Sendable {
    
    /// Syncs all user data to Firebase
    /// - Parameter userId: Firebase user ID
    func syncToCloud(userId: String) async throws
    
    /// Downloads user data from Firebase
    /// - Parameter userId: Firebase user ID
    func syncFromCloud(userId: String) async throws
    
    /// Syncs a specific data type
    /// - Parameters:
    ///   - dataType: Type of data to sync
    ///   - userId: Firebase user ID
    func sync(_ dataType: SyncDataType, userId: String) async throws
    
    /// Whether sync is in progress
    var isSyncing: Bool { get }
    
    /// Last sync timestamp
    var lastSyncDate: Date? { get }
}

/// Types of data that can be synced
enum SyncDataType: String, Sendable {
    case userProfile
    case customPrompts
    case affirmations
    case progress
    case voiceProfiles
}

// MARK: - Subscription Service Protocol

/// Protocol for StoreKit subscription management
protocol SubscriptionServiceProtocol: AnyObject, Sendable {
    
    /// Whether user has active premium subscription
    var isPremium: Bool { get async }
    
    /// Current subscription status
    var subscriptionStatus: SubscriptionStatus { get async }
    
    /// Available products for purchase
    func getProducts() async throws -> [SubscriptionProduct]
    
    /// Purchases a subscription
    /// - Parameter productId: Product identifier
    func purchase(productId: String) async throws
    
    /// Restores purchases
    func restorePurchases() async throws
    
    /// Subscription status stream
    var statusStream: AsyncStream<SubscriptionStatus> { get }
}

/// Subscription status
enum SubscriptionStatus: String, Sendable {
    case notSubscribed
    case subscribed
    case expired
    case inGracePeriod
}

/// Subscription product info
struct SubscriptionProduct: Identifiable, Sendable {
    let id: String
    let displayName: String
    let description: String
    let displayPrice: String
    let period: SubscriptionPeriod
}

/// Subscription period
enum SubscriptionPeriod: String, Sendable {
    case monthly
    case annual
}

// MARK: - Audio Cache Service Protocol

/// Protocol for managing cached audio files
protocol AudioCacheServiceProtocol: AnyObject, Sendable {
    
    /// Gets cached audio for an affirmation
    /// - Parameters:
    ///   - text: Affirmation text
    ///   - voiceId: Voice ID
    /// - Returns: Cached audio data if available
    func getCachedAudio(forText text: String, voiceId: String) async -> Data?
    
    /// Caches audio data
    /// - Parameters:
    ///   - data: Audio data
    ///   - text: Affirmation text
    ///   - voiceId: Voice ID
    /// - Returns: Filename of cached file
    @discardableResult
    func cacheAudio(_ data: Data, forText text: String, voiceId: String) async throws -> String
    
    /// Removes cached audio
    /// - Parameter fileName: File to remove
    func removeCachedAudio(fileName: String) async
    
    /// Clears all cached audio
    func clearCache() async
    
    /// Current cache size in bytes
    var cacheSize: Int64 { get async }
    
    /// Maximum cache size in bytes
    var maxCacheSize: Int64 { get }
}

// MARK: - Mock Implementations

final class MockTTSService: TTSServiceProtocol, @unchecked Sendable {
    var isSpeaking: Bool = false
    
    func synthesize(text: String, voiceId: String?) async throws -> Data {
        try await Task.sleep(for: .milliseconds(500))
        return Data()
    }
    
    func speakText(_ text: String, voiceId: String?) async throws {
        isSpeaking = true
        try await Task.sleep(for: .seconds(2))
        isSpeaking = false
    }
    
    func stopSpeaking() async {
        isSpeaking = false
    }
}

final class MockAffirmationService: AffirmationServiceProtocol, @unchecked Sendable {
    var isOnlineAvailable: Bool {
        get async { true }
    }
    
    func generateAffirmations(forGoals goals: [String], count: Int) async throws -> [String] {
        try await Task.sleep(for: .seconds(1))
        return (0..<count).map { "I am affirmation \($0 + 1)" }
    }
    
    func generateAffirmations(fromPrompt prompt: String, count: Int) async throws -> [String] {
        try await Task.sleep(for: .seconds(1))
        return (0..<count).map { "Custom affirmation \($0 + 1) for: \(prompt)" }
    }
    
    func loadOfflineAffirmations(forCategories categories: [String]) -> [String] {
        Affirmation.samples.map(\.text)
    }
}

final class MockVoiceCloneService: VoiceCloneServiceProtocol, @unchecked Sendable {
    func createVoiceClone(from audioData: Data, name: String) async throws -> String {
        try await Task.sleep(for: .seconds(3))
        return "mock-voice-id-\(UUID().uuidString.prefix(8))"
    }
    
    func deleteVoiceClone(voiceId: String) async throws {}
    
    func validateVoiceClone(voiceId: String) async -> Bool {
        true
    }
    
    func getVoicePreview(voiceId: String) async throws -> Data {
        Data()
    }
}

final class MockAuthService: AuthServiceProtocol, @unchecked Sendable {
    var currentUserId: String?
    var isAuthenticated: Bool { currentUserId != nil }
    
    lazy var authStateStream: AsyncStream<String?> = {
        AsyncStream { _ in }
    }()
    
    func signInWithApple() async throws -> String {
        let id = "apple-\(UUID().uuidString)"
        currentUserId = id
        return id
    }
    
    func signInWithGoogle() async throws -> String {
        let id = "google-\(UUID().uuidString)"
        currentUserId = id
        return id
    }
    
    func signIn(email: String, password: String) async throws -> String {
        let id = "email-\(UUID().uuidString)"
        currentUserId = id
        return id
    }
    
    func createAccount(email: String, password: String) async throws -> String {
        let id = "email-\(UUID().uuidString)"
        currentUserId = id
        return id
    }
    
    func signOut() async throws {
        currentUserId = nil
    }
    
    func deleteAccount() async throws {
        currentUserId = nil
    }
    
    func sendPasswordReset(to email: String) async throws {}
}

final class MockSyncService: SyncServiceProtocol, @unchecked Sendable {
    var isSyncing: Bool = false
    var lastSyncDate: Date?
    
    func syncToCloud(userId: String) async throws {
        isSyncing = true
        try await Task.sleep(for: .seconds(1))
        lastSyncDate = Date()
        isSyncing = false
    }
    
    func syncFromCloud(userId: String) async throws {
        isSyncing = true
        try await Task.sleep(for: .seconds(1))
        lastSyncDate = Date()
        isSyncing = false
    }
    
    func sync(_ dataType: SyncDataType, userId: String) async throws {
        try await Task.sleep(for: .milliseconds(500))
    }
}

final class MockSubscriptionService: SubscriptionServiceProtocol, @unchecked Sendable {
    var isPremium: Bool {
        get async { false }
    }
    
    var subscriptionStatus: SubscriptionStatus {
        get async { .notSubscribed }
    }
    
    lazy var statusStream: AsyncStream<SubscriptionStatus> = {
        AsyncStream { _ in }
    }()
    
    func getProducts() async throws -> [SubscriptionProduct] {
        [
            SubscriptionProduct(
                id: "com.imprint.monthly",
                displayName: "Monthly",
                description: "Billed monthly",
                displayPrice: "$9.99",
                period: .monthly
            ),
            SubscriptionProduct(
                id: "com.imprint.annual",
                displayName: "Annual",
                description: "Billed annually",
                displayPrice: "$79.99",
                period: .annual
            )
        ]
    }
    
    func purchase(productId: String) async throws {}
    func restorePurchases() async throws {}
}

final class MockAudioCacheService: AudioCacheServiceProtocol, @unchecked Sendable {
    var maxCacheSize: Int64 = Constants.Cache.maxAudioCacheSize
    
    var cacheSize: Int64 {
        get async { 0 }
    }
    
    func getCachedAudio(forText text: String, voiceId: String) async -> Data? {
        nil
    }
    
    func cacheAudio(_ data: Data, forText text: String, voiceId: String) async throws -> String {
        "cached-\(UUID().uuidString).mp3"
    }
    
    func removeCachedAudio(fileName: String) async {}
    func clearCache() async {}
}

// MARK: - Placeholder Implementations

final class TTSService: TTSServiceProtocol, @unchecked Sendable {
    
    /// System TTS service for offline speech
    private let systemTTS = SystemTTSService()
    
    /// Audio cache manager
    private let cacheManager = AudioCacheManager.shared
    
    var isSpeaking: Bool {
        systemTTS.isSpeaking
    }
    
    func synthesize(text: String, voiceId: String?) async throws -> Data {
        // If voiceId is provided, use ElevenLabs (Phase 5)
        if let voiceId = voiceId {
            // Check cache first
            if let cachedData = await cacheManager.getCachedAudio(forText: text, voiceId: voiceId) {
                return cachedData
            }
            
            // TODO: Phase 5 - ElevenLabs API call
            throw AppError.notImplemented(feature: "ElevenLabs TTS")
        }
        
        // Use system TTS
        return try await systemTTS.synthesizeToData(text)
    }
    
    func speakText(_ text: String, voiceId: String?) async throws {
        // If voiceId is provided, use ElevenLabs (Phase 5)
        if voiceId != nil {
            throw AppError.notImplemented(feature: "ElevenLabs TTS Playback")
        }
        
        // Use system TTS
        try await systemTTS.speak(text)
    }
    
    func stopSpeaking() async {
        systemTTS.stopSpeaking()
    }
}

final class AffirmationService: AffirmationServiceProtocol, @unchecked Sendable {
    var isOnlineAvailable: Bool {
        get async { false }
    }
    
    func generateAffirmations(forGoals goals: [String], count: Int) async throws -> [String] {
        throw AppError.notImplemented(feature: "Affirmation Generation")
    }
    
    func generateAffirmations(fromPrompt prompt: String, count: Int) async throws -> [String] {
        throw AppError.notImplemented(feature: "Affirmation Generation")
    }
    
    func loadOfflineAffirmations(forCategories categories: [String]) -> [String] {
        // TODO: Load from OfflineAffirmations.json
        []
    }
}

final class VoiceCloneService: VoiceCloneServiceProtocol, @unchecked Sendable {
    func createVoiceClone(from audioData: Data, name: String) async throws -> String {
        throw AppError.notImplemented(feature: "Voice Cloning")
    }
    
    func deleteVoiceClone(voiceId: String) async throws {}
    func validateVoiceClone(voiceId: String) async -> Bool { false }
    
    func getVoicePreview(voiceId: String) async throws -> Data {
        throw AppError.notImplemented(feature: "Voice Preview")
    }
}

final class AuthService: AuthServiceProtocol, @unchecked Sendable {
    var currentUserId: String?
    var isAuthenticated: Bool { currentUserId != nil }
    
    lazy var authStateStream: AsyncStream<String?> = {
        AsyncStream { _ in }
    }()
    
    func signInWithApple() async throws -> String {
        throw AppError.notImplemented(feature: "Apple Sign In")
    }
    
    func signInWithGoogle() async throws -> String {
        throw AppError.notImplemented(feature: "Google Sign In")
    }
    
    func signIn(email: String, password: String) async throws -> String {
        throw AppError.notImplemented(feature: "Email Sign In")
    }
    
    func createAccount(email: String, password: String) async throws -> String {
        throw AppError.notImplemented(feature: "Account Creation")
    }
    
    func signOut() async throws {}
    func deleteAccount() async throws {}
    func sendPasswordReset(to email: String) async throws {}
}

final class SyncService: SyncServiceProtocol, @unchecked Sendable {
    var isSyncing: Bool = false
    var lastSyncDate: Date?
    
    func syncToCloud(userId: String) async throws {
        throw AppError.notImplemented(feature: "Cloud Sync")
    }
    
    func syncFromCloud(userId: String) async throws {
        throw AppError.notImplemented(feature: "Cloud Sync")
    }
    
    func sync(_ dataType: SyncDataType, userId: String) async throws {
        throw AppError.notImplemented(feature: "Cloud Sync")
    }
}

final class SubscriptionService: SubscriptionServiceProtocol, @unchecked Sendable {
    var isPremium: Bool {
        get async { false }
    }
    
    var subscriptionStatus: SubscriptionStatus {
        get async { .notSubscribed }
    }
    
    lazy var statusStream: AsyncStream<SubscriptionStatus> = {
        AsyncStream { _ in }
    }()
    
    func getProducts() async throws -> [SubscriptionProduct] {
        throw AppError.notImplemented(feature: "Subscriptions")
    }
    
    func purchase(productId: String) async throws {
        throw AppError.notImplemented(feature: "Subscriptions")
    }
    
    func restorePurchases() async throws {
        throw AppError.notImplemented(feature: "Subscriptions")
    }
}

final class AudioCacheService: AudioCacheServiceProtocol, @unchecked Sendable {
    
    /// The underlying cache manager
    private let cacheManager = AudioCacheManager.shared
    
    var maxCacheSize: Int64 {
        cacheManager.maxCacheSize
    }
    
    var cacheSize: Int64 {
        get async {
            await cacheManager.cacheSize
        }
    }
    
    func getCachedAudio(forText text: String, voiceId: String) async -> Data? {
        await cacheManager.getCachedAudio(forText: text, voiceId: voiceId)
    }
    
    func cacheAudio(_ data: Data, forText text: String, voiceId: String) async throws -> String {
        try await cacheManager.cacheAudio(data, forText: text, voiceId: voiceId)
    }
    
    func removeCachedAudio(fileName: String) async {
        await cacheManager.removeCachedAudio(fileName: fileName)
    }
    
    func clearCache() async {
        await cacheManager.clearCache()
    }
}
