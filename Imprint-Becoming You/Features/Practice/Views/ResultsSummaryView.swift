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
    let onClose: () -> Void
    let onRepeat: (_ mode: SessionMode, _ loopCount: Int, _ shuffle: Bool) -> Void
    let onSaveSession: () -> Void
    let onToggleFavorite: (_ affirmationId: UUID) -> Void
    
    // MARK: - State
    
    @State private var dockAdapter: ConfigurationDockAdapter
    
    // MARK: - Constants
    
    private let dockAreaHeight: CGFloat = 120
    
    // MARK: - Initialization
    
    init(
        summary: SessionSummary,
        loopConfiguration: LoopConfiguration,
        isPlayingSavedSession: Bool,
        isFavoritesSession: Bool,
        onClose: @escaping () -> Void,
        onRepeat: @escaping (_ mode: SessionMode, _ loopCount: Int, _ shuffle: Bool) -> Void,
        onSaveSession: @escaping () -> Void,
        onToggleFavorite: @escaping (_ affirmationId: UUID) -> Void
    ) {
        self.summary = summary
        self.loopConfiguration = loopConfiguration
        self.isPlayingSavedSession = isPlayingSavedSession
        self.isFavoritesSession = isFavoritesSession
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
                
                if !isPlayingSavedSession && !isFavoritesSession {
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
        onClose: {},
        onRepeat: { _, _, _ in },
        onSaveSession: {},
        onToggleFavorite: { _ in }
    )
}
