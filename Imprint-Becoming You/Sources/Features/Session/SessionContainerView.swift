//
//  SessionContainerView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/21/25.
//

import SwiftUI
import SwiftData

// MARK: - SessionContainerView

/// Main container view for the affirmation practice session.
///
/// Coordinates:
/// - Vertical paging through affirmation cards
/// - Session controls (mode, binaural)
/// - Speech analysis integration
/// - Inactivity timeout handling
///
/// ## Usage
/// ```swift
/// SessionContainerView()
///     .environment(\.dependencies, container)
/// ```
struct SessionContainerView: View {
    
    // MARK: - Environment
    
    @Environment(\.appState) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dependencies) private var dependencies
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - State
    
    @State private var viewModel = SessionViewModel()
    @State private var showBinauralSelector = false
    @State private var dragOffset: CGFloat = 0
    @State private var isInitialized = false
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                AppColors.backgroundPrimary
                    .ignoresSafeArea()
                
                if isInitialized && !viewModel.affirmations.isEmpty {
                    // Main session content
                    VStack(spacing: 0) {
                        // Top bar (close button only)
                        SessionTopBar(
                            onClose: { handleClose() }
                        )
                        
                        // Affirmation card with vertical paging
                        affirmationPager(geometry: geometry)
                        
                        // Bottom controls
                        SessionControlsView(
                            viewModel: viewModel,
                            showBinauralSelector: $showBinauralSelector,
                            onBinauralChange: { preset in
                                await viewModel.changeBinauralPreset(
                                    preset,
                                    audioService: dependencies.audioService
                                )
                            }
                        )
                    }
                    
                    // Expanded menus as overlays (float above everything)
                    expandedMenusOverlay(geometry: geometry)
                    
                    // Inactivity popup overlay
                    if viewModel.showInactivityPopup {
                        inactivityOverlay
                    }
                } else {
                    // Loading state
                    loadingView
                }
            }
        }
        .task {
            await initializeSession()
        }
        .alert(
            "Error",
            isPresented: $viewModel.showError,
            presenting: viewModel.errorMessage
        ) { _ in
            Button("OK") { viewModel.dismissError() }
        } message: { message in
            Text(message)
        }
        .onDisappear {
            Task {
                await viewModel.endSession(audioService: dependencies.audioService)
            }
        }
    }
    
    // MARK: - Expanded Menus Overlay
    
    @ViewBuilder
    private func expandedMenusOverlay(geometry: GeometryProxy) -> some View {
        // Dim background when menu is open
        if viewModel.showModeSelector || showBinauralSelector {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(AppTheme.Animation.standard) {
                        viewModel.showModeSelector = false
                        showBinauralSelector = false
                    }
                }
        }
        
        // Mode selector
        if viewModel.showModeSelector {
            VStack {
                Spacer()
                
                ModeSelectorExpanded(
                    selectedMode: viewModel.sessionMode,
                    onSelect: { mode in
                        viewModel.changeMode(mode)
                        withAnimation(AppTheme.Animation.standard) {
                            viewModel.showModeSelector = false
                        }
                    }
                )
                .padding(.bottom, 76) // Bottom bar (~56) + spacing (20)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        
        // Binaural selector
        if showBinauralSelector {
            VStack {
                Spacer()
                
                BinauralSelectorExpanded(
                    selectedPreset: viewModel.binauralPreset,
                    onSelect: { preset in
                        Task {
                            await viewModel.changeBinauralPreset(
                                preset,
                                audioService: dependencies.audioService
                            )
                        }
                        withAnimation(AppTheme.Animation.standard) {
                            showBinauralSelector = false
                        }
                    }
                )
                .padding(.bottom, 76) // Bottom bar (~56) + spacing (20)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    // MARK: - Affirmation Pager
    
    @ViewBuilder
    private func affirmationPager(geometry: GeometryProxy) -> some View {
        let cardHeight = geometry.size.height - 120 // Account for top and bottom bars
        
        ZStack {
            // Current card
            if let affirmation = viewModel.currentAffirmation {
                AffirmationCardView(
                    affirmation: affirmation,
                    phase: viewModel.affirmationPhase,
                    realtimeScore: viewModel.realtimeScore,
                    resonanceRecord: viewModel.lastResonanceRecord,
                    isSpeaking: viewModel.isSpeaking,
                    isListening: viewModel.isListening,
                    recognizedText: viewModel.recognizedText
                )
                .frame(height: cardHeight)
                .offset(y: dragOffset)
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    handleDragChange(value, cardHeight: cardHeight)
                }
                .onEnded { value in
                    handleDragEnd(value, cardHeight: cardHeight)
                }
        )
        .simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    viewModel.recordInteraction()
                }
        )
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            ProgressView()
                .tint(AppColors.accent)
                .scaleEffect(1.5)
            
            Text("Preparing your session...")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
        }
    }
    
    // MARK: - Inactivity Overlay
    
    private var inactivityOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.dismissInactivityPopup()
                }
            
            InactivityPopup(
                countdown: viewModel.inactivityCountdown,
                onContinue: {
                    viewModel.dismissInactivityPopup()
                },
                onEnd: {
                    handleClose()
                }
            )
            .transition(.scale.combined(with: .opacity))
        }
        .animation(AppTheme.Animation.standard, value: viewModel.showInactivityPopup)
    }
    
    // MARK: - Gesture Handling
    
    private func handleDragChange(_ value: DragGesture.Value, cardHeight: CGFloat) {
        // Only allow swipe in read-only mode or when showing score
        guard viewModel.sessionMode == .readOnly ||
              viewModel.affirmationPhase == .showingScore else {
            return
        }
        
        // Don't allow swipe when menus are open
        guard !viewModel.showModeSelector && !showBinauralSelector else {
            return
        }
        
        let translation = value.translation.height
        
        // Apply resistance at edges
        if (translation < 0 && !viewModel.canGoNext) ||
           (translation > 0 && !viewModel.canGoPrevious) {
            dragOffset = translation * 0.3
        } else {
            dragOffset = translation
        }
    }
    
    private func handleDragEnd(_ value: DragGesture.Value, cardHeight: CGFloat) {
        let threshold = cardHeight * 0.2
        let translation = value.translation.height
        let velocity = value.predictedEndTranslation.height
        
        withAnimation(AppTheme.Animation.standard) {
            if translation < -threshold || velocity < -500 {
                // Swipe up - next
                if viewModel.canGoNext {
                    Task {
                        await viewModel.nextAffirmation()
                    }
                }
            } else if translation > threshold || velocity > 500 {
                // Swipe down - previous
                if viewModel.canGoPrevious {
                    Task {
                        await viewModel.previousAffirmation()
                    }
                }
            }
            
            dragOffset = 0
        }
    }
    
    // MARK: - Actions
    
    private func initializeSession() async {
        // Fetch affirmations
        let affirmations = await loadAffirmations()
        
        guard !affirmations.isEmpty else {
            // No affirmations - show error or generate
            viewModel.errorMessage = "No affirmations available. Please complete onboarding."
            viewModel.showError = true
            return
        }
        
        // Get user preferences
        let profile = appState.userProfile
        let mode = profile?.preferredMode ?? .readOnly
        let binaural = profile?.binauralPreset ?? .off
        let calibration = profile?.calibrationData
        
        // Start session
        await viewModel.startSession(
            affirmations: affirmations,
            mode: mode,
            binauralPreset: binaural,
            calibrationData: calibration,
            audioService: dependencies.audioService
        )
        
        isInitialized = true
    }
    
    private func loadAffirmations() async -> [Affirmation] {
        do {
            // Use stored property in predicate (computed properties crash SwiftData)
            let now = Date()
            let descriptor = FetchDescriptor<Affirmation>(
                predicate: #Predicate { $0.expiresAt > now },
                sortBy: [
                    SortDescriptor(\.batchIndex)
                ]
            )
            
            var affirmations = try modelContext.fetch(descriptor)
            
            // Sort in memory: unseen first, then by batch index
            // (Bool is not Comparable, so we can't use SortDescriptor for it)
            affirmations.sort { a, b in
                if a.hasBeenSeen != b.hasBeenSeen {
                    return !a.hasBeenSeen // unseen (false) comes first
                }
                return a.batchIndex < b.batchIndex
            }
            
            // Return up to batch size
            return Array(affirmations.prefix(Constants.Session.batchSize))
        } catch {
            print("Failed to load affirmations: \(error)")
            return Affirmation.samples // Fallback to samples
        }
    }
    
    private func handleClose() {
        Task {
            await viewModel.endSession(audioService: dependencies.audioService)
        }
        dismiss()
    }
}

// MARK: - Previews

#Preview("Session Container") {
    SessionContainerView()
        .previewEnvironment()
}
