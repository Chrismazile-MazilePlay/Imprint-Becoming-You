//
//  PracticePageView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import SwiftUI
import SwiftData

// MARK: - PracticePageView

/// The center page containing the affirmation practice experience.
///
/// This is the main interaction surface of the app, containing:
/// - Affirmation card (center)
/// - Floating HUD (top buttons, action buttons)
/// - Adaptive bottom dock (mode controls, progress)
///
/// ## Gestures
/// - **Vertical swipe**: Navigate between affirmations
/// - **Tap card**: Close selectors or record interaction
/// - **Horizontal swipe**: Handled by parent TabView (page navigation)
///
/// ## Layers (bottom to top)
/// 1. Affirmation card with drag gesture
/// 2. Floating HUD overlay
/// 3. Bottom dock with selectors
struct PracticePageView: View {
    
    // MARK: - Properties
    
    @Bindable var viewModel: PracticeViewModel
    
    /// Callback to navigate to profile page
    let onNavigateToProfile: () -> Void
    
    /// Callback to navigate to prompts page
    let onNavigateToPrompts: () -> Void
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dependencies) private var dependencies
    
    // MARK: - State
    
    @State private var dragOffset: CGFloat = 0
    @State private var showCategories = false
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Affirmation card layer (with tap gesture to close selectors)
                affirmationLayer(geometry: geometry)
                
                // Floating HUD (top buttons + action buttons)
                FloatingHUDLayer(
                    viewModel: viewModel,
                    onProfileTap: onNavigateToProfile,
                    onPromptsTap: onNavigateToPrompts,
                    onCategoriesTap: { showCategories = true }
                )
                
                // Bottom dock (selectors expand from here)
                VStack {
                    Spacer()
                    
                    AdaptiveBottomDock(
                        viewModel: viewModel,
                        onBinauralChange: { preset in
                            await viewModel.changeBinauralPreset(
                                preset,
                                audioService: dependencies.audioService
                            )
                        },
                        onModeChange: { mode in
                            await viewModel.changeMode(
                                mode,
                                audioService: dependencies.audioService
                            )
                        }
                    )
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.bottom, AppTheme.Spacing.md)
                }
                
                // NOTE: No dimming overlay - tapping affirmation area closes selectors
            }
        }
        .fullScreenCover(isPresented: $showCategories) {
            CategoriesFullScreenView(viewModel: viewModel)
        }
    }
    
    // MARK: - Affirmation Layer
    
    @ViewBuilder
    private func affirmationLayer(geometry: GeometryProxy) -> some View {
        ZStack {
            if let affirmation = viewModel.currentAffirmation {
                AffirmationCardView(
                    affirmation: affirmation,
                    phase: currentPhase,
                    realtimeScore: Float(viewModel.realtimeScore),
                    resonanceRecord: viewModel.lastResonanceRecord,
                    isSpeaking: viewModel.isTTSPlaying,
                    isListening: viewModel.isListening,
                    recognizedText: viewModel.recognizedText
                )
                .offset(y: dragOffset)
            }
        }
        .gesture(verticalSwipeGesture(geometry: geometry))
        .simultaneousGesture(tapGesture)
    }
    
    // MARK: - Vertical Swipe Gesture
    
    private func verticalSwipeGesture(geometry: GeometryProxy) -> some Gesture {
        DragGesture()
            .onChanged { value in
                handleDragChange(value, geometry: geometry)
            }
            .onEnded { value in
                handleDragEnd(value, geometry: geometry)
            }
    }
    
    private func handleDragChange(_ value: DragGesture.Value, geometry: GeometryProxy) {
        // Don't allow swiping when selectors are expanded
        guard !viewModel.dockManager.isModeSelectorExpanded else { return }
        guard !viewModel.dockManager.isBinauralSelectorExpanded else { return }
        
        // During active session, only allow swipe in certain phases
        if viewModel.isSessionActive {
            guard canSwipeInCurrentPhase else { return }
        }
        
        let translation = value.translation.height
        
        // Apply resistance at boundaries
        if (translation < 0 && !viewModel.canGoNext) ||
           (translation > 0 && !viewModel.canGoPrevious) {
            dragOffset = translation * 0.3
        } else {
            dragOffset = translation
        }
    }
    
    private func handleDragEnd(_ value: DragGesture.Value, geometry: GeometryProxy) {
        let threshold = geometry.size.height * 0.15
        let translation = value.translation.height
        let velocity = value.predictedEndTranslation.height
        
        withAnimation(AppTheme.Animation.standard) {
            // Swipe up = next, swipe down = previous
            if translation < -threshold || velocity < -500 {
                if viewModel.canGoNext {
                    viewModel.nextAffirmation()
                }
            } else if translation > threshold || velocity > 500 {
                if viewModel.canGoPrevious {
                    viewModel.previousAffirmation()
                }
            }
            
            dragOffset = 0
        }
    }
    
    // MARK: - Tap Gesture
    
    private var tapGesture: some Gesture {
        TapGesture()
            .onEnded { _ in
                if viewModel.dockManager.isModeSelectorExpanded ||
                   viewModel.dockManager.isBinauralSelectorExpanded {
                    viewModel.dockManager.closeSelectors()
                } else {
                    viewModel.recordInteraction()
                }
            }
    }
    
    // MARK: - Phase Mapping
    
    /// Maps dock state to affirmation card phase
    private var currentPhase: AffirmationPhase {
        switch viewModel.dockManager.state {
        case .home:
            return .displaying
            
        case .readAloud(let phase):
            switch phase {
            case .idle: return .displaying
            case .speaking: return .playing
            case .complete: return .displaying
            }
            
        case .readAndSpeak(let phase):
            switch phase {
            case .idle: return .displaying
            case .ttsPlaying: return .playing
            case .waitingForUser: return .waitingToSpeak
            case .listening: return .listening
            case .analyzing: return .analyzing
            case .showingScore: return .showingScore
            }
            
        case .speakOnly(let phase):
            switch phase {
            case .idle: return .displaying
            case .listening: return .listening
            case .analyzing: return .analyzing
            case .showingScore: return .showingScore
            }
        }
    }
    
    /// Whether vertical swipe is allowed in the current phase
    private var canSwipeInCurrentPhase: Bool {
        switch viewModel.dockManager.state {
        case .home:
            return true
            
        case .readAloud(let phase):
            return phase == .idle || phase == .complete
            
        case .readAndSpeak(let phase):
            if case .showingScore = phase { return true }
            return phase == .idle
            
        case .speakOnly(let phase):
            if case .showingScore = phase { return true }
            return phase == .idle
        }
    }
}

// MARK: - Previews

#Preview("Practice Page") {
    PracticePageView(
        viewModel: {
            let vm = PracticeViewModel()
            vm.affirmations = Affirmation.samples
            return vm
        }(),
        onNavigateToProfile: {},
        onNavigateToPrompts: {}
    )
    .previewEnvironment()
}

#Preview("Practice Page - Read Aloud") {
    PracticePageView(
        viewModel: {
            let vm = PracticeViewModel()
            vm.affirmations = Affirmation.samples
            vm.dockManager.setMode(.readAloud)
            vm.dockManager.updateReadAloudPhase(.speaking)
            return vm
        }(),
        onNavigateToProfile: {},
        onNavigateToPrompts: {}
    )
    .previewEnvironment()
}

#Preview("Practice Page - Listening") {
    PracticePageView(
        viewModel: {
            let vm = PracticeViewModel()
            vm.affirmations = Affirmation.samples
            vm.dockManager.setMode(.speakOnly)
            vm.dockManager.updateSpeakOnlyPhase(.listening)
            return vm
        }(),
        onNavigateToProfile: {},
        onNavigateToPrompts: {}
    )
    .previewEnvironment()
}
