//
//  ResultsSummaryView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/6/26.
//

import SwiftUI

// MARK: - ResultsSummaryView

/// Displays the results of a completed practice session.
struct ResultsSummaryView: View {
    
    // MARK: - Properties
    
    let summary: SessionSummary
    let loopConfiguration: LoopConfiguration
    let isPlayingSavedSession: Bool
    let isFavoritesSession: Bool
    let isSessionSaved: Bool
    let onClose: () -> Void
    let onRepeat: (_ mode: SessionMode, _ loopCount: Int, _ shuffle: Bool) -> Void
    let onSaveSession: () -> Void
    let onToggleFavorite: (_ affirmationId: UUID) -> Void
    
    // MARK: - State
    
    @State private var dockAdapter: ConfigurationDockAdapter
    
    // MARK: - Constants
    
    private let dockAreaHeight: CGFloat = 120
    
    // MARK: - Computed Properties
    
    /// Whether the save button should be disabled.
    ///
    /// Disabled when:
    /// - Playing a saved session (re-saving not allowed)
    /// - Playing a favorites session (not a saveable session type)
    /// - Session has already been saved (prevents duplicates)
    private var isSaveButtonDisabled: Bool {
        isPlayingSavedSession || isFavoritesSession || isSessionSaved
    }
    
    /// Accessibility label for the save button based on its state.
    private var saveButtonAccessibilityLabel: String {
        if isSessionSaved {
            return "Session saved"
        } else if isPlayingSavedSession {
            return "Cannot save - playing a saved session"
        } else if isFavoritesSession {
            return "Cannot save - favorites session"
        } else {
            return "Save session"
        }
    }
    
    // MARK: - Initialization
    
    init(
        summary: SessionSummary,
        loopConfiguration: LoopConfiguration,
        isPlayingSavedSession: Bool,
        isFavoritesSession: Bool,
        isSessionSaved: Bool,
        onClose: @escaping () -> Void,
        onRepeat: @escaping (_ mode: SessionMode, _ loopCount: Int, _ shuffle: Bool) -> Void,
        onSaveSession: @escaping () -> Void,
        onToggleFavorite: @escaping (_ affirmationId: UUID) -> Void
    ) {
        self.summary = summary
        self.loopConfiguration = loopConfiguration
        self.isPlayingSavedSession = isPlayingSavedSession
        self.isFavoritesSession = isFavoritesSession
        self.isSessionSaved = isSessionSaved
        self.onClose = onClose
        self.onRepeat = onRepeat
        self.onSaveSession = onSaveSession
        self.onToggleFavorite = onToggleFavorite
        
        let initialDockMode: DockMode = {
            switch summary.mode {
            case .readOnly: return .readOnly
            case .readAloud: return .readAloud
            case .readThenSpeak: return .readAndSpeak
            case .speakOnly: return .speakOnly
            }
        }()
        
        self._dockAdapter = State(initialValue: ConfigurationDockAdapter(
            initialMode: initialDockMode,
            initialLoopCount: loopConfiguration.loopCount,
            initialShuffle: loopConfiguration.isShuffleEnabled,
            labelText: "Repeat Session",
            isPlayEnabled: true,
            onPlay: onRepeat
        ))
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.backgroundPrimary
                    .ignoresSafeArea()
                
                scrollableContent
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
            .navigationTitle("Session Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onClose()
                    }
                    .foregroundStyle(AppColors.accent)
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onSaveSession()
                    } label: {
                        Image(systemName: isSaveButtonDisabled ? "checkmark.circle.fill" : "square.and.arrow.down")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundStyle(isSaveButtonDisabled ? AppColors.textTertiary : AppColors.accent)
                    .disabled(isSaveButtonDisabled)
                    .accessibilityLabel(saveButtonAccessibilityLabel)
                }
            }
        }
    }
    
    // MARK: - Scrollable Content
    
    private var scrollableContent: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xl) {
                headerSection
                cardsSection
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: dockAreaHeight)
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(AppColors.success)
            
            if let progressText = loopConfiguration.progressText {
                Text(progressText)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
            }
            
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
                .id("\(result.id.uuidString)-\(result.isFavorited)")
            }
        }
    }
}

// MARK: - Previews

#Preview("Results Summary") {
    ResultsSummaryView(
        summary: .sample,
        loopConfiguration: LoopConfiguration(loopCount: 3, isShuffleEnabled: true),
        isPlayingSavedSession: false,
        isFavoritesSession: false,
        isSessionSaved: false,
        onClose: {},
        onRepeat: { _, _, _ in },
        onSaveSession: {},
        onToggleFavorite: { _ in }
    )
}

#Preview("Results Summary - Already Saved") {
    ResultsSummaryView(
        summary: .sample,
        loopConfiguration: LoopConfiguration(loopCount: 3, isShuffleEnabled: true),
        isPlayingSavedSession: false,
        isFavoritesSession: false,
        isSessionSaved: true,
        onClose: {},
        onRepeat: { _, _, _ in },
        onSaveSession: {},
        onToggleFavorite: { _ in }
    )
}
