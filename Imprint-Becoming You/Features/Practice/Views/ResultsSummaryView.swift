//
//  ResultsSummaryView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/6/26.
//

import SwiftUI

// MARK: - ResultsSummaryView

/// Displays the results of a completed practice session.
///
/// Uses NavigationStack with standard nav bar for proper scroll behavior
/// and `DockGradientContainer` for clean visual separation.
///
/// ## Layout
/// ```
/// ┌─────────────────────────────────────────────┐
/// │  Close        Session Complete        Save  │  ← Nav bar
/// ├─────────────────────────────────────────────┤
/// │              ✓                              │  ← SF Symbol
/// │        Loop 2 of 3 (if looping)             │  ← Loop progress
/// │                                             │
/// │  ┌─────────────────────────────────────┐   │
/// │  │  Scored Card 1                      │   │
/// │  └─────────────────────────────────────┘   │
/// │  ┌─────────────────────────────────────┐   │  ← Scrollable cards
/// │  │  Scored Card 2                      │   │
/// │  └─────────────────────────────────────┘   │
/// │                                             │
/// ├═════════════════════════════════════════════┤  ← Gradient
/// │  [Mode ▼]       [🔁 3] [🔀]         [▶]    │  ← Dock
/// │            Repeat Session                   │  ← Label (under dock)
/// └─────────────────────────────────────────────┘
/// ```
struct ResultsSummaryView: View {
    
    // MARK: - Environment
    
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Properties
    
    /// The session summary to display
    let summary: SessionSummary
    
    /// Current loop configuration
    let loopConfiguration: LoopConfiguration
    
    /// Whether currently playing a saved session
    let isPlayingSavedSession: Bool
    
    /// Callback when close is tapped
    let onClose: () -> Void
    
    /// Callback when repeat is tapped with selected configuration
    let onRepeat: (_ mode: SessionMode, _ loopCount: Int, _ shuffle: Bool) -> Void
    
    /// Callback when save session is tapped
    let onSaveSession: () -> Void
    
    /// Callback when favorite is toggled for an affirmation
    /// - Parameter affirmationId: The ID of the affirmation to toggle
    let onToggleFavorite: (_ affirmationId: UUID) -> Void
    
    // MARK: - State
    
    /// Selected mode (defaults to the mode that was just played)
    @State private var selectedMode: SessionMode
    
    /// Loop count for repeat
    @State private var loopCount: Int
    
    /// Shuffle enabled for repeat
    @State private var shuffleEnabled: Bool
    
    /// Whether mode selector is expanded
    @State private var isModeSelectorExpanded: Bool = false
    
    // MARK: - Constants
    
    /// Height reserved for the dock area at bottom
    private let dockAreaHeight: CGFloat = 160
    
    // MARK: - Initialization
    
