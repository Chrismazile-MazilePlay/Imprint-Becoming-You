//
//  DependencyContainer.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import SwiftUI
import SwiftData

// MARK: - Repository Cache

/// Cache for repository instances keyed by ModelContext identity.
///
/// Uses `NSMapTable` with weak keys to automatically release repositories
/// when their ModelContext is deallocated. This prevents memory leaks
/// while still enabling instance reuse.
///
/// ## Why NSMapTable?
/// - Supports weak references to keys (ModelContext)
/// - Automatically removes entries when key is deallocated
/// - Thread-safe when accessed from MainActor
///
/// ## Benefits of Caching
/// - Reduces memory allocation overhead
/// - Enables potential internal caching within repositories
/// - Reduces object churn for frequently accessed data
private final class RepositoryCache {
    
    /// Weak key -> strong value map for affirmation repositories
    private var affirmationRepositories = NSMapTable<AnyObject, AnyObject>.weakToStrongObjects()
    
    /// Weak key -> strong value map for saved session repositories
    private var savedSessionRepositories = NSMapTable<AnyObject, AnyObject>.weakToStrongObjects()
    
    /// Weak key -> strong value map for voice repositories
    private var voiceRepositories = NSMapTable<AnyObject, AnyObject>.weakToStrongObjects()
    
    // MARK: - Affirmation Repository
    
    /// Retrieves a cached affirmation repository for the given context.
    func getAffirmationRepository(for context: ModelContext) -> (any AffirmationRepositoryProtocol)? {
        affirmationRepositories.object(forKey: context) as? any AffirmationRepositoryProtocol
    }
    
    /// Caches an affirmation repository for the given context.
    func setAffirmationRepository(_ repo: any AffirmationRepositoryProtocol, for context: ModelContext) {
        affirmationRepositories.setObject(repo as AnyObject, forKey: context)
    }
    
    // MARK: - Saved Session Repository
    
    /// Retrieves a cached saved session repository for the given context.
    func getSavedSessionRepository(for context: ModelContext) -> (any SavedSessionRepositoryProtocol)? {
        savedSessionRepositories.object(forKey: context) as? any SavedSessionRepositoryProtocol
    }
    
    /// Caches a saved session repository for the given context.
    func setSavedSessionRepository(_ repo: any SavedSessionRepositoryProtocol, for context: ModelContext) {
        savedSessionRepositories.setObject(repo as AnyObject, forKey: context)
    }
    
    // MARK: - Voice Repository
    
    /// Retrieves a cached voice repository for the given context.
    func getVoiceRepository(for context: ModelContext) -> (any VoiceRepositoryProtocol)? {
        voiceRepositories.object(forKey: context) as? any VoiceRepositoryProtocol
    }
    
    /// Caches a voice repository for the given context.
    func setVoiceRepository(_ repo: any VoiceRepositoryProtocol, for context: ModelContext) {
        voiceRepositories.setObject(repo as AnyObject, forKey: context)
    }
    
    // MARK: - Cleanup
    
    /// Clears all cached repositories.
    ///
    /// Call when app enters background or receives memory warning.
    func clearAll() {
        affirmationRepositories.removeAllObjects()
        savedSessionRepositories.removeAllObjects()
        voiceRepositories.removeAllObjects()
    }
    
