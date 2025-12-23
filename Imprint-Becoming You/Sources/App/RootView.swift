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
/// Note: `OnboardingContainerView` is defined in its own file
/// at `Sources/Features/Onboarding/OnboardingContainerView.swift`
struct RootView: View {
    
    // MARK: - Properties
    
    @Environment(\.appState) private var appState
    @Environment(\.modelContext) private var modelContext
    
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
        try? await Task.sleep(for: .milliseconds(300))
        
        let descriptor = FetchDescriptor<UserProfile>()
        
        do {
            let profiles = try modelContext.fetch(descriptor)
            
            if let profile = profiles.first {
                appState.updateProfile(profile)
            } else {
                let newProfile = UserProfile()
                modelContext.insert(newProfile)
                try modelContext.save()
                appState.updateProfile(newProfile)
            }
        } catch {
            appState.presentError(.loadFailed(reason: error.localizedDescription))
        }
        
        appState.isLoading = false
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
