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
/// ## Navigation
/// This view is pushed onto the Profile navigation stack.
/// When starting a session, it pops back to Profile root
/// then triggers navigation to Practice page.
struct SavedSessionsFullListView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dependencies) private var dependencies
    
    // MARK: - Properties
    
    @Bindable var store: PracticeStore
    
    /// Called when user starts a session - should pop to root and navigate to Practice
    let onStartSession: () -> Void
    
    // MARK: - Queries
    
    @Query(sort: \SavedSession.sortOrder, order: .forward)
    private var savedSessions: [SavedSession]
    
    // MARK: - State
    
    @State private var selectedSessionId: UUID?
    @State private var dockAdapter: ConfigurationDockAdapter
    @State private var editingSessionId: UUID?
    @State private var originalTitleBeforeEdit: String = ""
    @State private var currentEditingTitle: String = ""
    @State private var sessionToDelete: SavedSession?
    
    /// Session info destination for navigation
    @State private var sessionInfoDestination: SessionInfoDestination?
    
    // MARK: - Constants
    
    private let dockAreaHeight: CGFloat = 120
    
    // MARK: - Computed Properties
    
    private var isAnyCardEditing: Bool {
        editingSessionId != nil
    }
    
    private var isPlayEnabled: Bool {
        selectedSessionId != nil && !isAnyCardEditing
    }
    
    private var isEmpty: Bool {
        savedSessions.isEmpty
    }
    
    private var selectedSession: SavedSession? {
        guard let id = selectedSessionId else { return nil }
        return savedSessions.first { $0.id == id }
    }
    
    // MARK: - Initialization
    
    init(
        store: PracticeStore,
        onStartSession: @escaping () -> Void
    ) {
        self.store = store
        self.onStartSession = onStartSession
        
        self._dockAdapter = State(initialValue: ConfigurationDockAdapter(
            labelText: "",
            isPlayEnabled: false,
            onPlay: { _, _, _ in }
        ))
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()
            
            if isEmpty {
                emptyState
            } else {
                sessionsList
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
        .navigationTitle("Saved Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isAnyCardEditing {
                    Button("Done") {
                        saveAndExitEditing()
                    }
                    .foregroundStyle(AppColors.accent)
                    .accessibilityLabel("Done editing")
                    .accessibilityHint("Save changes to session name")
                }
            }
        }
        .navigationDestination(item: $sessionInfoDestination) { destination in
            SavedSessionInfoView(
                sessionName: destination.sessionName,
                affirmationIds: destination.affirmationIds
            )
        }
        .overlay {
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
        .onChange(of: selectedSessionId) { _, _ in
            updateDockAdapter()
        }
        .onAppear {
            updateDockAdapter()
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Spacer()
            
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textTertiary)
                .accessibilityHidden(true)
            
            Text("No Saved Sessions")
                .font(AppTypography.title3)
                .foregroundStyle(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            
            Text("Complete a practice session and save it to create your own custom sessions.")
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
        .accessibilityLabel("No saved sessions. Complete a practice session and save it to create your own custom sessions.")
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
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(session.name). \(session.affirmationIds.count) affirmations. \(selectedSessionId == session.id ? "Selected" : "")")
                    .accessibilityHint(selectedSessionId == session.id ? "Double tap to deselect. Swipe left for more options." : "Double tap to select for playback. Swipe left for more options.")
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Dismiss any open swipe actions when tapping outside cards
            SwipeActionSharedState.shared.dismissAll()
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: dockAreaHeight)
        }
        .accessibilityLabel("Saved sessions list, \(savedSessions.count) items")
    }
    
    // MARK: - Dock Adapter
    
    private func updateDockAdapter() {
        dockAdapter = ConfigurationDockAdapter(
            initialMode: dockAdapter.currentMode,
            initialLoopCount: dockAdapter.loopCount,
            initialShuffle: dockAdapter.isShuffleEnabled,
            labelText: "",
            isPlayEnabled: isPlayEnabled,
            onPlay: { [self] mode, loopCount, shuffle in
                playSelectedSession(mode: mode, loopCount: loopCount, shuffle: shuffle)
            }
        )
    }
    
    // MARK: - Selection
    
    private func handleCardTap(_ session: SavedSession) {
        guard !isAnyCardEditing else { return }
        
        if selectedSessionId == session.id {
            selectedSessionId = nil
        } else {
            selectedSessionId = session.id
        }
        HapticFeedback.selection()
    }
    
    // MARK: - Edit Mode
    
    private func toggleEditing(_ session: SavedSession) {
        if editingSessionId == session.id {
            saveAndExitEditing()
        } else {
            startEditing(session)
        }
    }
    
    private func startEditing(_ session: SavedSession) {
        originalTitleBeforeEdit = session.name
        currentEditingTitle = session.name
        editingSessionId = session.id
        HapticFeedback.selection()
    }
    
    private func cancelEditing() {
        editingSessionId = nil
        originalTitleBeforeEdit = ""
        currentEditingTitle = ""
    }
    
    private func saveAndExitEditing() {
        guard let sessionId = editingSessionId else { return }
        guard let session = savedSessions.first(where: { $0.id == sessionId }) else { return }
        
        let trimmed = currentEditingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !trimmed.isEmpty && trimmed != originalTitleBeforeEdit {
            renameSession(session, to: trimmed)
        }
        
        editingSessionId = nil
        originalTitleBeforeEdit = ""
        currentEditingTitle = ""
    }
    
    // MARK: - Actions
    
    /// Shows session info by navigating to detail view.
    ///
    /// Uses `affirmationIds` (stored reliably) instead of the SwiftData
    /// relationship which may not be fully loaded due to lazy loading.
    private func showInfo(for session: SavedSession) {
        sessionInfoDestination = SessionInfoDestination(
            sessionName: session.name,
            affirmationIds: session.affirmationIds
        )
    }
    
    private func playSelectedSession(mode: SessionMode, loopCount: Int, shuffle: Bool) {
        guard let session = selectedSession else { return }
        
        let config = LoopConfiguration(
            loopCount: loopCount,
            isShuffleEnabled: shuffle,
            currentLoopIteration: 1
        )
        store.setLoopConfiguration(config)
        session.setDefaultMode(mode)
        store.send(.startSavedSession(session))
        
        // Pop to root and navigate to Practice
        onStartSession()
    }
    
    private func renameSession(_ session: SavedSession, to newName: String) {
        let repo = dependencies.makeSavedSessionRepository(modelContext: modelContext)
        do {
            session.name = newName
            try repo.update(session)
            HapticFeedback.notification(.success)
        } catch {
            #if DEBUG
            print("[ERROR] SavedSessionsFullListView: Failed to rename session: \(error)")
            #endif
        }
    }
    
    private func deleteSession(_ session: SavedSession) {
        let repo = dependencies.makeSavedSessionRepository(modelContext: modelContext)
        
        if selectedSessionId == session.id {
            selectedSessionId = nil
        }
        
        do {
            try repo.delete(session)
            HapticFeedback.notification(.success)
        } catch {
            #if DEBUG
            print("[ERROR] SavedSessionsFullListView: Failed to delete session: \(error)")
            #endif
        }
    }
}

