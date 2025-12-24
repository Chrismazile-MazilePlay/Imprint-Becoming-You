//
//  ProfilePageView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/22/25.
//

import SwiftUI
import SwiftData

// MARK: - ProfilePageView

/// Full-screen profile page accessible by sliding right from Practice.
///
/// Contains:
/// - Profile header with avatar
/// - Stats row (streak, practiced, favorites)
/// - Progress section (future charts)
/// - Favorites list
/// - Settings section
///
/// Navigation: This page is on the RIGHT. Back navigation goes LEFT to Practice.
struct ProfilePageView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appState) private var appState
    
    // MARK: - Properties
    
    @Bindable var viewModel: PracticeViewModel
    let onNavigateToCenter: () -> Void
    
    // MARK: - State
    
    @State private var favoriteCount: Int = 0
    @State private var streak: Int = 0
    @State private var totalPracticed: Int = 0
    @State private var showFavorites = false
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    // Navigation header (back goes LEFT to Practice)
                    navigationHeader
                    
                    // Profile header
                    profileHeader
                    
                    // Stats row
                    statsRow
                    
                    // Progress section
                    progressSection
                    
                    // Favorites section
                    favoritesSection
                    
                    // Settings section
                    settingsSection
                    
                    // Bottom padding
                    Spacer()
                        .frame(height: AppTheme.Spacing.xxl)
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
            }
        }
        .task {
            await loadStats()
        }
        .navigationDestination(isPresented: $showFavorites) {
            FavoritesFullListView(viewModel: viewModel)
        }
    }
    
    // MARK: - Navigation Header
    
    private var navigationHeader: some View {
        HStack {
            // Back to Practice (goes LEFT)
            Button {
                onNavigateToCenter()
            } label: {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Practice")
                        .font(AppTypography.body)
                }
                .foregroundStyle(AppColors.accent)
            }
            
            Spacer()
        }
        .padding(.top, AppTheme.Spacing.xl)
    }
    
    // MARK: - Profile Header
    
    private var profileHeader: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Avatar
            Image(systemName: "person.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(AppColors.accent.opacity(0.8))
            
            // Welcome text
            VStack(spacing: AppTheme.Spacing.xs) {
                Text("Your Profile")
                    .font(AppTypography.title2)
                    .foregroundStyle(AppColors.textPrimary)
                
                Text("Track your journey")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.lg)
    }
    
    // MARK: - Stats Row
    
    private var statsRow: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            ProfileStatCard(
                icon: "flame.fill",
                value: "\(streak)",
                label: "Day Streak",
                color: .orange
            )
            
            ProfileStatCard(
                icon: "checkmark.circle.fill",
                value: "\(totalPracticed)",
                label: "Practiced",
                color: AppColors.success
            )
            
            ProfileStatCard(
                icon: "heart.fill",
                value: "\(favoriteCount)",
                label: "Favorites",
                color: AppColors.accent
            )
        }
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            ProfileSectionHeader(title: "PROGRESS")
            
            // Placeholder for progress charts
            VStack(spacing: AppTheme.Spacing.md) {
                ProgressPlaceholderCard(
                    title: "Weekly Practice",
                    subtitle: "View your practice history",
                    icon: "chart.bar.fill"
                )
                
                ProgressPlaceholderCard(
                    title: "Resonance Trends",
                    subtitle: "Track your vocal improvement",
                    icon: "waveform.path.ecg"
                )
            }
        }
    }
    
    // MARK: - Favorites Section
    
    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            ProfileSectionHeader(title: "FAVORITES")
            
            Button {
                showFavorites = true
            } label: {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppColors.accent)
                        .frame(width: 32, height: 32)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Saved Affirmations")
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColors.textPrimary)
                        
                        Text("\(favoriteCount) affirmations")
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    Spacer(minLength: 0)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .padding(AppTheme.Spacing.md)
                .background(AppColors.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Settings Section
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            ProfileSectionHeader(title: "SETTINGS")
            
            VStack(spacing: AppTheme.Spacing.sm) {
                // Voice Profile
                SettingsRow(
                    icon: "waveform",
                    iconColor: AppColors.accentSecondary,
                    title: "Voice Profile",
                    subtitle: appState.userProfile?.voiceProfileId != nil ? "Custom voice" : "System voice"
                ) {
                    // TODO: Navigate to voice settings
                }
                
                // Goals
                SettingsRow(
                    icon: "target",
                    iconColor: AppColors.accent,
                    title: "Goals",
                    subtitle: "\(appState.userProfile?.selectedGoals.count ?? 0) selected"
                ) {
                    // TODO: Navigate to goals settings
                }
                
                // Notifications
                SettingsRow(
                    icon: "bell.fill",
                    iconColor: .blue,
                    title: "Notifications",
                    subtitle: "Manage reminders"
                ) {
                    // TODO: Navigate to notification settings
                }
                
                // Account
                SettingsRow(
                    icon: "person.circle",
                    iconColor: AppColors.textSecondary,
                    title: "Account",
                    subtitle: "Sign in to sync"
                ) {
                    // TODO: Navigate to account settings
                }
                
                // Debug: Reset Onboarding
                #if DEBUG
                SettingsRow(
                    icon: "arrow.counterclockwise",
                    iconColor: AppColors.error,
                    title: "Reset Onboarding",
                    subtitle: "Development only"
                ) {
                    resetOnboarding()
                }
                #endif
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadStats() async {
        let favDescriptor = FetchDescriptor<Affirmation>(
            predicate: #Predicate { $0.isFavorited }
        )
        favoriteCount = (try? modelContext.fetchCount(favDescriptor)) ?? 0
        
        let practicedDescriptor = FetchDescriptor<Affirmation>(
            predicate: #Predicate { $0.speakCount > 0 }
        )
        totalPracticed = (try? modelContext.fetchCount(practicedDescriptor)) ?? 0
        
        // TODO: Calculate actual streak from session history
        streak = 3
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

// MARK: - ProfileSectionHeader

struct ProfileSectionHeader: View {
    
    let title: String
    
    var body: some View {
        Text(title)
            .font(AppTypography.caption1.weight(.semibold))
            .foregroundStyle(AppColors.textTertiary)
            .padding(.top, AppTheme.Spacing.sm)
    }
}

// MARK: - ProfileStatCard

struct ProfileStatCard: View {
    
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(color)
            
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)
            
            Text(label)
                .font(AppTypography.caption2)
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.md)
        .background(AppColors.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
    }
}

// MARK: - ProgressPlaceholderCard

struct ProgressPlaceholderCard: View {
    
    let title: String
    let subtitle: String
    let icon: String
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                
                Text(subtitle)
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
            }
            
            Spacer()
            
            Text("Soon")
                .font(AppTypography.caption2)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.horizontal, AppTheme.Spacing.sm)
                .padding(.vertical, AppTheme.Spacing.xs)
                .background(AppColors.surfaceTertiary)
                .clipShape(Capsule())
        }
        .padding(AppTheme.Spacing.md)
        .background(AppColors.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
    }
}

