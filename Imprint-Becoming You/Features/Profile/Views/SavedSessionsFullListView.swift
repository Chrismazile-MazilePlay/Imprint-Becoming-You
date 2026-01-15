//
//  SavedSessionsFullListView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/12/26.
//

import SwiftUI
import SwiftData

// MARK: - SavedSessionsFullListView

/// Full list of saved sessions with selection-based playback.
///
/// Uses the unified `AdaptiveBottomDock` in configuration mode.
/// The dock is fixed at the bottom with the mode selector sliding up.
///
/// ## Scroll Indicator
/// Uses `safeAreaInset(edge: .bottom)` to ensure the scroll indicator
/// remains visible above the gradient/dock overlay.
///
/// ## Layout
/// ```
/// ┌─────────────────────────────────────────────────────────────────────┐
/// │  Close                    Saved Sessions                            │  ← Nav bar (normal)
/// ├─────────────────────────────────────────────────────────────────────┤
/// │  ┌───────────────────────────────────────────────────────────────┐  │
/// │  │  Session 1                                        ✏️  ⓘ       │  │
/// │  │  5 affirmations • Last played today                           │  │
/// │  └───────────────────────────────────────────────────────────────┘  │
/// │  ┌═══════════════════════════════════════════════════════════════┐  │
/// │  ║  Session 2 (selected)                             ✏️  ⓘ       ║  │  ← Accent border
/// │  ║  3 affirmations • Last played yesterday                       ║  │
/// │  └═══════════════════════════════════════════════════════════════┘  │
/// ├═════════════════════════════════════════════════════════════════════┤  ← Fixed dock boundary
/// │       [Mode Selector - slides up]                                   │
/// │ [Mode]            [Loop] [Shuffle]              [▶]                │  ← Dock (no label for saved)
/// └─────────────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Keyboard Behavior
/// The dock stays fixed at the bottom. When editing a session
/// title, the keyboard rises and covers the dock (it does not push it up).
struct SavedSessionsFullListView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var dependencies
    @Environment(\.appState) private var appState
    
    // MARK: - Properties
    
    @Bindable var store: PracticeStore
    
    /// Callback when navigating to practice (after playing a session)
    let onNavigateToCenter: () -> Void
    
    // MARK: - Queries
    
    @Query(sort: \SavedSession.sortOrder, order: .forward)
    private var savedSessions: [SavedSession]
    
    // MARK: - State: Selection
    
    /// Currently selected session ID (nil if none selected)
    @State private var selectedSessionId: UUID?
    
    // MARK: - State: Configuration
    
    /// Global mode selection
    @State private var selectedMode: SessionMode = .readThenSpeak
    
    /// Global loop count
    @State private var loopCount: Int = 1
    
    /// Global shuffle toggle
    @State private var shuffleEnabled: Bool = false
    
    /// Whether mode selector is expanded
    @State private var isModeSelectorExpanded: Bool = false
    
    // MARK: - State: Edit Mode
    
    /// ID of session currently being edited (nil if not editing)
    @State private var editingSessionId: UUID?
    
    /// Original title before edit (for revert on Cancel)
    @State private var originalTitleBeforeEdit: String = ""
    
    /// Current editing title (tracked for empty validation)
    @State private var currentEditingTitle: String = ""
    
    // MARK: - State: Sheets & Popups
    
    /// Session for info sheet
    @State private var sessionForInfo: SavedSession?
    
    /// Affirmations for info sheet
    @State private var infoSheetAffirmations: [Affirmation] = []
    
    /// Session pending deletion (shows confirmation popup)
    @State private var sessionToDelete: SavedSession?
    
    // MARK: - Constants
    
    /// Height reserved for the dock area at bottom (for safeAreaInset)
    private let dockAreaHeight: CGFloat = 110
    
    // MARK: - Computed Properties
    
    /// Whether any card is in edit mode
    private var isAnyCardEditing: Bool {
        editingSessionId != nil
    }
    
    /// Whether Play button should be enabled
    private var isPlayEnabled: Bool {
        selectedSessionId != nil && !isAnyCardEditing
    }
    
    /// Whether the empty state should show
    private var isEmpty: Bool {
        savedSessions.isEmpty
    }
    
    /// The currently selected session (if any)
    private var selectedSession: SavedSession? {
        guard let id = selectedSessionId else { return nil }
        return savedSessions.first { $0.id == id }
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()
            
            // Content
            if isEmpty {
                emptyState
            } else {
                sessionsList
            }
            
            // Fixed dock at bottom
            // AdaptiveDockContainer handles:
            // - Dismiss overlay for menus
            // - Menu expansion (Mode selector)
            // - Gradient fade
            // - Dock positioning
            AdaptiveDockContainer.savedSessions(
                isModeSelectorExpanded: $isModeSelectorExpanded,
                selectedMode: $selectedMode
            ) {
                AdaptiveBottomDock(
                    selectedMode: $selectedMode,
                    loopCount: $loopCount,
                    shuffleEnabled: $shuffleEnabled,
                    isModeSelectorExpanded: $isModeSelectorExpanded,
                    isPlayEnabled: isPlayEnabled,
                    isDisabled: isEmpty,
                    onPlay: {
                        playSelectedSession()
                    }
                )
            }
        }
        .navigationTitle("Saved Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Left: Close or Cancel
            ToolbarItem(placement: .cancellationAction) {
                if isAnyCardEditing {
                    Button("Cancel") {
                        cancelEditing()
                    }
                    .foregroundStyle(AppColors.accent)
                } else {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.accent)
                }
            }
            
            // Right: Done (only in edit mode)
            ToolbarItem(placement: .confirmationAction) {
                if isAnyCardEditing {
                    Button("Done") {
                        saveAndExitEditing()
                    }
                    .foregroundStyle(AppColors.accent)
                }
            }
        }
        .sheet(item: $sessionForInfo) { session in
            SavedSessionInfoSheetSimplified(
                session: session,
                affirmations: infoSheetAffirmations
            )
            .presentationDetents([.large])
        }
        .overlay {
            // Delete confirmation popup
            if let session = sessionToDelete {
                DeleteConfirmationPopup(
                    title: "Delete Session",
                    itemName: session.name,
                    onConfirm: {
                        deleteSession(session)
                        sessionToDelete = nil
                        editingSessionId = nil
                    },
                    onCancel: {
                        sessionToDelete = nil
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(AppTheme.Animation.standard, value: isAnyCardEditing)
        .animation(AppTheme.Animation.standard, value: sessionToDelete != nil)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Spacer()
            
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textTertiary)
            
            Text("No Saved Sessions")
                .font(AppTypography.title3)
                .foregroundStyle(AppColors.textPrimary)
            
            Text("Complete a session and save it to see it here")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.xl)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: dockAreaHeight)
        }
    }
    
    // MARK: - Sessions List
    
    private var sessionsList: some View {
        ScrollView {
            LazyVStack(spacing: AppTheme.Spacing.md) {
                ForEach(savedSessions) { session in
                    SavedSessionCard(
                        session: session,
                        isSelected: selectedSessionId == session.id,
                        isEditing: editingSessionId == session.id,
                        isAnyCardEditing: isAnyCardEditing,
                        onTap: {
                            handleCardTap(session)
                        },
                        onEdit: {
                            toggleEditing(session)
                        },
                        onInfo: {
                            showInfo(for: session)
                        },
                        onDelete: {
                            sessionToDelete = session
                        },
                        onTitleChanged: { newTitle in
                            currentEditingTitle = newTitle
                        },
                        onTitleCommit: {
                            saveAndExitEditing()
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
    
    // MARK: - Selection Handling
    
    private func handleCardTap(_ session: SavedSession) {
        // Cannot select while editing
        guard !isAnyCardEditing else { return }
        
        if selectedSessionId == session.id {
            // Deselect
            selectedSessionId = nil
        } else {
            // Select
            selectedSessionId = session.id
        }
        HapticFeedback.selection()
    }
    
    // MARK: - Edit Mode Handling
    
    /// Toggles edit mode for a session.
    /// If already editing this session, saves and exits.
    /// If not editing, starts editing this session.
    private func toggleEditing(_ session: SavedSession) {
        if editingSessionId == session.id {
            // Already editing this session - save and exit
            saveAndExitEditing()
        } else {
            // Not editing this session - start editing
            startEditing(session)
        }
    }
    
    private func startEditing(_ session: SavedSession) {
        // Store original title for cancel/revert
        originalTitleBeforeEdit = session.name
        currentEditingTitle = session.name
        editingSessionId = session.id
        HapticFeedback.selection()
    }
    
    private func cancelEditing() {
        // Revert title (don't save changes)
        editingSessionId = nil
        originalTitleBeforeEdit = ""
        currentEditingTitle = ""
    }
    
    /// Saves the current edit and exits edit mode.
    /// Called when Done button is tapped OR when Return key is pressed.
    private func saveAndExitEditing() {
        guard let sessionId = editingSessionId else { return }
        guard let session = savedSessions.first(where: { $0.id == sessionId }) else { return }
        
        // Validate title
        let trimmed = currentEditingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            // Revert to original if empty - don't save
            #if DEBUG
            print("[OK] SavedSessionsFullListView: Empty title, reverting to original")
            #endif
        } else if trimmed != originalTitleBeforeEdit {
            // Save the new title
            renameSession(session, to: trimmed)
        }
        
        // Exit edit mode
        editingSessionId = nil
        originalTitleBeforeEdit = ""
        currentEditingTitle = ""
    }
    
    // MARK: - Actions
    
    private func showInfo(for session: SavedSession) {
        // Selection persists when viewing info
        infoSheetAffirmations = session.affirmations
        sessionForInfo = session
        
        #if DEBUG
        print("[OK] SavedSessionsFullListView: Showing info for '\(session.name)' with \(session.affirmations.count) affirmations")
        #endif
    }
    
    private func playSelectedSession() {
        guard let session = selectedSession else { return }
        
        // Set loop configuration
        let config = LoopConfiguration(
            loopCount: loopCount,
            isShuffleEnabled: shuffleEnabled,
            currentLoopIteration: 1
        )
        store.setLoopConfiguration(config)
        
        // Update session's default mode to selected mode
        session.setDefaultMode(selectedMode)
        
        // Start the saved session
        store.send(.startSavedSession(session))
        
        // Dismiss this view
        dismiss()
        
        // Navigate to practice page
        onNavigateToCenter()
    }
    
    private func renameSession(_ session: SavedSession, to newName: String) {
        let repo = dependencies.makeSavedSessionRepository(modelContext: modelContext)
        do {
            session.name = newName
            try repo.update(session)
            HapticFeedback.notification(.success)
            
            #if DEBUG
            print("[OK] SavedSessionsFullListView: Renamed session to '\(newName)'")
            #endif
        } catch {
            #if DEBUG
            print("[ERROR] SavedSessionsFullListView: Failed to rename session: \(error)")
            #endif
        }
    }
    
    private func deleteSession(_ session: SavedSession) {
        let repo = dependencies.makeSavedSessionRepository(modelContext: modelContext)
        
        // Clear selection if deleting selected session
        if selectedSessionId == session.id {
            selectedSessionId = nil
        }
        
        do {
            try repo.delete(session)
            HapticFeedback.notification(.success)
            
            #if DEBUG
            print("[OK] SavedSessionsFullListView: Deleted session '\(session.name)'")
            #endif
        } catch {
            #if DEBUG
            print("[ERROR] SavedSessionsFullListView: Failed to delete session: \(error)")
            #endif
        }
    }
}

// MARK: - SavedSessionInfoSheetSimplified

/// Simplified info sheet showing the affirmation list in styled cards.
///
/// Uses `AffirmationListCard` with `.savedSessionInfo` context for consistent
/// card styling across the app. Dismiss via X or swipe.
struct SavedSessionInfoSheetSimplified: View {
    
    // MARK: - Environment
    
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Properties
    
    let session: SavedSession
    let affirmations: [Affirmation]
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    LazyVStack(spacing: AppTheme.Spacing.md) {
                        ForEach(affirmations) { affirmation in
                            AffirmationListCard(
                                text: affirmation.text,
                                category: affirmation.goalCategory,
                                context: .savedSessionInfo,
                                isFavorited: affirmation.isFavorited,
                                onToggleFavorite: { }
                            )
                        }
                    }
                    .padding(AppTheme.Spacing.lg)
                }
            }
            .navigationTitle(session.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Saved Sessions Full List") {
    NavigationStack {
        SavedSessionsFullListView(
            store: .preview,
            onNavigateToCenter: {}
        )
    }
    .previewEnvironment()
}
