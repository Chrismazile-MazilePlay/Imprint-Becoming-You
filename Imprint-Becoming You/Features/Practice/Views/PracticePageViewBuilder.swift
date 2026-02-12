//
//  PracticePageViewBuilder.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/9/26.
//

import SwiftUI

// MARK: - PracticePageViewBuilder

/// Configures the layered composition of PracticePageView.
///
/// ## Builder Pattern
/// Encapsulates the complex assembly of background, content, HUD, and dock layers
/// into a single configuration point. Each layer is an independent View struct
/// that can be tested, previewed, and swapped.
///
/// ## Layer Stack (bottom to top)
/// 1. Background layer — `MorphingBackgroundView` or `SolidBackgroundView` (swappable)
/// 2. Content layer — `AffirmationContentView` via VerticalPager
/// 3. HUD layer — `FloatingHUDLayer` (already external)
/// 4. Dock layer — `AdaptiveDockContainer` (already external)
///
/// ## Background Style Switching
/// Reads the user's `BackgroundStyle` preference and returns the appropriate
/// background view. When `morphingGradient`, returns `MorphingBackgroundView`;
/// otherwise returns `SolidBackgroundView` with the selected color.
///
/// ## Usage
/// ```swift
/// let builder = PracticePageViewBuilder(store: store, backgroundStyle: .morphingGradient)
///
/// VerticalPager(...) { index in
///     builder.buildContent(at: index, ...)
/// } background: { currentIndex, progress in
///     builder.buildBackground(currentIndex: currentIndex, progress: progress, ...)
/// }
/// ```
@MainActor
struct PracticePageViewBuilder {

    // MARK: - Properties

    /// The practice store providing state for all layers.
    let store: PracticeStore

    /// The user's selected background style.
    let backgroundStyle: BackgroundStyle

    // MARK: - Background Layer

    /// Builds the background layer based on user's background style preference.
    ///
    /// - Parameters:
    ///   - currentIndex: Current page index from VerticalPager
    ///   - progress: Drag progress from VerticalPager (-1.0 to 1.0)
    ///   - displayedCategory: Binding to the at-rest category tracker
    /// - Returns: Either `MorphingBackgroundView` or `SolidBackgroundView`
    @ViewBuilder
    func buildBackground(
        currentIndex: Int,
        progress: CGFloat,
        displayedCategory: Binding<GoalCategory?>
    ) -> some View {
        switch backgroundStyle {
        case .morphingGradient:
            MorphingBackgroundView(
                affirmations: store.affirmations,
                currentIndex: currentIndex,
                progress: progress,
                displayedCategory: displayedCategory
            )
        default:
            SolidBackgroundView(style: backgroundStyle)
        }
    }

    // MARK: - Content Layer

    /// Builds the affirmation content for a given page index.
    ///
    /// Wraps the content in a `GeometryReader` for layout calculations.
    ///
    /// - Parameters:
    ///   - index: The page index to build content for
    ///   - isScrollActive: Whether auto-scrolling is currently active
    ///   - topPadding: Top offset for HUD + centering
    ///   - bottomPadding: Bottom offset for dock area
    ///   - maxTextHeight: Maximum text height before scrolling activates
    /// - Returns: `AffirmationContentView` or empty view if index is invalid
    @ViewBuilder
    func buildContent(
        at index: Int,
        isScrollActive: Bool,
        topPadding: CGFloat,
        bottomPadding: CGFloat,
        maxTextHeight: CGFloat
    ) -> some View {
        if let affirmation = affirmation(at: index) {
            let isCurrentPage = index == store.currentIndex

            // Read decoupled listening properties instead of store.flow.listeningContext.
            // This prevents AutoScrollingAffirmationText from re-evaluating on every
            // audio level tick (~43Hz). It only re-renders when matchedWordCount changes.
            let isListening = isCurrentPage && store.isInListeningPhase

            AffirmationContentView(
                affirmation: affirmation,
                isCurrentPage: isCurrentPage,
                isScrollActive: isScrollActive,
                scrollGeneration: store.flowGeneration,
                maxTextHeight: maxTextHeight,
                isListeningMode: isListening,
                matchedWordCount: isListening ? store.listeningMatchedWordCount : 0,
                topPadding: topPadding,
                bottomPadding: bottomPadding,
                onShare: { store.send(.shareAffirmation) },
                onToggleFavorite: { store.send(.toggleFavorite) }
            )
        }
    }

    // MARK: - HUD Layer

    /// Builds the floating HUD layer (exit/navigation buttons).
    ///
    /// - Parameters:
    ///   - onProfileTap: Callback when profile button is tapped
    ///   - onPromptsTap: Callback when prompts button is tapped
    /// - Returns: `FloatingHUDLayer` configured with the store
    func buildHUD(
        onProfileTap: @escaping () -> Void,
        onPromptsTap: @escaping () -> Void
    ) -> FloatingHUDLayer {
        FloatingHUDLayer(
            store: store,
            onProfileTap: onProfileTap,
            onPromptsTap: onPromptsTap
        )
    }

    // MARK: - Dock Layer

    /// Builds the dock container with adaptive bottom dock.
    ///
    /// - Parameter adapter: The dock adapter bridging store to dock module
    /// - Returns: Configured dock container view
    @ViewBuilder
    func buildDock(adapter: PracticeDockAdapter, waveformType: DockWaveformType) -> some View {
        AdaptiveDockContainer(adapter: adapter) {
            AdaptiveBottomDock(adapter: adapter)
        }
        .imprintDockEnvironment(waveformType: waveformType)
    }

    // MARK: - Helpers

    /// Safe array access for affirmation at index.
    private func affirmation(at index: Int) -> Affirmation? {
        guard store.affirmations.indices.contains(index) else { return nil }
        return store.affirmations[index]
    }
}
