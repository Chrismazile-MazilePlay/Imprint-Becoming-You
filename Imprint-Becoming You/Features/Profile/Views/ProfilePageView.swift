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
/// - Saved Sessions section
/// - Settings section
///
/// Navigation: This page is on the RIGHT. Back navigation goes LEFT to Practice.
///
/// ## Note on Navigation
/// Since this view is inside a TabView (not a NavigationStack), we use
/// `.fullScreenCover` for the Favorites detail view instead of
/// `.navigationDestination` which requires NavigationStack.
struct ProfilePageView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    
    // MARK: - Properties
    
    @Bindable var store: PracticeStore
    let onNavigateToCenter: () -> Void
    
    // MARK: - State
    
    @State private var favoriteCount: Int = 0
    @State private var streak: Int = 0
    @State private var totalPracticed: Int = 0
    @State private var showFavorites = false
    @State private var showSavedSessions = false
    @State private var savedSessionCount: Int = 0
    @State private var showWaveformSelection = false
    
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
                    
                    // Saved Sessions section
                    savedSessionsSection
                    
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
        .onChange(of: showSavedSessions) { _, isShowing in
            // Reload stats when returning from saved sessions view
            // in case sessions were deleted
            if !isShowing {
                Task { await loadStats() }
            }
        }
        .onChange(of: showFavorites) { _, isShowing in
            // Reload stats when returning from favorites view
            if !isShowing {
                Task { await loadStats() }
            }
        }
        .fullScreenCover(isPresented: $showFavorites) {
            // Wrap in NavigationStack so FavoritesFullListView's
            // .navigationTitle and toolbar work correctly
            NavigationStack {
                FavoritesFullListView(
                    store: store,
                    dependencies: dependencies,
                    onNavigateToCenter: onNavigateToCenter
                )
            }
        }
        .fullScreenCover(isPresented: $showSavedSessions) {
            // Wrap in NavigationStack for proper navigation bar
            NavigationStack {
                SavedSessionsFullListView(
                    store: store,
                    onNavigateToCenter: onNavigateToCenter
                )
            }
        }
        .sheet(isPresented: $showWaveformSelection) {
            WaveformSelectionSheet(
                selectedType: waveformTypeBinding,
                onSave: { newType in
                    // Save is handled via binding
                }
            )
        }
    }
    
    // MARK: - Waveform Type Binding
    
    /// Binding to UserProfile's waveformType for the selection sheet
    private var waveformTypeBinding: Binding<DockWaveformType> {
        Binding(
            get: { appState.userProfile?.waveformType ?? .layeredWaves },
            set: { newType in
                appState.userProfile?.waveformType = newType
            }
        )
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
    
    // MARK: - Saved Sessions Section
    
    private var savedSessionsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            ProfileSectionHeader(title: "SAVED SESSIONS")
            
            Button {
                showSavedSessions = true
            } label: {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppColors.accentSecondary)
                        .frame(width: 32, height: 32)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Saved Sessions")
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColors.textPrimary)
                        
                        Text("\(savedSessionCount) sessions")
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
    
    /// Starts playback of a saved session with the specified loop configuration
    func playSavedSession(_ session: SavedSession, loopCount: Int, shuffleEnabled: Bool) {
        // Set loop configuration from the card controls
        let config = LoopConfiguration(
            loopCount: loopCount,
            isShuffleEnabled: shuffleEnabled,
            currentLoopIteration: 1
        )
        store.setLoopConfiguration(config)
        
        // Start the saved session
        store.send(.startSavedSession(session))
        
        // Navigate back to practice page
        onNavigateToCenter()
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
                
                // Waveform Style
                SettingsRow(
                    icon: "waveform.path",
                    iconColor: AppColors.success,
                    title: "Waveform Style",
                    subtitle: appState.userProfile?.waveformType.displayName ?? "Layered Waves"
                ) {
                    showWaveformSelection = true
                }
                
                // Goals
                SettingsRow(
                    icon: "target",
                    iconColor: AppColors.accent,
                    title: "My Goals",
                    subtitle: goalsSubtitle
                ) {
                    // TODO: Navigate to goals selection
                }
                
                // Faith Content
                SettingsRow(
                    icon: "sparkles",
                    iconColor: .purple,
                    title: "Faith Content",
                    subtitle: appState.userProfile?.includeFaithContent == true ? "Enabled" : "Disabled"
                ) {
                    // TODO: Toggle faith content
                }
                
                // Account
                SettingsRow(
                    icon: "person.crop.circle",
                    iconColor: AppColors.textSecondary,
                    title: "Account",
                    subtitle: appState.isAuthenticated ? "Signed in" : "Not signed in"
                ) {
                    // TODO: Navigate to account
                }
                
                // Premium
                if !appState.isPremium {
                    SettingsRow(
                        icon: "star.fill",
                        iconColor: .yellow,
                        title: "Upgrade to Premium",
                        subtitle: "Unlock all features"
                    ) {
                        // TODO: Show premium upsell
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private var goalsSubtitle: String {
        let goals = appState.userProfile?.selectedGoals ?? []
        if goals.isEmpty {
            return "No goals selected"
        } else if goals.count == 1 {
            return "1 goal selected"
        } else {
            return "\(goals.count) goals selected"
        }
    }
    
    private func loadStats() async {
        // Load favorites count
        let favoritesDescriptor = FetchDescriptor<Affirmation>(
            predicate: #Predicate { $0.isFavorited }
        )
        favoriteCount = (try? modelContext.fetchCount(favoritesDescriptor)) ?? 0
        
        // Load saved sessions count
        let savedSessionsDescriptor = FetchDescriptor<SavedSession>()
        savedSessionCount = (try? modelContext.fetchCount(savedSessionsDescriptor)) ?? 0
        
        // Load progress data - aggregate across all days
        let progressDescriptor = FetchDescriptor<ProgressData>()
        if let allProgress = try? modelContext.fetch(progressDescriptor) {
            // Sum total affirmations practiced across all days
            totalPracticed = allProgress.reduce(0) { $0 + $1.affirmationsPracticed }
            
            // Calculate streak from consecutive days with countsTowardStreak
            streak = calculateStreak(from: allProgress)
        }
    }
    
    /// Calculates current streak from progress data
    private func calculateStreak(from progressData: [ProgressData]) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Filter to days that count toward streak and sort by date descending
        let streakDays = progressData
            .filter { $0.countsTowardStreak }
            .sorted { $0.date > $1.date }
        
        guard !streakDays.isEmpty else { return 0 }
        
        var currentStreak = 0
        var expectedDate = today
        
        for progress in streakDays {
            let progressDate = calendar.startOfDay(for: progress.date)
            
            // Check if this is the expected date or yesterday (if we haven't practiced today yet)
            if progressDate == expectedDate {
                currentStreak += 1
                expectedDate = calendar.date(byAdding: .day, value: -1, to: expectedDate) ?? expectedDate
            } else if currentStreak == 0 && progressDate == calendar.date(byAdding: .day, value: -1, to: today) {
                // Allow starting streak from yesterday if no practice today
                currentStreak = 1
                expectedDate = calendar.date(byAdding: .day, value: -2, to: today) ?? expectedDate
            } else {
                break // Streak broken
            }
        }
        
        return currentStreak
    }
}

// MARK: - Profile Supporting Views

struct ProfileStatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(color)
            
            Text(value)
                .font(AppTypography.title2)
                .foregroundStyle(AppColors.textPrimary)
            
            Text(label)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.md)
        .background(AppColors.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
    }
}

struct ProfileSectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(AppTypography.caption2)
            .fontWeight(.medium)
            .tracking(1.2)
            .foregroundStyle(AppColors.textTertiary)
    }
}

struct ProgressPlaceholderCard: View {
    let title: String
    let subtitle: String
    let icon: String
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 44, height: 44)
                .background(AppColors.surfaceTertiary)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small))
            
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

// MARK: - Previews

#Preview("Profile Page") {
    ProfilePageView(
        store: .preview,
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
