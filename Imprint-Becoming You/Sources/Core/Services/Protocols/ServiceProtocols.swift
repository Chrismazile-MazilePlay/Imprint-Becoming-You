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
    func generateAffirmations(forGoals goals: [String], count: Int) async throws -> [String]
    
    /// Generates affirmations from a custom prompt
    func generateAffirmations(fromPrompt prompt: String, count: Int) async throws -> [String]
    
    /// Loads offline affirmations for the given categories
    func loadOfflineAffirmations(forCategories categories: [String]) -> [String]
    
    /// Whether online generation is available
    var isOnlineAvailable: Bool { get async }
}

// MARK: - Voice Clone Service Protocol

/// Protocol for voice cloning via ElevenLabs
protocol VoiceCloneServiceProtocol: AnyObject, Sendable {
    
    /// Creates a voice clone from audio data
    func createVoiceClone(from audioData: Data, name: String) async throws -> String
    
    /// Deletes a voice clone
    func deleteVoiceClone(voiceId: String) async throws
    
    /// Validates that a voice clone still exists
    func validateVoiceClone(voiceId: String) async -> Bool
    
    /// Gets a preview audio sample for a voice
    func getVoicePreview(voiceId: String) async throws -> Data
}

// MARK: - Auth Service Protocol

/// Protocol for authentication services
protocol AuthServiceProtocol: AnyObject, Sendable {
    
    var currentUserId: String? { get }
    var isAuthenticated: Bool { get }
    
    func signInWithApple() async throws -> String
    func signInWithGoogle() async throws -> String
    func signIn(email: String, password: String) async throws -> String
    func createAccount(email: String, password: String) async throws -> String
    func signOut() async throws
    func deleteAccount() async throws
    func sendPasswordReset(to email: String) async throws
    
    var authStateStream: AsyncStream<String?> { get }
}

// MARK: - Sync Service Protocol

/// Protocol for data synchronization with Firebase
protocol SyncServiceProtocol: AnyObject, Sendable {
    
    func syncToCloud(userId: String) async throws
    func syncFromCloud(userId: String) async throws
    func sync(_ dataType: SyncDataType, userId: String) async throws
    
    var isSyncing: Bool { get }
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
    
    var isPremium: Bool { get async }
    var subscriptionStatus: SubscriptionStatus { get async }
    
    func getProducts() async throws -> [SubscriptionProduct]
    func purchase(productId: String) async throws
    func restorePurchases() async throws
    
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
    
    func getCachedAudio(forText text: String, voiceId: String) async -> Data?
    
    @discardableResult
    func cacheAudio(_ data: Data, forText text: String, voiceId: String) async throws -> String
    
    func removeCachedAudio(fileName: String) async
    func clearCache() async
    
    var cacheSize: Int64 { get async }
    var maxCacheSize: Int64 { get }
}

// MARK: - Mock Implementations

final class MockTTSService: TTSServiceProtocol, @unchecked Sendable {
    private let stateQueue = DispatchQueue(label: "com.imprint.mocktts")
    private var _isSpeaking: Bool = false
    
    var isSpeaking: Bool {
        stateQueue.sync { _isSpeaking }
    }
    
    func synthesize(text: String, voiceId: String?) async throws -> Data {
        try await Task.sleep(for: .milliseconds(500))
        return Data()
    }
    
    func speakText(_ text: String, voiceId: String?) async throws {
        stateQueue.sync { _isSpeaking = true }
        try await Task.sleep(for: .seconds(2))
        stateQueue.sync { _isSpeaking = false }
    }
    
    func stopSpeaking() async {
        stateQueue.sync { _isSpeaking = false }
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
    func validateVoiceClone(voiceId: String) async -> Bool { true }
    func getVoicePreview(voiceId: String) async throws -> Data { Data() }
}

final class MockAuthService: AuthServiceProtocol, @unchecked Sendable {
    private let stateQueue = DispatchQueue(label: "com.imprint.mockauth")
    private var _currentUserId: String?
    
    var currentUserId: String? {
        stateQueue.sync { _currentUserId }
    }
    
    var isAuthenticated: Bool {
        currentUserId != nil
    }
    
    lazy var authStateStream: AsyncStream<String?> = {
        AsyncStream { _ in }
    }()
    
    func signInWithApple() async throws -> String {
        let id = "apple-\(UUID().uuidString)"
        stateQueue.sync { _currentUserId = id }
        return id
    }
    
    func signInWithGoogle() async throws -> String {
        let id = "google-\(UUID().uuidString)"
        stateQueue.sync { _currentUserId = id }
        return id
    }
    
    func signIn(email: String, password: String) async throws -> String {
        let id = "email-\(UUID().uuidString)"
        stateQueue.sync { _currentUserId = id }
        return id
    }
    
    func createAccount(email: String, password: String) async throws -> String {
        let id = "email-\(UUID().uuidString)"
        stateQueue.sync { _currentUserId = id }
        return id
    }
    
    func signOut() async throws {
        stateQueue.sync { _currentUserId = nil }
    }
    
    func deleteAccount() async throws {
        stateQueue.sync { _currentUserId = nil }
    }
    
    func sendPasswordReset(to email: String) async throws {}
}

final class MockSyncService: SyncServiceProtocol, @unchecked Sendable {
    private let stateQueue = DispatchQueue(label: "com.imprint.mocksync")
    private var _isSyncing: Bool = false
    private var _lastSyncDate: Date?
    
    var isSyncing: Bool {
        stateQueue.sync { _isSyncing }
    }
    
    var lastSyncDate: Date? {
        stateQueue.sync { _lastSyncDate }
    }
    
    func syncToCloud(userId: String) async throws {
        stateQueue.sync { _isSyncing = true }
        try await Task.sleep(for: .seconds(1))
        stateQueue.sync {
            _lastSyncDate = Date()
            _isSyncing = false
        }
    }
    
    func syncFromCloud(userId: String) async throws {
        stateQueue.sync { _isSyncing = true }
        try await Task.sleep(for: .seconds(1))
        stateQueue.sync {
            _lastSyncDate = Date()
            _isSyncing = false
        }
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
    
    func getCachedAudio(forText text: String, voiceId: String) async -> Data? { nil }
    
    func cacheAudio(_ data: Data, forText text: String, voiceId: String) async throws -> String {
        "cached-\(UUID().uuidString).mp3"
    }
    
    func removeCachedAudio(fileName: String) async {}
    func clearCache() async {}
}

// MARK: - Production Implementations

final class TTSService: TTSServiceProtocol, @unchecked Sendable {
    
    /// System TTS service for offline speech
    private let systemTTS: SystemTTSService
    
    /// Audio cache manager
    private let cacheManager: AudioCacheManager
    
    init() {
        self.systemTTS = SystemTTSService()
        self.cacheManager = AudioCacheManager.shared
    }
    
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
    private let stateQueue = DispatchQueue(label: "com.imprint.authservice")
    private var _currentUserId: String?
    
    var currentUserId: String? {
        stateQueue.sync { _currentUserId }
    }
    
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
    private let stateQueue = DispatchQueue(label: "com.imprint.syncservice")
    private var _isSyncing: Bool = false
    private var _lastSyncDate: Date?
    
    var isSyncing: Bool {
        stateQueue.sync { _isSyncing }
    }
    
    var lastSyncDate: Date? {
        stateQueue.sync { _lastSyncDate }
    }
    
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
    
    private let cacheManager: AudioCacheManager
    
    init() {
        self.cacheManager = AudioCacheManager.shared
    }
    
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
