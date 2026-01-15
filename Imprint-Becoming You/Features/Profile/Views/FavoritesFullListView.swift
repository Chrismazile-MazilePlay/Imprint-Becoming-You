//
//  FavoritesFullListView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/14/26.
//

import SwiftUI
import SwiftData

// MARK: - FavoritesFullListView

/// Full list of favorites accessible from Profile page.
///
/// Uses `AffirmationListCard` for consistent card styling and
/// `AdaptiveDockContainer` for unified dock/menu handling.
///
/// ## Scroll Indicator
/// Uses `safeAreaInset(edge: .bottom)` to ensure the scroll indicator
/// remains visible above the gradient/dock overlay.
///
/// ## Layout
/// ```
/// ┌─────────────────────────────────────────────────────────────────────┐
/// │  Close                        Favorites                             │
/// ├─────────────────────────────────────────────────────────────────────┤
/// │  ┌───────────────────────────────────────────────────────────────┐  │
/// │  │  [Category]                                                   │  │
/// │  │  "Affirmation text..."                                        │  │
/// │  │  Saved 2 days ago                                        ♡   │  │
/// │  └───────────────────────────────────────────────────────────────┘  │
/// │  ┌───────────────────────────────────────────────────────────────┐  │
/// │  │  [Category]                                                   │  │  ← Card list
/// │  │  "Another affirmation..."                                     │  │
/// │  │  Saved 1 hour ago                                        ♡   │  │
/// │  └───────────────────────────────────────────────────────────────┘  │
/// │                                                                     │
/// ├═════════════════════════════════════════════════════════════════════┤  ← Gradient
/// │              Practice 9 affirmations                                │  ← Label
/// │ [Mode ▼]            [🔁 3] [🔀]              [▶]                   │  ← Dock
/// └─────────────────────────────────────────────────────────────────────┘
/// ```
struct FavoritesFullListView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Properties
    
    @Bindable var store: PracticeStore
    let dependencies: DependencyContainer
    
    /// Callback when navigating to practice (after starting a session)
    let onNavigateToCenter: () -> Void
    
    // MARK: - State
    
    @State private var favorites: [Affirmation] = []
    
    // MARK: - Configuration State
    
    @State private var selectedMode: SessionMode = .readThenSpeak
    @State private var loopCount: Int = 1
    @State private var shuffleEnabled: Bool = false
    @State private var isModeSelectorExpanded: Bool = false
    
    // MARK: - Constants
    
    /// Height reserved for the dock area at bottom (for safeAreaInset)
    private let dockAreaHeight: CGFloat = 110
    
    // MARK: - Computed Properties
    
    private var hasFavorites: Bool {
        !favorites.isEmpty
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()
            
            // Content
            if favorites.isEmpty {
                emptyState
            } else {
                favoritesList
            }
            
            // Fixed dock area
            // AdaptiveDockContainer handles:
            // - Dismiss overlay for menus
            // - Menu expansion (Mode selector)
            // - Gradient fade
            // - Dock positioning
            AdaptiveDockContainer.favorites(
                count: favorites.count,
                isModeSelectorExpanded: $isModeSelectorExpanded,
                selectedMode: $selectedMode
            ) {
                AdaptiveBottomDock(
                    selectedMode: $selectedMode,
                    loopCount: $loopCount,
                    shuffleEnabled: $shuffleEnabled,
                    isModeSelectorExpanded: $isModeSelectorExpanded,
                    isPlayEnabled: hasFavorites,
                    isDisabled: !hasFavorites,
                    onPlay: {
                        startFavoritesSession()
                    }
                )
            }
        }
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
                .foregroundStyle(AppColors.accent)
            }
        }
        .task {
            await loadFavorites()
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Spacer()
            
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
            
            Spacer()
        }
        .padding(AppTheme.Spacing.xl)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: dockAreaHeight)
        }
    }
    
    // MARK: - Favorites List
    
    private var favoritesList: some View {
        ScrollView {
            LazyVStack(spacing: AppTheme.Spacing.md) {
                ForEach(favorites) { affirmation in
                    AffirmationListCard(
                        text: affirmation.text,
                        category: affirmation.goalCategory,
                        context: .favorites(savedAt: affirmation.favoritedAt),
                        isFavorited: true,
                        onToggleFavorite: {
                            unfavorite(affirmation)
                        }
                    )
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: dockAreaHeight)
        }
    }
    
    // MARK: - Actions
    
    private func loadFavorites() async {
        let descriptor = FetchDescriptor<Affirmation>(
            predicate: #Predicate { $0.isFavorited },
            sortBy: [SortDescriptor(\.favoritedAt, order: .reverse)]
        )
        favorites = (try? modelContext.fetch(descriptor)) ?? []
    }
    
    private func startFavoritesSession() {
        let repository = dependencies.makeAffirmationRepository(modelContext: modelContext)
        
        // Configure loop settings before starting
        let config = LoopConfiguration(
            loopCount: loopCount,
            isShuffleEnabled: shuffleEnabled,
            currentLoopIteration: 1
        )
        store.setLoopConfiguration(config)
        
        Task {
            await store.loadFavoritesAsSession(
                using: repository,
                mode: selectedMode,
                shuffle: shuffleEnabled
            )
            dismiss()
            onNavigateToCenter()
        }
    }
    
    private func unfavorite(_ affirmation: Affirmation) {
        affirmation.isFavorited = false
        affirmation.favoritedAt = nil
        favorites.removeAll { $0.id == affirmation.id }
        HapticFeedback.impact(.light)
    }
}

// MARK: - Previews

#Preview("Favorites Full List") {
    NavigationStack {
        FavoritesFullListView(
            store: .preview,
            dependencies: .preview,
            onNavigateToCenter: {}
        )
    }
    .previewEnvironment()
}
