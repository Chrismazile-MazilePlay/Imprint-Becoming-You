//
//  DependencyContainer.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import SwiftUI
import SwiftData

// MARK: - Dependency Container

/// Central dependency injection container for the Imprint app.
///
/// Provides both production and preview implementations of all services.
/// Uses environment-based injection for SwiftUI views.
///
/// **Important:** This class is `@MainActor` isolated because most services
/// require MainActor access (audio, speech recognition, etc.).
///
/// ## Usage in Views
/// ```swift
/// struct MyView: View {
///     @Environment(\.dependencies) private var dependencies
///
///     var body: some View {
///         Text("Hello")
///             .onAppear {
///                 dependencies.audioService.play()
///             }
///     }
/// }
/// ```
///
/// ## Repository Pattern
/// For SwiftData-dependent services like `AffirmationRepository`, use the factory methods:
/// ```swift
/// @Environment(\.modelContext) private var modelContext
///
/// let repository = dependencies.makeAffirmationRepository(modelContext: modelContext)
/// ```
@MainActor
final class DependencyContainer: Sendable {
    
    // MARK: - Singleton
    
    /// Shared container for production use
    static let shared = DependencyContainer(isPreview: false)
    
    /// Preview container with mock services
    static let preview = DependencyContainer(isPreview: true)
    
    // MARK: - Properties
    
    /// Whether this container is for previews
    let isPreview: Bool
    
    // MARK: - Services (Lazy Initialization)
    
    /// Audio playback and binaural beat service
    private var _audioService: (any AudioServiceProtocol)?
    var audioService: any AudioServiceProtocol {
        if _audioService == nil {
            _audioService = isPreview ? MockAudioService() : AudioService()
        }
        return _audioService!
    }
    
    /// Speech recognition and analysis service
    private var _speechAnalysisService: (any SpeechAnalysisServiceProtocol)?
    var speechAnalysisService: any SpeechAnalysisServiceProtocol {
        if _speechAnalysisService == nil {
            _speechAnalysisService = isPreview ? MockSpeechAnalysisService() : SpeechAnalysisService()
        }
        return _speechAnalysisService!
    }
    
    /// Text-to-speech service
    private var _ttsService: (any TTSServiceProtocol)?
    var ttsService: any TTSServiceProtocol {
        if _ttsService == nil {
            _ttsService = isPreview ? MockTTSService() : TTSService()
        }
        return _ttsService!
    }
    
    /// Affirmation generation and management service
    private var _affirmationService: (any AffirmationServiceProtocol)?
    var affirmationService: any AffirmationServiceProtocol {
        if _affirmationService == nil {
            _affirmationService = isPreview ? MockAffirmationService() : AffirmationService()
        }
        return _affirmationService!
    }
    
    /// Voice cloning service
    private var _voiceCloneService: (any VoiceCloneServiceProtocol)?
    var voiceCloneService: any VoiceCloneServiceProtocol {
        if _voiceCloneService == nil {
            _voiceCloneService = isPreview ? MockVoiceCloneService() : VoiceCloneService()
        }
        return _voiceCloneService!
    }
    
    /// Authentication service
    private var _authService: (any AuthServiceProtocol)?
    var authService: any AuthServiceProtocol {
        if _authService == nil {
            _authService = isPreview ? MockAuthService() : AuthService()
        }
        return _authService!
    }
    
    /// Data synchronization service
    private var _syncService: (any SyncServiceProtocol)?
    var syncService: any SyncServiceProtocol {
        if _syncService == nil {
            _syncService = isPreview ? MockSyncService() : SyncService()
        }
        return _syncService!
    }
    
    /// Subscription/StoreKit service
    private var _subscriptionService: (any SubscriptionServiceProtocol)?
    var subscriptionService: any SubscriptionServiceProtocol {
        if _subscriptionService == nil {
            _subscriptionService = isPreview ? MockSubscriptionService() : SubscriptionService()
        }
        return _subscriptionService!
    }
    
    /// Audio caching service
    private var _audioCacheService: (any AudioCacheServiceProtocol)?
    var audioCacheService: any AudioCacheServiceProtocol {
        if _audioCacheService == nil {
            _audioCacheService = isPreview ? MockAudioCacheService() : AudioCacheService()
        }
        return _audioCacheService!
    }
    
    // MARK: - Initialization
    
    private init(isPreview: Bool) {
        self.isPreview = isPreview
    }
    
    // MARK: - Repository Factory Methods
    
    /// Creates an affirmation repository for the given model context.
    ///
    /// For production, returns a real `AffirmationRepository`.
    /// For previews, returns a `MockAffirmationRepository`.
    ///
    /// - Parameter modelContext: SwiftData model context
    /// - Returns: Repository conforming to `AffirmationRepositoryProtocol`
    func makeAffirmationRepository(modelContext: ModelContext) -> any AffirmationRepositoryProtocol {
        if isPreview {
            return MockAffirmationRepository()
        }
        return AffirmationRepository(modelContext: modelContext)
    }
    
    /// Creates an offline content loader.
    ///
    /// Note: The loader should be created ad-hoc when needed since its methods
    /// require `@MainActor` isolation and a `ModelContext`.
    ///
    /// - Returns: A new `OfflineContentLoader` instance
    func makeOfflineContentLoader() -> OfflineContentLoader {
        OfflineContentLoader()
    }
    
