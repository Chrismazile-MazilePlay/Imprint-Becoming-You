//
//  ProfilePageView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/22/25.
//

import SwiftUI
import SwiftData

// MARK: - ProfileDestination

/// Navigation destinations for the Profile flow.
///
/// Used with NavigationStack's type-safe navigation path.
enum ProfileDestination: Hashable {
    case favorites
    case savedSessions
    case voiceSettings
    case waveformStyle
    case goals
    case account
    case premium
}

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
/// ## Navigation Architecture
/// Uses a single NavigationStack with type-safe navigation path.
/// All sub-pages push onto the stack and use standard back navigation.
/// The profile header scrolls under the navbar as standard iOS behavior.
struct ProfilePageView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    
    // MARK: - Properties
    
    @Bindable var store: PracticeStore
    let onNavigateToCenter: () -> Void
    
    /// Binding to communicate navigation depth to parent.
    /// Parent uses this to disable pager gestures when depth > 0.
    @Binding var navigationDepth: Int
    
    /// Whether the horizontal pager is actively being dragged.
    /// Used to disable vertical scrolling during horizontal paging.
    let isHorizontallyDragging: Bool
    
    /// Whether this page is currently the active/visible page.
    /// Used to reset scroll position when navigating to this page.
    let isActive: Bool
    
    // MARK: - Navigation State
    
    /// Navigation path owned by this view
    @State private var navigationPath = NavigationPath()
    
    // MARK: - Stats State
    
    @State private var favoriteCount: Int = 0
    @State private var streak: Int = 0
    @State private var totalPracticed: Int = 0
    @State private var savedSessionCount: Int = 0
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            scrollContent
                .background(AppColors.backgroundPrimary)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        backToPracticeButton
                    }
                }
                .navigationDestination(for: ProfileDestination.self) { destination in
                    destinationView(for: destination)
                }
        }
        .tint(AppColors.accent) // Accent color for all nested back buttons
        .task {
            await loadStats()
        }
        .onChange(of: navigationPath) { oldPath, newPath in
            // Publish depth to parent for gesture control
            navigationDepth = newPath.count
            
            #if DEBUG
            print("🔵 [ProfilePageView] navigationPath changed: \(oldPath.count) → \(newPath.count)")
            print("🔵 [ProfilePageView] Published navigationDepth: \(navigationDepth)")
            #endif
            
            // Reload stats when returning to root (path becomes empty)
            if newPath.isEmpty {
                Task { await loadStats() }
            }
        }
        .onAppear {
            // Sync depth on appear
            navigationDepth = navigationPath.count
            #if DEBUG
            print("🔵 [ProfilePageView] onAppear - navigationPath.count: \(navigationPath.count)")
            #endif
        }
        .onDisappear {
            #if DEBUG
            print("🔵 [ProfilePageView] onDisappear - navigationPath.count: \(navigationPath.count)")
            #endif
        }
    }
    
    // MARK: - Back Button
    
    private var backToPracticeButton: some View {
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
        .accessibilityLabel("Back to Practice")
        .accessibilityHint("Return to the practice screen")
    }
    
    // MARK: - Scroll Content
    
    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    // Profile header (scrolls under navbar)
                    profileHeader
                        .id("profileTop") // Anchor for scroll-to-top
                    
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
            .scrollDisabled(isHorizontallyDragging)
            .onChange(of: isActive) { _, nowActive in
                // Scroll to top when this page becomes active
                if nowActive {
                    proxy.scrollTo("profileTop", anchor: .top)
                }
            }
        }
    }
    
    // MARK: - Navigation Destinations
    
    @ViewBuilder
    private func destinationView(for destination: ProfileDestination) -> some View {
        switch destination {
        case .favorites:
            FavoritesFullListView(
                store: store,
                dependencies: dependencies,
                onStartSession: {
                    popToRootAndNavigateToCenter()
                }
            )
            
        case .savedSessions:
            SavedSessionsFullListView(
                store: store,
                onStartSession: {
                    popToRootAndNavigateToCenter()
                }
            )
            
        case .voiceSettings:
            VoiceSettingsView()
            
        case .waveformStyle:
            WaveformSelectionView(selectedType: waveformTypeBinding)
            
        case .goals:
            GoalsSettingsView()
            
        case .account:
            AccountSettingsView()
            
        case .premium:
            PremiumView()
        }
    }
    
    /// Pops navigation stack to root and navigates to Practice page.
    ///
    /// Used when starting a session from Favorites or Saved Sessions.
    /// Ensures clean navigation state before transitioning.
    private func popToRootAndNavigateToCenter() {
        navigationPath = NavigationPath()
        // Small delay to allow stack to clear before page transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            onNavigateToCenter()
        }
    }
    
    // MARK: - Waveform Type Binding
    
    /// Binding to UserProfile's waveformType for the selection view
    private var waveformTypeBinding: Binding<DockWaveformType> {
        Binding(
            get: { appState.userProfile?.waveformType ?? .layeredWaves },
            set: { newType in
                appState.userProfile?.waveformType = newType
            }
        )
    }
    
    // MARK: - Profile Header
    
    private var profileHeader: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Avatar
            Image(systemName: "person.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(AppColors.accent.opacity(0.8))
                .accessibilityHidden(true)
            
            // Welcome text
            VStack(spacing: AppTheme.Spacing.xs) {
                Text("Your Profile")
                    .font(AppTypography.title2)
                    .foregroundStyle(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                
                Text("Track your journey")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your Profile. Track your journey")
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(streak) day streak")
            
            ProfileStatCard(
                icon: "checkmark.circle.fill",
                value: "\(totalPracticed)",
                label: "Practiced",
                color: AppColors.success
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(totalPracticed) affirmations practiced")
            
            ProfileStatCard(
                icon: "heart.fill",
                value: "\(favoriteCount)",
                label: "Favorites",
                color: AppColors.accent
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(favoriteCount) favorites")
        }
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            ProfileSectionHeader(title: "PROGRESS")
                .accessibilityAddTraits(.isHeader)
            
            ProgressPlaceholderCard(
                title: "Weekly Activity",
                subtitle: "Coming soon",
                icon: "chart.bar.fill"
            )
            .accessibilityLabel("Weekly Activity chart. Coming soon")
            
            ProgressPlaceholderCard(
                title: "Category Breakdown",
                subtitle: "Coming soon",
                icon: "chart.pie.fill"
            )
            .accessibilityLabel("Category Breakdown chart. Coming soon")
        }
    }
    
    // MARK: - Favorites Section
    
    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            ProfileSectionHeader(title: "FAVORITES")
                .accessibilityAddTraits(.isHeader)
            
            Button {
                navigateTo(.favorites)
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
                        
                        Text("\(favoriteCount) favorites")
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
            .accessibilityLabel("Saved Affirmations, \(favoriteCount) favorites")
            .accessibilityHint("View and manage your favorite affirmations")
        }
    }
    
    // MARK: - Saved Sessions Section
    
    private var savedSessionsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            ProfileSectionHeader(title: "SAVED SESSIONS")
                .accessibilityAddTraits(.isHeader)
            
            Button {
                navigateTo(.savedSessions)
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
            .accessibilityLabel("Saved Sessions, \(savedSessionCount) sessions")
            .accessibilityHint("View and play your saved sessions")
        }
    }
    
    // MARK: - Settings Section
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            ProfileSectionHeader(title: "SETTINGS")
                .accessibilityAddTraits(.isHeader)
            
            VStack(spacing: AppTheme.Spacing.sm) {
                // Voice Profile
                SettingsRow(
                    icon: "waveform",
                    iconColor: AppColors.accent,
                    title: "Voice Profile",
                    subtitle: voiceProfileSubtitle
                ) {
                    navigateTo(.voiceSettings)
                }
                .accessibilityLabel("Voice Profile, \(voiceProfileSubtitle)")
                .accessibilityHint("Change your preferred voice for affirmations")
                
                // Waveform Style
                SettingsRow(
                    icon: "waveform.path.ecg",
                    iconColor: AppColors.success,
                    title: "Waveform Style",
                    subtitle: appState.userProfile?.waveformType.displayName ?? "Layered Waves"
                ) {
                    navigateTo(.waveformStyle)
                }
                .accessibilityLabel("Waveform Style, \(appState.userProfile?.waveformType.displayName ?? "Layered Waves")")
                .accessibilityHint("Change your waveform visualization style")
                
                // Goals
                SettingsRow(
                    icon: "target",
                    iconColor: AppColors.accentSecondary,
                    title: "Goals",
                    subtitle: goalsSubtitle
                ) {
                    navigateTo(.goals)
                }
                .accessibilityLabel("Goals, \(goalsSubtitle)")
                .accessibilityHint("Update your affirmation goals")
                
                // Account
                SettingsRow(
                    icon: "person.crop.circle",
                    iconColor: AppColors.textSecondary,
                    title: "Account",
                    subtitle: appState.isAuthenticated ? "Signed in" : "Not signed in"
                ) {
                    navigateTo(.account)
                }
                .accessibilityLabel("Account, \(appState.isAuthenticated ? "Signed in" : "Not signed in")")
                .accessibilityHint("Manage your account settings")
                
                // Premium
                if !appState.isPremium {
                    SettingsRow(
                        icon: "star.fill",
                        iconColor: .yellow,
                        title: "Upgrade to Premium",
                        subtitle: "Unlock all features"
                    ) {
                        navigateTo(.premium)
                    }
                    .accessibilityLabel("Upgrade to Premium")
                    .accessibilityHint("View premium features and pricing")
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
    
    private var voiceProfileSubtitle: String {
        let selectedId = appState.userProfile?.selectedVoiceId
        let voice = Voice.voice(forId: selectedId)
        return voice.displayNameWithDefault
    }
    
    // MARK: - Navigation Helper
    
    /// Navigates to a destination with debug logging.
    private func navigateTo(_ destination: ProfileDestination) {
        #if DEBUG
        print("🔷 [ProfilePageView] navigateTo(\(destination)) called")
        print("   - navigationPath.count BEFORE: \(navigationPath.count)")
        #endif
        
        navigationPath.append(destination)
        
        #if DEBUG
        print("   - navigationPath.count AFTER: \(navigationPath.count)")
        #endif
    }
    
    // MARK: - Data Loading
    
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
    struct PreviewWrapper: View {
        @State private var navigationDepth = 0
        
        var body: some View {
            ProfilePageView(
                store: .preview,
                onNavigateToCenter: {},
                navigationDepth: $navigationDepth,
                isHorizontallyDragging: false,
                isActive: true
            )
            .previewEnvironment()
        }
    }
    return PreviewWrapper()
}

#Preview("Profile Stat Card") {
    HStack {
        ProfileStatCard(icon: "flame.fill", value: "7", label: "Day Streak", color: .orange)
        ProfileStatCard(icon: "checkmark.circle.fill", value: "42", label: "Practiced", color: AppColors.success)
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}