// MARK: - SettingsRow

struct SettingsRow: View {
    
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(iconColor)
                    .frame(width: 28, height: 28)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text(subtitle)
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(AppTheme.Spacing.md)
            .background(AppColors.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FavoritesFullListView

/// Full list of favorites accessible from Profile page.
struct FavoritesFullListView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: PracticeViewModel
    
    @State private var favorites: [Affirmation] = []
    
    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()
            
            if favorites.isEmpty {
                emptyState
            } else {
                favoritesList
            }
        }
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadFavorites()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "heart.slash")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textTertiary)
            
            Text("No Favorites Yet")
                .font(AppTypography.title3)
                .foregroundStyle(AppColors.textPrimary)
            
            Text("Tap the heart on any affirmation to save it here.")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(AppTheme.Spacing.xl)
    }
    
    private var favoritesList: some View {
        VStack(spacing: 0) {
            List {
                ForEach(favorites) { affirmation in
                    FavoriteListRow(
                        affirmation: affirmation,
                        onUnfavorite: { unfavorite(affirmation) }
                    )
                }
                .onDelete(perform: deleteFavorites)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            
            // Start session button
            Button {
                Task {
                    await viewModel.loadFavorites(from: modelContext)
                    dismiss()
                }
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Practice Favorites")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)
            .padding(AppTheme.Spacing.lg)
        }
    }
    
    private func loadFavorites() async {
        let descriptor = FetchDescriptor<Affirmation>(
            predicate: #Predicate { $0.isFavorited },
            sortBy: [SortDescriptor(\.favoritedAt, order: .reverse)]
        )
        favorites = (try? modelContext.fetch(descriptor)) ?? []
    }
    
    private func unfavorite(_ affirmation: Affirmation) {
        affirmation.isFavorited = false
        affirmation.favoritedAt = nil
        favorites.removeAll { $0.id == affirmation.id }
    }
    
    private func deleteFavorites(at offsets: IndexSet) {
        for index in offsets {
            let affirmation = favorites[index]
            affirmation.isFavorited = false
            affirmation.favoritedAt = nil
        }
        favorites.remove(atOffsets: offsets)
    }
}

// MARK: - FavoriteListRow

struct FavoriteListRow: View {
    
    let affirmation: Affirmation
    let onUnfavorite: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            if let category = affirmation.goalCategory {
                Image(systemName: category.iconName)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 28, height: 28)
                    .background(AppColors.accent.opacity(0.15))
                    .clipShape(Circle())
            }
            
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(affirmation.text)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(3)
                
                if let date = affirmation.favoritedAt {
                    Text("Saved \(date.formatted(.relative(presentation: .named)))")
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            
            Spacer(minLength: 0)
            
            Button {
                onUnfavorite()
                HapticFeedback.impact(.light)
            } label: {
                Image(systemName: "heart.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(AppColors.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .listRowBackground(AppColors.backgroundPrimary)
    }
}

// MARK: - Previews

#Preview("Profile Page") {
    ProfilePageView(
        viewModel: PracticeViewModel(),
        onNavigateToCenter: {}
    )
    .previewEnvironment()
}

#Preview("Profile Stat Card") {
    HStack {
        ProfileStatCard(icon: "flame.fill", value: "7", label: "Day Streak", color: .orange)
        ProfileStatCard(icon: "checkmark.circle.fill", value: "42", label: "Practiced", color: AppColors.success)
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}
