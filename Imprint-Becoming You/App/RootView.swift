//
//  RootView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/22/25.
//

import SwiftUI
import SwiftData

// MARK: - Root View

/// Root view that handles navigation between onboarding and main app.
///
/// After onboarding, the app presents `MainPracticeView` as the sole
/// root experience - no tab bar, fully immersive.
///
/// ## First Launch Behavior
/// On first launch, `loadInitialData()` will:
/// 1. Seed offline affirmations from bundled JSON (1,120 items)
/// 2. Create a new `UserProfile`
/// 3. Show onboarding flow
///
/// Note: `OnboardingContainerView` is defined in its own file
/// at `Sources/Features/Onboarding/OnboardingContainerView.swift`
struct RootView: View {
    
    // MARK: - Properties
    
    @Environment(\.appState) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dependencies) private var dependencies
    
    // MARK: - Body
    
    var body: some View {
        Group {
            if appState.isLoading {
                LaunchView()
            } else if !appState.hasCompletedOnboarding {
                OnboardingContainerView()
            } else {
                // Main app - full immersive experience
                MainPracticeView()
            }
        }
        .animation(AppTheme.Animation.standard, value: appState.isLoading)
        .animation(AppTheme.Animation.standard, value: appState.hasCompletedOnboarding)
        .task {
            await loadInitialData()
        }
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
                    appState.clearError()
                }
            }
        } message: { error in
            Text(error.errorDescription ?? "An unknown error occurred.")
        }
    }
    
    // MARK: - Private Methods
    
    @MainActor
    private func loadInitialData() async {
        // Step 0: Warm up haptic generators immediately.
        // This prepares the Taptic Engine so the first user interaction
        // (e.g., tapping "Yes" in faith preference) has zero latency.
        HapticFeedback.warmUp()
        
        // Brief delay for launch animation
        try? await Task.sleep(for: .milliseconds(300))
        
        // Step 1: Seed offline content if needed (first launch)
        await seedOfflineContentIfNeeded()
        
        // Step 2: Load or create user profile
        await loadUserProfile()
        
        // Complete loading
        appState.isLoading = false
    }
    
    /// Seeds offline affirmations from bundled JSON on first launch.
    @MainActor
    private func seedOfflineContentIfNeeded() async {
        let loader = dependencies.makeOfflineContentLoader()
        
        // Skip if already seeded
        guard !loader.hasBeenSeeded else {
            appState.markOfflineContentSeeded()
            return
        }
        
        do {
            try await loader.seedIfNeeded(modelContext: modelContext)
            appState.markOfflineContentSeeded()
            
            #if DEBUG
            // Verify seeding
            let count = try? modelContext.fetchCount(FetchDescriptor<Affirmation>())
            print("✅ RootView: Offline content seeded. Total affirmations: \(count ?? 0)")
            #endif
            
        } catch {
            // Log but don't block - app can still function with samples
            #if DEBUG
            print("⚠️ RootView: Failed to seed offline content: \(error.localizedDescription)")
            #endif
            
            // Still mark as attempted to avoid retry loops
            appState.markOfflineContentSeeded()
        }
    }
    
    /// Loads existing user profile or creates a new one.
    @MainActor
    private func loadUserProfile() async {
        let descriptor = FetchDescriptor<UserProfile>()
        
        do {
            let profiles = try modelContext.fetch(descriptor)
            
            if let profile = profiles.first {
                appState.updateProfile(profile)
            } else {
                // First launch - create new profile
                let newProfile = UserProfile()
                modelContext.insert(newProfile)
                try modelContext.save()
                appState.updateProfile(newProfile)
            }
        } catch {
            appState.presentError(.loadFailed(reason: error.localizedDescription))
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

// MARK: - Previews

#Preview("Root View") {
    RootView()
        .previewEnvironment()
}

#Preview("Launch View") {
    LaunchView()
}
