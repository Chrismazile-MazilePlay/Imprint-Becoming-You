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
/// ## Navigation
/// This view is pushed onto the Profile navigation stack.
/// When starting a session, it pops back to Profile root
/// then triggers navigation to Practice page.
struct FavoritesFullListView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - Properties
    
    @Bindable var store: PracticeStore
    let dependencies: DependencyContainer
    
    /// Called when user starts a session - should pop to root and navigate to Practice
    let onStartSession: () -> Void
    
    // MARK: - State
    
    @State private var favorites: [Affirmation] = []
    @State private var dockAdapter: ConfigurationDockAdapter
    
    // MARK: - Constants
    
    private let dockAreaHeight: CGFloat = 120
    
    // MARK: - Initialization
    
    init(
        store: PracticeStore,
        dependencies: DependencyContainer,
        onStartSession: @escaping () -> Void
    ) {
        self.store = store
        self.dependencies = dependencies
        self.onStartSession = onStartSession
        
        self._dockAdapter = State(initialValue: ConfigurationDockAdapter(
            labelText: "Loading...",
            isPlayEnabled: false,
            onPlay: { _, _, _ in }
        ))
    }
    
    // MARK: - Body
    
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
        .dismissesDockMenuOnTouch(adapter: dockAdapter)
        .overlay {
            VStack {
                Spacer()
                AdaptiveDockContainer(adapter: dockAdapter, showsGradient: true) {
                    AdaptiveBottomDock(adapter: dockAdapter)
                }
                .imprintDockEnvironment()
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.inline)
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
                .accessibilityHidden(true)
            
            Text("No Favorites Yet")
                .font(AppTypography.title3)
                .foregroundStyle(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No favorites yet. Tap the heart on any affirmation to save it here.")
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
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(affirmation.text). Category: \(affirmation.category). Favorited.")
                    .accessibilityHint("Double tap to remove from favorites")
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: dockAreaHeight)
        }
        .accessibilityLabel("Favorites list, \(favorites.count) items")
    }
    
    // MARK: - Actions
    
    private func loadFavorites() async {
        let descriptor = FetchDescriptor<Affirmation>(
            predicate: #Predicate { $0.isFavorited },
            sortBy: [SortDescriptor(\.favoritedAt, order: .reverse)]
        )
        favorites = (try? modelContext.fetch(descriptor)) ?? []
        updateDockAdapter()
    }
    
    private func updateDockAdapter() {
        let count = favorites.count
        let labelText = count > 0 ? "Practice \(count) affirmation\(count == 1 ? "" : "s")" : "No favorites yet"
        
        dockAdapter = ConfigurationDockAdapter(
            initialMode: dockAdapter.currentMode,
            initialLoopCount: dockAdapter.loopCount,
            initialShuffle: dockAdapter.isShuffleEnabled,
            labelText: labelText,
            isPlayEnabled: count > 0,
            onPlay: { [self] mode, loopCount, shuffle in
                startFavoritesSession(mode: mode, loopCount: loopCount, shuffle: shuffle)
            }
        )
    }
    
    private func startFavoritesSession(mode: SessionMode, loopCount: Int, shuffle: Bool) {
        let repository = dependencies.makeAffirmationRepository(modelContext: modelContext)
        
        let config = LoopConfiguration(
            loopCount: loopCount,
            isShuffleEnabled: shuffle,
            currentLoopIteration: 1
        )
        store.setLoopConfiguration(config)
        
        Task {
            await store.loadFavoritesAsSession(
                using: repository,
                mode: mode,
                shuffle: shuffle
            )
            // Pop to root and navigate to Practice
            onStartSession()
        }
    }
    
    private func unfavorite(_ affirmation: Affirmation) {
        affirmation.isFavorited = false
        affirmation.favoritedAt = nil
        favorites.removeAll { $0.id == affirmation.id }
        HapticFeedback.impact(.light)
        updateDockAdapter()
    }
}

// MARK: - Previews

#Preview("Favorites Full List") {
    NavigationStack {
        FavoritesFullListView(
            store: .preview,
            dependencies: .preview,
            onStartSession: {}
        )
    }
    .previewEnvironment()
}
