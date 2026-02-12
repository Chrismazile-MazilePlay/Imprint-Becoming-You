//
//  Imprint_Becoming_YouApp.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/19/25.
//

import SwiftUI
import SwiftData

// MARK: - App Entry Point

/// Main entry point for the Imprint application.
///
/// Responsibilities:
/// - SwiftData model container initialization with recovery handling
/// - Memory management setup (via MemoryManager)
/// - Dependency injection setup
/// - Global UI appearance configuration
/// - App state management
///
/// ## Database Recovery Strategy
/// The app uses `ModelContainerFactory` to handle SwiftData initialization
/// with graceful fallback:
/// 1. Attempt normal persistent storage
/// 2. If fails, fall back to in-memory storage (app functions but data won't persist)
/// 3. If both fail, show recovery UI with option to reset
///
/// ## Memory Management
/// At launch, MemoryManager is initialized to monitor:
/// - iOS memory warnings
/// - Background/foreground transitions
/// - Coordinated release of heavy resources (Kokoro ML pipelines)
///
/// Note: All view logic lives in `RootView.swift` and its children.
/// This file focuses purely on app configuration and setup.
@main
struct ImprintApp: App {
    
    // MARK: - Properties
    
    /// SwiftData model container for persistence
    private let modelContainer: ModelContainer
    
    /// Result of container initialization for error handling
    private let initializationResult: ModelContainerResult
    
    /// Global app state - injected into environment
    @State private var appState = AppState()
    
    /// Whether to show the fallback warning banner
    @State private var showFallbackBanner = false
    
    // MARK: - Initialization
    
    init() {
        // Initialize SwiftData with recovery handling
        let result = ModelContainerFactory.createContainer()
        self.initializationResult = result
        
        // Extract container or create emergency fallback
        if let container = result.container {
            self.modelContainer = container
        } else {
            // Complete failure - create minimal in-memory container for compilation
            // The app will show recovery UI instead of normal content
            do {
                self.modelContainer = try ModelContainer(
                    for: ModelContainerFactory.schema,
                    configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
                )
            } catch {
                // This should never happen, but handle it gracefully
                fatalError("Critical: Unable to create even an in-memory container: \(error)")
            }
        }
        
        // Configure global UI appearance
        configureAppearance()
        
        // Log initialization status
        switch result {
        case .success:
            AppLogger.debug("SwiftData initialized successfully (persistent)", category: .app)
        case .fallback(_, let error):
            AppLogger.debug(
                "SwiftData using in-memory fallback",
                category: .app,
                context: ["error": String(describing: error)]
            )
        case .failure(let error):
            AppLogger.debug(
                "SwiftData initialization failed",
                category: .app,
                context: ["error": String(describing: error)]
            )
        }
    }
    
    // MARK: - Body
    
    var body: some Scene {
        WindowGroup {
            Group {
                if initializationResult.isFailed {
                    // Complete failure - show recovery UI
                    DatabaseRecoveryView(
                        errorMessage: initializationResult.errorMessage ?? "Unknown error",
                        onReset: handleDatabaseReset,
                        onContinue: handleContinueWithoutData
                    )
                } else {
                    // Normal or fallback operation
                    mainAppContent
                        .onAppear {
                            // Show warning if using fallback mode
                            if initializationResult.isUsingFallback {
                                showFallbackBanner = true
                            }
                        }
                }
            }
        }
        .modelContainer(modelContainer)
    }
    
    // MARK: - Main App Content
    
    /// The main app content when database is available
    @ViewBuilder
    private var mainAppContent: some View {
        ZStack(alignment: .top) {
            RootView()
                .environment(\.appState, appState)
                .withDependencies()
                .preferredColorScheme(.dark)
                .task {
                    await startBackgroundServices()
                }
            
            // Fallback warning banner (if needed)
            if showFallbackBanner {
                DatabaseFallbackBanner(onDismiss: {
                    withAnimation {
                        showFallbackBanner = false
                    }
                })
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.top, AppTheme.Spacing.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Recovery Handlers
    
    /// Handles user request to reset database
    private func handleDatabaseReset() {
        AppLogger.debug("User requested database reset", category: .app)
        
        // Attempt to reset and restart
        let resetResult = ModelContainerFactory.resetDatabase()
        
        switch resetResult {
        case .success, .fallback:
            // Reset succeeded - but we need app restart to use new container
            // Show message guiding user to restart
            showRestartRequiredAlert()
        case .failure:
            // Still failing - user needs to reinstall
            AppLogger.debug("Database reset failed", category: .app)
        }
    }
    
    /// Handles user choosing to continue without persistent data
    private func handleContinueWithoutData() {
        AppLogger.debug("User continuing without persistent data", category: .app)
        
        // The app is already using in-memory container
        // User can proceed but data won't persist
        // We'll need to trigger a state change to refresh the view
        // Since we can't mutate initializationResult, we rely on the view
        // to handle this case appropriately
    }
    
    /// Shows an alert indicating restart is required
    private func showRestartRequiredAlert() {
        // Note: In a production app, you would implement this with a proper
        // alert or banner. For now, we log and rely on the next launch.
        AppLogger.debug("Database reset complete. Please restart the app.", category: .app)
    }
    
    // MARK: - Background Services
    
    /// Starts background services including memory management, TTS warm-up, and voice preview synthesis.
    @MainActor
    private func startBackgroundServices() async {
        let dependencies = DependencyContainer.shared
        
        // ===============================================================
        // MEMORY MANAGEMENT: Start monitoring before loading heavy resources
        // ===============================================================
        AppLogger.debug("Starting memory management...", category: .app)
        #if DEBUG
        MemoryManager.shared.logMemoryUsage()
        #endif
        
        MemoryManager.shared.startMonitoring(dependencies: dependencies)
        
        // ===============================================================
        // TTS: Warm up Kokoro engine
        // This loads ~500MB-1GB of ML models into memory
        // ===============================================================
        AppLogger.debug("Warming up TTS engine...", category: .app)
        let startTime = Date()
        await dependencies.ttsService.warmUp()
        let elapsed = Date().timeIntervalSince(startTime)
        AppLogger.debug(
            "TTS warm-up complete",
            category: .app,
            context: ["elapsed": String(format: "%.2f", elapsed)]
        )
        #if DEBUG
        MemoryManager.shared.logMemoryUsage()
        #endif
        
        AppLogger.debug("All background services started", category: .app)
        #if DEBUG
        MemoryManager.shared.logMemoryUsage()
        #endif
    }
    
    // MARK: - Appearance Configuration
    
    /// Configures global UI appearance for UIKit components
    private func configureAppearance() {
        // Navigation bar appearance
        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithOpaqueBackground()
        navigationAppearance.backgroundColor = UIColor(AppColors.backgroundPrimary)
        navigationAppearance.titleTextAttributes = [
            .foregroundColor: UIColor(AppColors.textPrimary)
        ]
        navigationAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(AppColors.textPrimary)
        ]
        
        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        
        // Note: Tab bar configuration removed - app uses full-screen immersive UI
        // If tab bar is added in future, configure appearance here
    }
}

// MARK: - Preview Support

#Preview("App Launch") {
    RootView()
        .previewEnvironment()
}

#Preview("Database Recovery") {
    DatabaseRecoveryView(
        errorMessage: "Failed to load persistent stores",
        onReset: { },
        onContinue: { }
    )
}
