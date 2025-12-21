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
/// Configures:
/// - SwiftData model container
/// - Dependency injection
/// - App state management
/// - Root navigation
@main
struct ImprintApp: App {
    
    // MARK: - Properties
    
    /// SwiftData model container
    private let modelContainer: ModelContainer
    
    /// Global app state
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
        
        // Configure appearance
        configureAppearance()
    }
    
    // MARK: - Body
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appState, appState)
                .withDependencies()
                .preferredColorScheme(.dark)
                .onAppear {
                    loadInitialData()
                }
        }
        .modelContainer(modelContainer)
    }
    
    // MARK: - Private Methods
    
    /// Configures global UI appearance
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
        
        // Tab bar appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(AppColors.backgroundSecondary)
        
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }
    
    /// Loads initial data and determines starting state
    @MainActor
    private func loadInitialData() {
        Task {
            // Small delay for smooth launch
            try? await Task.sleep(for: .milliseconds(500))
            
            // Load user profile from SwiftData
            let context = modelContainer.mainContext
            let descriptor = FetchDescriptor<UserProfile>()
            
            do {
                let profiles = try context.fetch(descriptor)
                
                if let profile = profiles.first {
                    appState.updateProfile(profile)
                } else {
                    // Create new profile for first launch
                    let newProfile = UserProfile()
                    context.insert(newProfile)
                    try context.save()
                    appState.updateProfile(newProfile)
                }
            } catch {
                appState.presentError(.loadFailed(reason: error.localizedDescription))
            }
            
            appState.isLoading = false
        }
    }
}

// MARK: - Root View

/// Root view that handles navigation between onboarding and main app
struct RootView: View {
    
    @Environment(\.appState) private var appState
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        Group {
            if appState.isLoading {
                LaunchView()
            } else if !appState.hasCompletedOnboarding {
                OnboardingContainerView()
            } else {
                MainTabView()
            }
        }
        .animation(AppTheme.Animation.standard, value: appState.isLoading)
        .animation(AppTheme.Animation.standard, value: appState.hasCompletedOnboarding)
        .alert(
            "Error",
            isPresented: Binding(
                get: { appState.showingError },
                set: { if !$0 { appState.clearError() } }
            ),
            presenting: appState.currentError
        ) { error in
            Button("OK") {
                appState.clearError()
            }
            
            if error.isRecoverable, let suggestion = error.recoverySuggestion {
                Button(suggestion) {
                    // Handle recovery action
                    appState.clearError()
                }
            }
        } message: { error in
            Text(error.errorDescription ?? "An unknown error occurred.")
        }
    }
}

// MARK: - Launch View

/// Splash screen shown during initial load
struct LaunchView: View {
    
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.8
    
    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()
            
            VStack(spacing: AppTheme.Spacing.lg) {
                // App Icon Placeholder
                Circle()
                    .fill(AppColors.accent.opacity(0.2))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(AppColors.accent)
                    )
                
                VStack(spacing: AppTheme.Spacing.xs) {
                    Text("Imprint")
                        .font(AppTypography.largeTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text("Becoming You")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(AppTheme.Animation.slow) {
                opacity = 1
                scale = 1
            }
        }
    }
}

// MARK: - Placeholder Views

/*/// Placeholder for onboarding flow (to be implemented in Phase 3)
struct OnboardingContainerView: View {
    
    @Environment(\.appState) private var appState
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer()
            
            VStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "sparkles")
                    .font(.system(size: 60))
                    .foregroundStyle(AppColors.accent)
                
                Text("Welcome to Imprint")
                    .font(AppTypography.title1)
                    .foregroundStyle(AppColors.textPrimary)
                
                Text("Your journey to becoming you starts here.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            // Temporary skip button for development
            Button("Complete Onboarding (Dev)") {
                completeOnboarding()
            }
            .buttonStyle(.primary)
            .padding(.horizontal, AppTheme.Spacing.lg)
            
            Spacer()
        }
        .padding()
        .background(AppColors.backgroundPrimary)
    }
    
    private func completeOnboarding() {
        // Fetch and update profile
        let descriptor = FetchDescriptor<UserProfile>()
        
        do {
            let profiles = try modelContext.fetch(descriptor)
            if let profile = profiles.first {
                profile.hasCompletedOnboarding = true
                profile.selectedGoals = [
                    GoalCategory.confidence.rawValue,
                    GoalCategory.focus.rawValue,
                    GoalCategory.faith.rawValue
                ]
                try modelContext.save()
                appState.updateProfile(profile)
            }
        } catch {
            appState.presentError(.saveFailed(reason: error.localizedDescription))
        }
    }
} */

/// Placeholder for main tab view (to be implemented in Phase 4)
struct MainTabView: View {
    
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            SessionPlaceholderView()
                .tabItem {
                    Label("Practice", systemImage: "waveform")
                }
                .tag(0)
            
            PromptsPlaceholderView()
                .tabItem {
                    Label("Prompts", systemImage: "text.bubble")
                }
                .tag(1)
            
            ProgressPlaceholderView()
                .tabItem {
                    Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(2)
            
            SettingsPlaceholderView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
        .tint(AppColors.accent)
    }
}

// MARK: - Tab Placeholder Views

struct SessionPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.backgroundPrimary
                    .ignoresSafeArea()
                
                VStack(spacing: AppTheme.Spacing.lg) {
                    Text("I am confident and capable of achieving my goals.")
                        .affirmationStyle()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppTheme.Spacing.xl)
                    
                    Text("Swipe up for next affirmation")
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct PromptsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.backgroundPrimary
                    .ignoresSafeArea()
                
                ContentUnavailableView(
                    "No Prompts Yet",
                    systemImage: "text.bubble",
                    description: Text("Create custom prompts to generate personalized affirmations.")
                )
            }
            .navigationTitle("Prompts")
        }
    }
}

struct ProgressPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.backgroundPrimary
                    .ignoresSafeArea()
                
                ContentUnavailableView(
                    "No Progress Yet",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Start practicing to see your progress here.")
                )
            }
            .navigationTitle("Progress")
        }
    }
}

struct SettingsPlaceholderView: View {
    
    @Environment(\.appState) private var appState
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    NavigationLink {
                        Text("Sign In")
                    } label: {
                        Label("Sign In", systemImage: "person.circle")
                    }
                }
                
                Section("Preferences") {
                    NavigationLink {
                        Text("Goals")
                    } label: {
                        Label("Goals", systemImage: "target")
                    }
                    
                    NavigationLink {
                        Text("Voice Profile")
                    } label: {
                        Label("Voice Profile", systemImage: "waveform")
                    }
                }
                
                Section("Debug") {
                    Button("Reset Onboarding") {
                        resetOnboarding()
                    }
                    .foregroundStyle(AppColors.error)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Settings")
        }
    }
    
    private func resetOnboarding() {
        let descriptor = FetchDescriptor<UserProfile>()
        
        do {
            let profiles = try modelContext.fetch(descriptor)
            if let profile = profiles.first {
                profile.hasCompletedOnboarding = false
                try modelContext.save()
                appState.updateProfile(profile)
            }
        } catch {
            appState.presentError(.saveFailed(reason: error.localizedDescription))
        }
    }
}

// MARK: - Previews

#Preview("Root View") {
    RootView()
        .previewEnvironment()
}

#Preview("Launch View") {
    LaunchView()
}

#Preview("Main Tab View") {
    MainTabView()
        .previewEnvironment()
}
