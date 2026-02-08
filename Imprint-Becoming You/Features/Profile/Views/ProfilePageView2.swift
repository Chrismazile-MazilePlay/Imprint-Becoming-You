//
//  ProfilePageView2.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 02/07/26.
//

import SwiftUI
import SwiftData

// MARK: - ProfilePageView2

/// Redesigned profile page using native iOS list components with sticky header.
///
/// Features:
/// - Sticky profile header with avatar and stats
/// - Native iOS List with grouped sections
/// - Clean navigation to sub-pages
/// - Modern iOS design patterns
struct ProfilePageView2: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    
    // MARK: - Properties
    
    @Bindable var store: PracticeStore
    let onNavigateToCenter: () -> Void
    
    @Binding var navigationDepth: Int
    let isHorizontallyDragging: Bool
    let isActive: Bool
    @Binding var resetScrollToTop: Bool
    
    // MARK: - Navigation State
    
    @State private var navigationPath = NavigationPath()
    
    // MARK: - Stats State
    
    @State private var favoriteCount: Int = 0
    @State private var streak: Int = 0
    @State private var totalPracticed: Int = 0
    @State private var savedSessionCount: Int = 0
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .top) {
                // Main list content
                listContent
                
                // Sticky header overlay
                stickyHeader
                    .background(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    backToPracticeButton
                }
            }
            .navigationDestination(for: ProfileDestination.self) { destination in
                destinationView(for: destination)
            }
            .navigationDestination(for: DummyDestination.self) { destination in
                destinationView(for: destination)
            }
        }
        .tint(AppColors.accent)
        .task {
            await loadStats()
        }
        .onChange(of: navigationPath) { _, newPath in
            navigationDepth = newPath.count
            if newPath.isEmpty {
                Task { await loadStats() }
            }
        }
        .onAppear {
            navigationDepth = navigationPath.count
        }
        .onChange(of: isActive) { _, nowActive in
            if nowActive {
                Task { await loadStats() }
            }
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
    
    // MARK: - Sticky Header
    
    private var stickyHeader: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Profile Avatar and Name
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppColors.accent, AppColors.accentSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .accessibilityHidden(true)
                
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("Your Profile")
                        .font(AppTypography.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    if appState.isAuthenticated {
                        Text("Signed In")
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.success)
                    } else {
                        Text("Not Signed In")
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.top, AppTheme.Spacing.sm)
            
            // Stats Row
            HStack(spacing: 0) {
                StatPill(
                    icon: "flame.fill",
                    value: "\(streak)",
                    label: "Streak",
                    color: .orange
                )
                
                Divider()
                    .frame(height: 40)
                
                StatPill(
                    icon: "checkmark.circle.fill",
                    value: "\(totalPracticed)",
                    label: "Practiced",
                    color: AppColors.success
                )
                
                Divider()
                    .frame(height: 40)
                
                StatPill(
                    icon: "heart.fill",
                    value: "\(favoriteCount)",
                    label: "Favorites",
                    color: AppColors.accent
                )
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.sm)
        }
    }
    
    // MARK: - List Content
    
    private var listContent: some View {
        List {
            // Spacer for sticky header
            Section {
                Color.clear
                    .frame(height: 140)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            
            // Progress Section
            Section {
                Button {
                    navigateTo(.weeklyActivity)
                } label: {
                    SwipeableNavigationContent(
                        destination: DummyDestination.weeklyActivity,
                        onNavigate: navigateTo
                    ) {
                        ListRowContent(
                            icon: "chart.bar.fill",
                            iconColor: AppColors.textTertiary,
                            title: "Weekly Activity",
                            subtitle: "Coming soon"
                        )
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(AppColors.surfaceSecondary)
                
                Button {
                    navigateTo(.categoryBreakdown)
                } label: {
                    SwipeableNavigationContent(
                        destination: DummyDestination.categoryBreakdown,
                        onNavigate: navigateTo
                    ) {
                        ListRowContent(
                            icon: "chart.pie.fill",
                            iconColor: AppColors.textTertiary,
                            title: "Category Breakdown",
                            subtitle: "Coming soon"
                        )
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(AppColors.surfaceSecondary)
            } header: {
                Text("PROGRESS")
                    .font(AppTypography.caption2)
                    .fontWeight(.medium)
                    .tracking(1.2)
                    .foregroundStyle(AppColors.textTertiary)
                    .textCase(nil)
            }
            
            // Content Section
            Section {
                Button {
                    navigateTo(.favorites)
                } label: {
                    SwipeableNavigationContent(
                        destination: ProfileDestination.favorites,
                        onNavigate: navigateTo
                    ) {
                        ListRowContent(
                            icon: "heart.fill",
                            iconColor: AppColors.accent,
                            title: "Saved Affirmations",
                            subtitle: "\(favoriteCount) favorites"
                        )
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(AppColors.surfaceSecondary)
                
                Button {
                    navigateTo(.savedSessions)
                } label: {
                    SwipeableNavigationContent(
                        destination: ProfileDestination.savedSessions,
                        onNavigate: navigateTo
                    ) {
                        ListRowContent(
                            icon: "bookmark.fill",
                            iconColor: AppColors.accentSecondary,
                            title: "Saved Sessions",
                            subtitle: "\(savedSessionCount) sessions"
                        )
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(AppColors.surfaceSecondary)
            } header: {
                Text("FAVORITES")
                    .font(AppTypography.caption2)
                    .fontWeight(.medium)
                    .tracking(1.2)
                    .foregroundStyle(AppColors.textTertiary)
                    .textCase(nil)
            }
            
            // Customization Section
            Section {
                Button {
                    navigateTo(.voiceSettings)
                } label: {
                    SwipeableNavigationContent(
                        destination: ProfileDestination.voiceSettings,
                        onNavigate: navigateTo
                    ) {
                        ListRowContent(
                            icon: "waveform",
                            iconColor: AppColors.accent,
                            title: "Voice Profile",
                            subtitle: voiceProfileSubtitle
                        )
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(AppColors.surfaceSecondary)
                
                Button {
                    navigateTo(.waveformStyle)
                } label: {
                    SwipeableNavigationContent(
                        destination: ProfileDestination.waveformStyle,
                        onNavigate: navigateTo
                    ) {
                        ListRowContent(
                            icon: "waveform.path.ecg",
                            iconColor: AppColors.success,
                            title: "Waveform Style",
                            subtitle: appState.userProfile?.waveformType.displayName ?? "Layered Waves"
                        )
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(AppColors.surfaceSecondary)
                
                Button {
                    navigateTo(.goals)
                } label: {
                    SwipeableNavigationContent(
                        destination: ProfileDestination.goals,
                        onNavigate: navigateTo
                    ) {
                        ListRowContent(
                            icon: "target",
                            iconColor: AppColors.accentSecondary,
                            title: "Goals",
                            subtitle: goalsSubtitle
                        )
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(AppColors.surfaceSecondary)
            } header: {
                Text("SETTINGS")
                    .font(AppTypography.caption2)
                    .fontWeight(.medium)
                    .tracking(1.2)
                    .foregroundStyle(AppColors.textTertiary)
                    .textCase(nil)
            }
            
            // Account Section
            Section {
                Button {
                    navigateTo(.account)
                } label: {
                    SwipeableNavigationContent(
                        destination: ProfileDestination.account,
                        onNavigate: navigateTo
                    ) {
                        ListRowContent(
                            icon: "person.crop.circle",
                            iconColor: AppColors.textSecondary,
                            title: "Account",
                            subtitle: appState.isAuthenticated ? "Signed in" : "Not signed in"
                        )
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(AppColors.surfaceSecondary)
                
                if !appState.isPremium {
                    Button {
                        navigateTo(.premium)
                    } label: {
                        SwipeableNavigationContent(
                            destination: ProfileDestination.premium,
                            onNavigate: navigateTo
                        ) {
                            ListRowContent(
                                icon: "star.fill",
                                iconColor: .yellow,
                                title: "Upgrade to Premium",
                                subtitle: "Unlock all features"
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(AppColors.surfaceSecondary)
                }
                
                Button {
                    navigateTo(.help)
                } label: {
                    SwipeableNavigationContent(
                        destination: DummyDestination.help,
                        onNavigate: navigateTo
                    ) {
                        ListRowContent(
                            icon: "questionmark.circle",
                            iconColor: .blue,
                            title: "Help & Support",
                            subtitle: "Get help and send feedback"
                        )
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(AppColors.surfaceSecondary)
                
                Button {
                    navigateTo(.about)
                } label: {
                    SwipeableNavigationContent(
                        destination: DummyDestination.about,
                        onNavigate: navigateTo
                    ) {
                        ListRowContent(
                            icon: "info.circle",
                            iconColor: AppColors.textTertiary,
                            title: "About",
                            subtitle: "Version 1.0.0"
                        )
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(AppColors.surfaceSecondary)
            } header: {
                Text("ACCOUNT & SUPPORT")
                    .font(AppTypography.caption2)
                    .fontWeight(.medium)
                    .tracking(1.2)
                    .foregroundStyle(AppColors.textTertiary)
                    .textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDisabled(isHorizontallyDragging)
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
            GoalsSettingsView(store: store)
            
        case .account:
            AccountSettingsView()
            
        case .premium:
            PremiumView()
        }
    }
    
    @ViewBuilder
    private func destinationView(for destination: DummyDestination) -> some View {
        switch destination {
        case .weeklyActivity:
            DummyView(title: "Weekly Activity", icon: "chart.bar.fill")
        case .categoryBreakdown:
            DummyView(title: "Category Breakdown", icon: "chart.pie.fill")
        case .help:
            DummyView(title: "Help & Support", icon: "questionmark.circle")
        case .about:
            DummyView(title: "About", icon: "info.circle")
        }
    }
    
    /// Pops navigation stack to root and navigates to Practice page.
    private func popToRootAndNavigateToCenter() {
        navigationPath = NavigationPath()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            onNavigateToCenter()
        }
    }
    
    // MARK: - Navigation Helpers
    
    /// Navigates to a ProfileDestination
    private func navigateTo(_ destination: ProfileDestination) {
        navigationPath.append(destination)
    }
    
    /// Navigates to a DummyDestination
    private func navigateTo(_ destination: DummyDestination) {
        navigationPath.append(destination)
    }
    
    // MARK: - Waveform Type Binding
    
    private var waveformTypeBinding: Binding<DockWaveformType> {
        Binding(
            get: { appState.userProfile?.waveformType ?? .layeredWaves },
            set: { newType in
                appState.userProfile?.waveformType = newType
            }
        )
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
            totalPracticed = allProgress.reduce(0) { $0 + $1.affirmationsPracticed }
            streak = calculateStreak(from: allProgress)
        }
    }
    
    /// Calculates current streak from progress data
    private func calculateStreak(from progressData: [ProgressData]) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        let streakDays = progressData
            .filter { $0.countsTowardStreak }
            .sorted { $0.date > $1.date }
        
        guard !streakDays.isEmpty else { return 0 }
        
        var currentStreak = 0
        var expectedDate = today
        
        for progress in streakDays {
            let progressDate = calendar.startOfDay(for: progress.date)
            
            if progressDate == expectedDate {
                currentStreak += 1
                expectedDate = calendar.date(byAdding: .day, value: -1, to: expectedDate) ?? expectedDate
            } else if currentStreak == 0 && progressDate == calendar.date(byAdding: .day, value: -1, to: today) {
                currentStreak = 1
                expectedDate = calendar.date(byAdding: .day, value: -2, to: today) ?? expectedDate
            } else {
                break
            }
        }
        
        return currentStreak
    }
}

// MARK: - Supporting Views

/// Compact stat display for sticky header
struct StatPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
                
                Text(value)
                    .font(AppTypography.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColors.textPrimary)
            }
            
            Text(label)
                .font(AppTypography.caption2)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Standard list row content with icon, title, and subtitle
struct ListRowContent: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
            
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
    }
}

// MARK: - Dummy Destination

enum DummyDestination: Hashable {
    case weeklyActivity
    case categoryBreakdown
    case help
    case about
}

// MARK: - Swipeable Navigation Link

/// A custom view that wraps NavigationLink content with swipe-to-navigate gesture
struct SwipeableNavigationContent<Destination: Hashable, Content: View>: View {
    let destination: Destination
    let content: Content
    let onNavigate: (Destination) -> Void
    
    @State private var dragOffset: CGFloat = 0
    @State private var isSwipeActive = false
    
    // Swipe threshold - how far left to swipe before triggering navigation
    private let swipeThreshold: CGFloat = -80
    
    init(
        destination: Destination,
        onNavigate: @escaping (Destination) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.destination = destination
        self.onNavigate = onNavigate
        self.content = content()
    }
    
    var body: some View {
        content
            .offset(x: dragOffset)
            .opacity(1.0 - min(abs(dragOffset) / 200.0, 0.5))
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        // Only allow left swipe (negative translation)
                        if value.translation.width < 0 {
                            dragOffset = value.translation.width
                        }
                    }
                    .onEnded { value in
                        // Check if swipe passed threshold
                        if value.translation.width < swipeThreshold {
                            // Trigger navigation
                            isSwipeActive = true
                            
                            // Animate out and navigate
                            withAnimation(.easeOut(duration: 0.2)) {
                                dragOffset = -UIScreen.main.bounds.width
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                onNavigate(destination)
                                // Reset after navigation
                                dragOffset = 0
                                isSwipeActive = false
                            }
                        } else {
                            // Snap back
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
    }
}

/// Simple placeholder view for navigation destinations
struct DummyView: View {
    let title: String
    let icon: String
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Image(systemName: icon)
                .font(.system(size: 80))
                .foregroundStyle(AppColors.accent.opacity(0.3))
            
            VStack(spacing: AppTheme.Spacing.sm) {
                Text(title)
                    .font(AppTypography.title1)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColors.textPrimary)
                
                Text("This feature is coming soon")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimary)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

#Preview("Profile Page v2 - List Style") {
    struct PreviewWrapper: View {
        @State private var navigationDepth = 0
        @State private var resetScroll = false
        
        var body: some View {
            ProfilePageView2(
                store: .preview,
                onNavigateToCenter: {},
                navigationDepth: $navigationDepth,
                isHorizontallyDragging: false,
                isActive: true,
                resetScrollToTop: $resetScroll
            )
            .previewEnvironment()
        }
    }
    return PreviewWrapper()
}

#Preview("Stat Pill") {
    HStack(spacing: 0) {
        StatPill(icon: "flame.fill", value: "7", label: "Streak", color: .orange)
        Divider().frame(height: 40)
        StatPill(icon: "checkmark.circle.fill", value: "42", label: "Practiced", color: AppColors.success)
        Divider().frame(height: 40)
        StatPill(icon: "heart.fill", value: "12", label: "Favorites", color: AppColors.accent)
    }
    .padding()
    .background(.ultraThinMaterial)
}

#Preview("List Row Content") {
    List {
        ListRowContent(
            icon: "heart.fill",
            iconColor: AppColors.accent,
            title: "Saved Affirmations",
            subtitle: "24 favorites"
        )
        
        ListRowContent(
            icon: "chart.bar.fill",
            iconColor: AppColors.textTertiary,
            title: "Weekly Activity",
            subtitle: "Coming soon"
        )
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(AppColors.backgroundPrimary)
}