// MARK: - SessionInfoDestination

/// Navigation destination data for session info view.
///
/// Uses `affirmationIds` rather than the SwiftData relationship
/// to ensure reliable data availability.
struct SessionInfoDestination: Hashable, Identifiable {
    let id = UUID()
    let sessionName: String
    let affirmationIds: [UUID]
}

// MARK: - SavedSessionInfoView

/// View displaying the affirmations in a saved session.
///
/// Fetches affirmations by ID from the database to ensure
/// consistent data availability (SwiftData relationships can
/// be unreliable due to lazy loading).
struct SavedSessionInfoView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - Properties
    
    let sessionName: String
    let affirmationIds: [UUID]
    
    // MARK: - State
    
    @State private var affirmations: [Affirmation] = []
    @State private var isLoading = true
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()
            
            if isLoading {
                ProgressView()
                    .tint(AppColors.accent)
            } else if affirmations.isEmpty {
                emptyState
            } else {
                affirmationsList
            }
        }
        .navigationTitle(sessionName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAffirmations()
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "doc.text")
                .font(.system(size: 40))
                .foregroundStyle(AppColors.textTertiary)
            
            Text("No affirmations found")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
        }
    }
    
    // MARK: - Affirmations List
    
    private var affirmationsList: some View {
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
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(affirmation.text). Category: \(affirmation.category)")
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .accessibilityLabel("Session affirmations, \(affirmations.count) items")
    }
    
    // MARK: - Data Loading
    
    /// Fetches affirmations by their IDs, preserving the original order.
    @MainActor
    private func loadAffirmations() async {
        defer { isLoading = false }
        
        guard !affirmationIds.isEmpty else { return }
        
        // Fetch all affirmations matching the IDs
        let descriptor = FetchDescriptor<Affirmation>(
            predicate: #Predicate<Affirmation> { affirmation in
                affirmationIds.contains(affirmation.id)
            }
        )
        
        do {
            let fetchedAffirmations = try modelContext.fetch(descriptor)
            
            // Reorder to match original affirmationIds order
            var orderedAffirmations: [Affirmation] = []
            for id in affirmationIds {
                if let affirmation = fetchedAffirmations.first(where: { $0.id == id }) {
                    orderedAffirmations.append(affirmation)
                }
            }
            
            affirmations = orderedAffirmations
        } catch {
            #if DEBUG
            print("[ERROR] SavedSessionInfoView: Failed to fetch affirmations: \(error)")
            #endif
        }
    }
}

// MARK: - Previews

#Preview("Saved Sessions Full List") {
    NavigationStack {
        SavedSessionsFullListView(
            store: .preview,
            onStartSession: {}
        )
    }
    .previewEnvironment()
}

#Preview("Session Info View") {
    NavigationStack {
        SavedSessionInfoView(
            sessionName: "Morning Confidence",
            affirmationIds: []
        )
    }
    .previewEnvironment()
}