    init(
        summary: SessionSummary,
        loopConfiguration: LoopConfiguration,
        isPlayingSavedSession: Bool,
        onClose: @escaping () -> Void,
        onRepeat: @escaping (_ mode: SessionMode, _ loopCount: Int, _ shuffle: Bool) -> Void,
        onSaveSession: @escaping () -> Void,
        onToggleFavorite: @escaping (_ affirmationId: UUID) -> Void
    ) {
        self.summary = summary
        self.loopConfiguration = loopConfiguration
        self.isPlayingSavedSession = isPlayingSavedSession
        self.onClose = onClose
        self.onRepeat = onRepeat
        self.onSaveSession = onSaveSession
        self.onToggleFavorite = onToggleFavorite
        
        // Initialize state with current session values
        _selectedMode = State(initialValue: summary.mode)
        _loopCount = State(initialValue: loopConfiguration.loopCount)
        _shuffleEnabled = State(initialValue: loopConfiguration.isShuffleEnabled)
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                AppColors.backgroundPrimary
                    .ignoresSafeArea()
                
                // Scrollable content
                scrollableContent
                
                // Fixed dock area with gradient
                VStack {
                    Spacer()
                    dockArea
                }
                .ignoresSafeArea(.keyboard)
            }
            .navigationTitle("Session Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onClose()
                    }
                    .foregroundStyle(AppColors.accent)
                }
                
                // Save button in nav bar (hidden if playing saved session)
                if !isPlayingSavedSession {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            onSaveSession()
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundStyle(AppColors.accent)
                        .accessibilityLabel("Save session")
                    }
                }
            }
        }
    }
    
    // MARK: - Scrollable Content
    
    private var scrollableContent: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xl) {
                // Header
                headerSection
                
                // Affirmation cards (sorted: scored first, then skipped)
                cardsSection
                
                // Bottom padding to clear the dock area
                Spacer()
                    .frame(height: dockAreaHeight)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            // Checkmark icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(AppColors.success)
            
            // Loop progress - only show when looping is active
            if let progressText = loopConfiguration.progressText {
                Text(progressText)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
            }
            
            // Saved session title (if playing saved)
            if let savedTitle = summary.savedSessionTitle {
                Text(savedTitle)
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.top, loopConfiguration.progressText == nil ? AppTheme.Spacing.xs : 0)
            }
        }
        .padding(.top, AppTheme.Spacing.lg)
        .padding(.bottom, AppTheme.Spacing.md)
    }
    
    // MARK: - Cards Section
    
    private var cardsSection: some View {
        LazyVStack(spacing: AppTheme.Spacing.md) {
            ForEach(summary.sortedResults) { result in
                SessionAffirmationCard(
                    result: result,
                    loopCount: summary.loopCount,
                    onToggleFavorite: {
                        onToggleFavorite(result.affirmationId)
                    }
                )
                // Use composite id that includes isFavorited to force re-render
                .id("\(result.id.uuidString)-\(result.isFavorited)")
            }
        }
    }
    
    // MARK: - Dock Area
    
    private var dockArea: some View {
        DockGradientContainer.resultsSummary(
            isModeSelectorExpanded: $isModeSelectorExpanded,
            selectedMode: $selectedMode
        ) {
            AdaptiveBottomDock(
                selectedMode: $selectedMode,
                loopCount: $loopCount,
                shuffleEnabled: $shuffleEnabled,
                isModeSelectorExpanded: $isModeSelectorExpanded,
                onPlay: {
                    onRepeat(selectedMode, loopCount, shuffleEnabled)
                }
            )
        }
    }
}

// MARK: - Previews

#Preview("Results Summary") {
    ResultsSummaryView(
        summary: .sample,
        loopConfiguration: LoopConfiguration(loopCount: 3, isShuffleEnabled: true),
        isPlayingSavedSession: false,
        onClose: {},
        onRepeat: { mode, loops, shuffle in
            print("Repeat: \(mode.displayName), \(loops)x, shuffle: \(shuffle)")
        },
        onSaveSession: {},
        onToggleFavorite: { _ in }
    )
}

#Preview("Results Summary - Playing Saved Session") {
    ResultsSummaryView(
        summary: SessionSummary(
            mode: .readThenSpeak,
            results: SessionAffirmationResult.samples,
            startedAt: Date().addingTimeInterval(-300),
            loopCount: 1,
            savedSessionId: UUID(),
            savedSessionTitle: "Morning Confidence"
        ),
        loopConfiguration: .default,
        isPlayingSavedSession: true,
        onClose: {},
        onRepeat: { _, _, _ in },
        onSaveSession: {},
        onToggleFavorite: { _ in }
    )
}

#Preview("Results Summary - Looping Active") {
    ResultsSummaryView(
        summary: .sample,
        loopConfiguration: LoopConfiguration(
            loopCount: 5,
            isShuffleEnabled: false,
            currentLoopIteration: 3
        ),
        isPlayingSavedSession: false,
        onClose: {},
        onRepeat: { _, _, _ in },
        onSaveSession: {},
        onToggleFavorite: { _ in }
    )
}
