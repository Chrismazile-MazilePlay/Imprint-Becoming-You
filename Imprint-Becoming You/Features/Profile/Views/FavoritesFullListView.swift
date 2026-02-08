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
    @State private var dockAdapter: ListDockAdapter

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

        self._dockAdapter = State(initialValue: ListDockAdapter(
            showsShuffleOption: true,
            labelText: "Loading...",
            isPlayEnabled: false
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
        .onDisappear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                dockAdapter.closeAllSelectors()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Spacer()

            Image(systemName: "heart.slash")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textSecondary.opacity(0.5))

            Text("No Favorites Yet")
                .font(AppTypography.title3)
                .foregroundStyle(AppColors.textPrimary)

            Text("Heart affirmations during practice to add them here.")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.Spacing.xl)

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No favorites yet. Heart affirmations during practice to add them here.")
    }

    // MARK: - Favorites List

    private var favoritesList: some View {
        ScrollView {
            LazyVStack(spacing: AppTheme.Spacing.md) {
                ForEach(favorites) { affirmation in
                    AffirmationListCard(
                        text: affirmation.text,
                        category: GoalCategory(rawValue: affirmation.category),
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
        .onTapGesture {
            guard dockAdapter.isModeSelectorExpanded
               || dockAdapter.isBinauralSelectorExpanded
               || dockAdapter.isConfigSelectorExpanded
               || dockAdapter.isErrorBarVisible else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                dockAdapter.closeAllSelectors()
            }
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
        updateDockState()
    }

    /// Updates dock adapter properties directly — no instance replacement.
    private func updateDockState() {
        let count = favorites.count
        dockAdapter.labelText = count > 0 ? "Practice \(count) affirmation\(count == 1 ? "" : "s")" : "No favorites yet"
        dockAdapter.isPlayEnabled = count > 0
        dockAdapter.onPlayHandler = { [self] mode, loopCount, shuffle in
            startFavoritesSession(mode: mode, loopCount: loopCount, shuffle: shuffle)
        }
    }

    /// Starts a favorites session using the synchronous event-driven pattern.
    ///
    /// Mirrors the saved session flow in `SavedSessionsFullListView`:
    /// set loop config -> send event -> pop to root.
    /// Affirmations are passed directly (already loaded), avoiding any `async`
    /// suspension that could cause voice ID staleness.
    private func startFavoritesSession(mode: SessionMode, loopCount: Int, shuffle: Bool) {
        let config = LoopConfiguration(
            loopCount: loopCount,
            isShuffleEnabled: shuffle,
            currentLoopIteration: 1
        )
        store.setLoopConfiguration(config)

        store.send(.startFavoritesSession(
            affirmations: favorites,
            mode: mode,
            shuffle: shuffle
        ))

        // Pop to root and navigate to Practice
        onStartSession()
    }

    private func unfavorite(_ affirmation: Affirmation) {
        affirmation.isFavorited = false
        affirmation.favoritedAt = nil
        favorites.removeAll { $0.id == affirmation.id }
        HapticFeedback.impact(.light)
        updateDockState()
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