    /// Returns the number of cached repositories for debugging.
    var debugDescription: String {
        """
        RepositoryCache:
          - Affirmation: \(affirmationRepositories.count)
          - SavedSession: \(savedSessionRepositories.count)
          - Voice: \(voiceRepositories.count)
        """
    }
}

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
/// For SwiftData-dependent services, use the factory methods:
/// ```swift
/// @Environment(\.modelContext) private var modelContext
///
/// let repository = dependencies.makeAffirmationRepository(modelContext: modelContext)
/// let voiceRepo = dependencies.makeVoiceRepository(modelContext: modelContext)
/// ```
///
/// ## Repository Caching
/// Repository instances are cached per ModelContext using weak-keyed maps.
/// This reduces allocation overhead while automatically cleaning up when
/// the ModelContext is deallocated. Cache can be cleared manually via
/// `clearRepositoryCache()` for memory management.
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
    
    /// Cache for repository instances
    private let repositoryCache = RepositoryCache()
    
    // MARK: - Services (Lazy Initialization with Safe Unwrapping)
    
    /// Audio playback and background music service
    private var _audioService: (any AudioServiceProtocol)?
    var audioService: any AudioServiceProtocol {
        if let existing = _audioService {
            return existing
        }
        let service: any AudioServiceProtocol = isPreview ? MockAudioService() : AudioService()
        _audioService = service
        return service
    }
    
    /// Audio player service for TTS playback.
    ///
    /// In production, returns the engine-attached player from `AudioService`,
    /// ensuring all TTS audio routes through the same `AVAudioEngine` as
    /// background music (one render client, zero static).
    ///
    /// In preview mode, returns a mock.
    private var _audioPlayerService: (any AudioPlayerServiceProtocol)?
    var audioPlayerService: any AudioPlayerServiceProtocol {
        if let existing = _audioPlayerService {
            return existing
        }
        if isPreview {
            let service: any AudioPlayerServiceProtocol = MockAudioPlayerService()
            _audioPlayerService = service
            return service
        }
        // Use the engine-attached player from AudioService
        let service = audioService.audioPlayerService
        _audioPlayerService = service
        return service
    }
    
    /// Speech recognition and analysis service
    private var _speechAnalysisService: (any SpeechAnalysisServiceProtocol)?
    var speechAnalysisService: any SpeechAnalysisServiceProtocol {
        if let existing = _speechAnalysisService {
            return existing
        }
        let service: any SpeechAnalysisServiceProtocol = isPreview ? MockSpeechAnalysisService() : SpeechAnalysisService()
        _speechAnalysisService = service
        return service
    }
    
    /// Text-to-speech service.
    ///
    /// In production, injects `audioService` and `audioPlayerService` references
    /// so TTS playback routes through the unified `AVAudioEngine` (no standalone
    /// `AVAudioPlayer`, no dual-render-client contention).
    private var _ttsService: (any TTSServiceProtocol)?
    var ttsService: any TTSServiceProtocol {
        if let existing = _ttsService {
            return existing
        }
        #if targetEnvironment(simulator)
        let service: any TTSServiceProtocol = MockTTSService()
        #else
        if isPreview {
            let service: any TTSServiceProtocol = MockTTSService()
            _ttsService = service
            return service
        }
        let concrete = TTSService()
        concrete.audioService = audioService
        concrete.audioPlayerService = audioPlayerService
        let service: any TTSServiceProtocol = concrete
        #endif
        _ttsService = service
        return service
    }
    
    /// Affirmation generation and management service
    private var _affirmationService: (any AffirmationServiceProtocol)?
    var affirmationService: any AffirmationServiceProtocol {
        if let existing = _affirmationService {
            return existing
        }
        let service: any AffirmationServiceProtocol = isPreview ? MockAffirmationService() : AffirmationService()
        _affirmationService = service
        return service
    }
    
    /// Voice cloning service
    private var _voiceCloneService: (any VoiceCloneServiceProtocol)?
    var voiceCloneService: any VoiceCloneServiceProtocol {
        if let existing = _voiceCloneService {
            return existing
        }
        let service: any VoiceCloneServiceProtocol = isPreview ? MockVoiceCloneService() : VoiceCloneService()
        _voiceCloneService = service
        return service
    }
    
    /// Authentication service
    private var _authService: (any AuthServiceProtocol)?
    var authService: any AuthServiceProtocol {
        if let existing = _authService {
            return existing
        }
        let service: any AuthServiceProtocol = isPreview ? MockAuthService() : AuthService()
        _authService = service
        return service
    }
    
    /// Data synchronization service
    private var _syncService: (any SyncServiceProtocol)?
    var syncService: any SyncServiceProtocol {
        if let existing = _syncService {
            return existing
        }
        let service: any SyncServiceProtocol = isPreview ? MockSyncService() : SyncService()
        _syncService = service
        return service
    }
    
    /// Subscription/StoreKit service
    private var _subscriptionService: (any SubscriptionServiceProtocol)?
    var subscriptionService: any SubscriptionServiceProtocol {
        if let existing = _subscriptionService {
            return existing
        }
        let service: any SubscriptionServiceProtocol = isPreview ? MockSubscriptionService() : SubscriptionService()
        _subscriptionService = service
        return service
    }
    
    /// Audio caching service
    private var _audioCacheService: (any AudioCacheServiceProtocol)?
    var audioCacheService: any AudioCacheServiceProtocol {
        if let existing = _audioCacheService {
            return existing
        }
        let service: any AudioCacheServiceProtocol = isPreview ? MockAudioCacheService() : AudioCacheManager.shared
        _audioCacheService = service
        return service
    }
    
    /// Voice preview caching service
    private var _voicePreviewCacheService: (any VoicePreviewCacheServiceProtocol)?
    var voicePreviewCacheService: any VoicePreviewCacheServiceProtocol {
        if let existing = _voicePreviewCacheService {
            return existing
        }
        let service: any VoicePreviewCacheServiceProtocol = isPreview
            ? MockVoicePreviewCacheService()
            : VoicePreviewCacheService(ttsService: ttsService)
        _voicePreviewCacheService = service
        return service
    }
    
    /// Session TTS pre-synthesis queue service
    private var _sessionTTSQueueService: (any SessionTTSQueueServiceProtocol)?
    var sessionTTSQueueService: any SessionTTSQueueServiceProtocol {
        if let existing = _sessionTTSQueueService {
            return existing
        }
        let service: any SessionTTSQueueServiceProtocol = isPreview
            ? MockSessionTTSQueueService()
            : SessionTTSQueueService(synthesisEngine: TTSSynthesisEngine(ttsService: ttsService))
        _sessionTTSQueueService = service
        return service
    }
    
    // MARK: - Initialization
    
    private init(isPreview: Bool) {
        self.isPreview = isPreview
    }
    
    // MARK: - Repository Factory Methods (Cached)
    
    /// Creates or retrieves a cached affirmation repository for the given model context.
    ///
    /// Repositories are cached per ModelContext to reduce allocation overhead
    /// and enable potential internal caching within the repository.
    ///
    /// For production, returns a real `AffirmationRepository`.
    /// For previews, returns a `MockAffirmationRepository` (not cached).
    ///
    /// - Parameter modelContext: SwiftData model context
    /// - Returns: Repository conforming to `AffirmationRepositoryProtocol`
    func makeAffirmationRepository(modelContext: ModelContext) -> any AffirmationRepositoryProtocol {
        if isPreview {
            // Don't cache mocks - they're stateless
            return MockAffirmationRepository()
        }
        
        // Check cache first
        if let cached = repositoryCache.getAffirmationRepository(for: modelContext) {
            AppLogger.debug(
                "AffirmationRepository cache hit",
                category: .data
            )
            return cached
        }
        
        // Create and cache new instance
        let repo = AffirmationRepository(modelContext: modelContext)
        repositoryCache.setAffirmationRepository(repo, for: modelContext)
        
        AppLogger.debug(
            "Created new AffirmationRepository (cached)",
            category: .data
        )
        
        return repo
    }
    
    /// Creates or retrieves a cached saved session repository for the given model context.
    ///
    /// Repositories are cached per ModelContext to reduce allocation overhead
    /// and enable potential internal caching within the repository.
    ///
    /// For production, returns a real `SavedSessionRepository`.
    /// For previews, returns a `MockSavedSessionRepository` (not cached).
    ///
    /// - Parameter modelContext: SwiftData model context
    /// - Returns: Repository conforming to `SavedSessionRepositoryProtocol`
    func makeSavedSessionRepository(modelContext: ModelContext) -> any SavedSessionRepositoryProtocol {
        if isPreview {
            return MockSavedSessionRepository()
        }
        
        // Check cache first
        if let cached = repositoryCache.getSavedSessionRepository(for: modelContext) {
            AppLogger.debug(
                "SavedSessionRepository cache hit",
                category: .data
            )
            return cached
        }
        
        // Create and cache new instance
        let repo = SavedSessionRepository(modelContext: modelContext)
        repositoryCache.setSavedSessionRepository(repo, for: modelContext)
        
        AppLogger.debug(
            "Created new SavedSessionRepository (cached)",
            category: .data
        )
        
        return repo
    }
    
    /// Creates or retrieves a cached voice repository for the given model context.
    ///
    /// Repositories are cached per ModelContext to reduce allocation overhead
    /// and enable potential internal caching within the repository.
    ///
    /// For production, returns a real `VoiceRepository`.
    /// For previews, returns a `MockVoiceRepository` (not cached).
    ///
    /// - Parameter modelContext: SwiftData model context
    /// - Returns: Repository conforming to `VoiceRepositoryProtocol`
    func makeVoiceRepository(modelContext: ModelContext) -> any VoiceRepositoryProtocol {
        if isPreview {
            return MockVoiceRepository()
        }
        
        // Check cache first
        if let cached = repositoryCache.getVoiceRepository(for: modelContext) {
            AppLogger.debug(
                "VoiceRepository cache hit",
                category: .data
            )
            return cached
        }
        
        // Create and cache new instance
        let repo = VoiceRepository(modelContext: modelContext)
        repositoryCache.setVoiceRepository(repo, for: modelContext)
        
        AppLogger.debug(
            "Created new VoiceRepository (cached)",
            category: .data
        )
        
        return repo
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
    
    // MARK: - Repository Cache Management
    
    /// Clears all cached repository instances.
    ///
    /// Call when:
    /// - App enters background for extended period
    /// - Memory warning received
    /// - User logs out
    ///
    /// Cached repositories will be recreated on next access.
    func clearRepositoryCache() {
        repositoryCache.clearAll()
        AppLogger.info("Repository cache cleared", category: .data)
    }
    
    #if DEBUG
    /// Debug description of repository cache state.
    ///
    /// Shows the number of cached repositories per type.
    var repositoryCacheDebugDescription: String {
        repositoryCache.debugDescription
    }
    #endif
    
    // MARK: - Service Registration (for testing)
    
    /// Registers a custom audio service (useful for testing)
    func register(audioService: any AudioServiceProtocol) {
        _audioService = audioService
    }

    /// Registers a custom audio player service
    func register(audioPlayerService: any AudioPlayerServiceProtocol) {
        _audioPlayerService = audioPlayerService
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
    
    /// Registers a custom audio cache service
    func register(audioCacheService: any AudioCacheServiceProtocol) {
        _audioCacheService = audioCacheService
    }
    
    /// Registers a custom voice preview cache service
    func register(voicePreviewCacheService: any VoicePreviewCacheServiceProtocol) {
        _voicePreviewCacheService = voicePreviewCacheService
    }
    
    /// Registers a custom session TTS queue service
    func register(sessionTTSQueueService: any SessionTTSQueueServiceProtocol) {
        _sessionTTSQueueService = sessionTTSQueueService
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

/// Shared in-memory SwiftData container for previews.
///
/// Uses a lazy singleton to prevent `ModelContext.reset` crashes when
/// switching between Xcode Previews. Each call to a non-cached factory
/// would create a new container, invalidating model instances still
/// referenced by the previous preview — triggering a `fatalError` in
/// `BackingData.swift`. A single shared instance keeps all preview
/// model references stable across preview switches.
@MainActor
private var _previewModelContainer: ModelContainer?

@MainActor
func previewModelContainer() -> ModelContainer {
    if let existing = _previewModelContainer {
        return existing
    }

    let schema = Schema([
        UserProfile.self,
        Affirmation.self,
        CustomPrompt.self,
        ProgressData.self,
        SavedSession.self,
        VoiceRecord.self,
        VoiceUsageRecord.self
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

        _previewModelContainer = container
        return container
    } catch {
        // For previews, we still need to return something
        // Create a minimal container without sample data
        #if DEBUG
        print("⚠️ PreviewContainer: Failed to create container with sample data: \(error)")
        print("⚠️ PreviewContainer: Attempting minimal container...")
        #endif

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            _previewModelContainer = container
            return container
        } catch {
            // This is a preview-only path, so fatalError is acceptable here
            // as it only affects Xcode Canvas, not production
            fatalError("Preview container creation failed completely: \(error)")
        }
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