    // MARK: - Service Registration (for testing)
    
    /// Registers a custom audio service (useful for testing)
    func register(audioService: any AudioServiceProtocol) {
        _audioService = audioService
    }
    
    /// Registers a custom speech analysis service
    func register(speechAnalysisService: any SpeechAnalysisServiceProtocol) {
        _speechAnalysisService = speechAnalysisService
    }
    
    /// Registers a custom TTS service
    func register(ttsService: any TTSServiceProtocol) {
        _ttsService = ttsService
    }
    
    /// Registers a custom affirmation service
    func register(affirmationService: any AffirmationServiceProtocol) {
        _affirmationService = affirmationService
    }
    
    /// Registers a custom auth service
    func register(authService: any AuthServiceProtocol) {
        _authService = authService
    }
}

// MARK: - Environment Key

/// Environment key for dependency container
/// Uses @preconcurrency to bridge MainActor-isolated default value with nonisolated protocol requirement
private struct DependencyContainerKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue = DependencyContainer.shared
}

extension EnvironmentValues {
    /// Access to the dependency container
    @MainActor
    var dependencies: DependencyContainer {
        get { self[DependencyContainerKey.self] }
        set { self[DependencyContainerKey.self] = newValue }
    }
}

// MARK: - View Extensions

extension View {
    /// Injects dependencies into the view hierarchy
    @MainActor
    func withDependencies(_ container: DependencyContainer) -> some View {
        environment(\.dependencies, container)
    }
    
    /// Injects shared dependencies into the view hierarchy
    @MainActor
    func withDependencies() -> some View {
        environment(\.dependencies, .shared)
    }
    
    /// Injects preview dependencies with mock services
    @MainActor
    func withPreviewDependencies() -> some View {
        environment(\.dependencies, .preview)
    }
}

// MARK: - Preview Model Container

/// Creates an in-memory SwiftData container for previews
@MainActor
func previewModelContainer() -> ModelContainer {
    let schema = Schema([
        UserProfile.self,
        Affirmation.self,
        CustomPrompt.self,
        ProgressData.self
    ])
    
    let configuration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: true
    )
    
    do {
        let container = try ModelContainer(for: schema, configurations: [configuration])
        
        // Insert sample data
        let context = container.mainContext
        
        // Sample user profile
        let profile = UserProfile(
            selectedGoals: [
                GoalCategory.confidence.rawValue,
                GoalCategory.focus.rawValue,
                GoalCategory.faith.rawValue
            ],
            hasCompletedOnboarding: true,
            includeFaithContent: true
        )
        context.insert(profile)
        
        // Sample affirmations
        for affirmation in Affirmation.samples {
            context.insert(affirmation)
        }
        
        // Sample prompts
        for prompt in CustomPrompt.samples {
            context.insert(prompt)
        }
        
        // Sample progress
        context.insert(ProgressData.sample)
        
        return container
    } catch {
        fatalError("Failed to create preview container: \(error)")
    }
}

// MARK: - Preview Helpers

/// Provides a complete preview environment with dependencies and model container
struct PreviewContainer<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .withPreviewDependencies()
            .modelContainer(previewModelContainer())
    }
}

extension View {
    /// Wraps view in a complete preview environment
    func previewEnvironment() -> some View {
        PreviewContainer { self }
    }
}

// MARK: - App State

/// Global application state observable
@Observable
final class AppState {
    
    // MARK: - Properties
    
    /// Whether onboarding has been completed
    var hasCompletedOnboarding: Bool = false
    
    /// Current user profile (loaded from SwiftData)
    var userProfile: UserProfile?
    
    /// Whether the app is loading initial data
    var isLoading: Bool = true
    
    /// Current error to display (if any)
    var currentError: AppError?
    
    /// Whether to show error alert
    var showingError: Bool = false
    
    /// Network connectivity status
    var isOnline: Bool = true
    
    /// Whether offline content has been seeded
    var hasSeededOfflineContent: Bool = false
    
    /// Whether user is authenticated
    var isAuthenticated: Bool {
        userProfile?.isAuthenticated ?? false
    }
    
    /// Whether user has premium subscription
    var isPremium: Bool {
        userProfile?.isPremium ?? false
    }
    
    // MARK: - Methods
    
    /// Presents an error to the user
    func presentError(_ error: AppError) {
        currentError = error
        showingError = true
    }
    
    /// Clears the current error
    func clearError() {
        currentError = nil
        showingError = false
    }
    
    /// Updates user profile from SwiftData
    func updateProfile(_ profile: UserProfile?) {
        userProfile = profile
        hasCompletedOnboarding = profile?.hasCompletedOnboarding ?? false
    }
    
    /// Marks offline content as seeded
    func markOfflineContentSeeded() {
        hasSeededOfflineContent = true
    }
}

// MARK: - App State Environment

private struct AppStateKey: EnvironmentKey {
    static let defaultValue = AppState()
}

extension EnvironmentValues {
    var appState: AppState {
        get { self[AppStateKey.self] }
        set { self[AppStateKey.self] = newValue }
    }
}

extension View {
    /// Injects app state into view hierarchy
    func withAppState(_ state: AppState) -> some View {
        environment(\.appState, state)
    }
}
