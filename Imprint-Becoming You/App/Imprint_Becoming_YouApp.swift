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
/// - SwiftData model container initialization
/// - Dependency injection setup
/// - Global UI appearance configuration
/// - App state management
///
/// Note: All view logic lives in `RootView.swift` and its children.
/// This file focuses purely on app configuration and setup.
@main
struct ImprintApp: App {
    
    // MARK: - Properties
    
    /// SwiftData model container for persistence
    private let modelContainer: ModelContainer
    
    /// Global app state - injected into environment
    @State private var appState = AppState()
    
    // MARK: - Initialization
    
    init() {
        // Initialize SwiftData container
        do {
            let schema = Schema([
                UserProfile.self,
                Affirmation.self,
                CustomPrompt.self,
                SessionState.self,
                ProgressData.self
            ])
            
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true
            )
            
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Failed to initialize SwiftData: \(error)")
        }
        
        // Configure global UI appearance
        configureAppearance()
    }
    
    // MARK: - Body
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appState, appState)
                .withDependencies()
                .preferredColorScheme(.dark)
        }
        .modelContainer(modelContainer)
    }
    
    // MARK: - Private Methods
    
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
        
        // Tab bar appearance (kept for any future use, but app has no tab bar)
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(AppColors.backgroundSecondary)
        
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }
}

// MARK: - Preview Support

#Preview("App Launch") {
    RootView()
        .previewEnvironment()
}
