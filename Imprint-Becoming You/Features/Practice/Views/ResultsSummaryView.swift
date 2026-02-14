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
/// ## Save Button Behavior
/// - Shows "Save" when session can be saved
/// - Transitions sharply to "Saved" after successful save (locks permanently)
/// - Disabled when playing a saved session, favorites session, or already saved
/// - Uses stable state capture to prevent visual glitch during dismissal
struct ResultsSummaryView: View {
    
    // MARK: - Properties
    
    let summary: SessionSummary
    let loopConfiguration: LoopConfiguration
    let isPlayingSavedSession: Bool
    let isFavoritesSession: Bool
    let isSessionSaved: Bool
    let currentMusicCategory: DockMusicCategory
    let onClose: () -> Void
    let onRepeat: (_ mode: SessionMode, _ loopCount: Int, _ shuffle: Bool, _ spacedRepetition: Bool) -> Void
    let onSaveSession: () -> Void
    let onToggleFavorite: (_ affirmationId: UUID) -> Void
    let onMusicSelect: (DockMusicCategory) -> Void
    
    // MARK: - State
    
    @State private var dockAdapter: ListDockAdapter
    
    /// Captured disabled state from when view appeared.
    /// Prevents button from flashing enabled when store state resets during dismissal.
    @State private var capturedSaveButtonDisabled: Bool = true
    
    /// Captured saved state - true once session has been saved.
    /// Prevents label from changing during dismissal. Locks permanently.
    @State private var capturedIsSessionSaved: Bool = false
    
    // MARK: - Constants
    
    private let dockAreaHeight: CGFloat = 120
    
    // MARK: - Computed Properties
    
    /// Whether the save button should be disabled based on current state.
    ///
    /// Disabled when:
    /// - Playing a saved session (re-saving not allowed)
    /// - Playing a favorites session (not a saveable session type)
    /// - Session has already been saved (prevents duplicates)
    private var isSaveButtonDisabled: Bool {
        isPlayingSavedSession || isFavoritesSession || isSessionSaved
    }
    
    /// Stable disabled state that never transitions from disabled to enabled.
    /// Once the button becomes disabled (initially or after saving), it stays disabled.
    /// Prevents visual glitch when store state resets during dismissal.
    private var stableSaveButtonDisabled: Bool {
        capturedSaveButtonDisabled || isSaveButtonDisabled
    }
    
    /// Accessibility label for the save button based on its state.
    private var saveButtonAccessibilityLabel: String {
        if capturedIsSessionSaved {
            return "Session saved"
        } else if isPlayingSavedSession || isFavoritesSession {
            return "Cannot save this session"
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
        currentMusicCategory: DockMusicCategory = .off,
        onClose: @escaping () -> Void,
        onRepeat: @escaping (_ mode: SessionMode, _ loopCount: Int, _ shuffle: Bool, _ spacedRepetition: Bool) -> Void,
        onSaveSession: @escaping () -> Void,
        onToggleFavorite: @escaping (_ affirmationId: UUID) -> Void,
        onMusicSelect: @escaping (DockMusicCategory) -> Void = { _ in }
    ) {
        self.summary = summary
        self.loopConfiguration = loopConfiguration
        self.isPlayingSavedSession = isPlayingSavedSession
        self.isFavoritesSession = isFavoritesSession
        self.isSessionSaved = isSessionSaved
        self.currentMusicCategory = currentMusicCategory
        self.onClose = onClose
        self.onRepeat = onRepeat
        self.onSaveSession = onSaveSession
        self.onToggleFavorite = onToggleFavorite
        self.onMusicSelect = onMusicSelect

        let initialDockMode: DockMode = {
            switch summary.mode {
            case .readOnly: return .readOnly
            case .readAloud: return .readAloud
            case .readThenSpeak: return .readAndSpeak
            case .speakOnly: return .speakOnly
            }
        }()

        let adapter = ListDockAdapter(
            initialMode: initialDockMode,
            initialLoopCount: loopConfiguration.loopCount,
            initialShuffle: loopConfiguration.isShuffleEnabled,
            initialSpacedRepetition: loopConfiguration.isSpacedRepetitionEnabled,
            initialMusic: currentMusicCategory,
            baseAffirmationCount: summary.results.count,
            showsShuffleOption: true,
            labelText: "Repeat Session",
            isPlayEnabled: true
        )
        adapter.onPlayHandler = onRepeat
        adapter.onMusicSelectHandler = onMusicSelect
        self._dockAdapter = State(initialValue: adapter)
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()

            scrollableContent
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
                Button(capturedIsSessionSaved ? "Saved" : "Save") {
                    onSaveSession()
                }
                .foregroundStyle(stableSaveButtonDisabled ? AppColors.textTertiary : AppColors.accent)
                .fontWeight(capturedIsSessionSaved ? .regular : .semibold)
                .disabled(stableSaveButtonDisabled)
                .accessibilityLabel(saveButtonAccessibilityLabel)
            }
        }
        .onAppear {
            // Capture initial state
            capturedSaveButtonDisabled = isSaveButtonDisabled
            capturedIsSessionSaved = isSessionSaved
        }
        .onChange(of: isSaveButtonDisabled) { _, newValue in
            // Once disabled, stay disabled (captures state after saving)
            if newValue {
                capturedSaveButtonDisabled = true
            }
        }
        .onChange(of: isSessionSaved) { _, newValue in
            // Once saved, stay saved (captures state after saving)
            if newValue {
                capturedIsSessionSaved = true
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
        .onTapGesture {
            guard dockAdapter.expandedSelector != nil
               || dockAdapter.isErrorBarVisible else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                dockAdapter.closeAllSelectors()
            }
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
    NavigationStack {
        ResultsSummaryView(
            summary: .sample,
            loopConfiguration: LoopConfiguration(loopCount: 3, isShuffleEnabled: true),
            isPlayingSavedSession: false,
            isFavoritesSession: false,
            isSessionSaved: false,
            onClose: {},
            onRepeat: { _, _, _, _ in },
            onSaveSession: {},
            onToggleFavorite: { _ in }
        )
    }
}

#Preview("Results Summary - Already Saved") {
    NavigationStack {
        ResultsSummaryView(
            summary: .sample,
            loopConfiguration: LoopConfiguration(loopCount: 3, isShuffleEnabled: true),
            isPlayingSavedSession: false,
            isFavoritesSession: false,
            isSessionSaved: true,
            onClose: {},
            onRepeat: { _, _, _, _ in },
            onSaveSession: {},
            onToggleFavorite: { _ in }
        )
    }
}
