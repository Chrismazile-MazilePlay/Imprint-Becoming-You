//
//  MainPracticeView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/21/25.
//

import SwiftUI
import SwiftData

// MARK: - AppPage

/// Represents the three main pages of the app.
///
/// Page order supports natural navigation flow:
/// - Prompts (left) - AI features, no further navigation
/// - Practice (center) - Main experience
/// - Profile (right) - Settings, account, nested navigation flows right
enum AppPage: Int, CaseIterable {
    case prompts = 0   // Left
    case practice = 1  // Center (default)
    case profile = 2   // Right
}

// MARK: - MainPracticeView

/// The root view for the entire app experience.
///
/// A horizontal pager with three pages:
/// - **Left (Page 0)**: Prompts - AI prompt management
/// - **Center (Page 1)**: Practice - Affirmations with adaptive dock
/// - **Right (Page 2)**: Profile - Stats, progress, favorites, settings
///
/// Navigation:
/// - AI button (top-left) → slides to Prompts page (left)
/// - Profile button (top-right) → slides to Profile page (right)
/// - Categories button → full-screen cover (no slide)
/// - Swipe left → Prompts
/// - Swipe right → Profile
struct MainPracticeView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dependencies) private var dependencies
    
    // MARK: - State
    
    @State private var viewModel = PracticeViewModel()
    @State private var currentPage: AppPage = .practice
    @State private var isInitialized = false
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Background
            AppColors.backgroundPrimary
                .ignoresSafeArea()
            
            if isInitialized {
                // Horizontal page navigation
                TabView(selection: $currentPage) {
                    // Page 0: Prompts (Left)
                    PromptsPageView(
                        onNavigateToCenter: { navigateToPage(.practice) }
                    )
                    .tag(AppPage.prompts)
                    
                    // Page 1: Practice (Center - Main)
                    PracticePageView(
                        viewModel: viewModel,
                        onNavigateToProfile: { navigateToPage(.profile) },
                        onNavigateToPrompts: { navigateToPage(.prompts) }
                    )
                    .tag(AppPage.practice)
                    
                    // Page 2: Profile (Right)
                    ProfilePageView(
                        viewModel: viewModel,
                        onNavigateToCenter: { navigateToPage(.practice) }
                    )
                    .tag(AppPage.profile)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
            } else {
                // Loading state
                loadingView
            }
        }
        .task {
            await initializePractice()
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
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            ProgressView()
                .tint(AppColors.accent)
                .scaleEffect(1.5)
            
            Text("Preparing your practice...")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
        }
    }
    
    // MARK: - Navigation
    
    private func navigateToPage(_ page: AppPage) {
        withAnimation(AppTheme.Animation.standard) {
            currentPage = page
        }
    }
    
    // MARK: - Initialization
    
    private func initializePractice() async {
        await viewModel.loadAffirmations(from: modelContext)
        isInitialized = true
    }
}

// MARK: - PracticePageView

/// The center page containing the affirmation practice experience.
struct PracticePageView: View {
    
    // MARK: - Properties
    
    @Bindable var viewModel: PracticeViewModel
    let onNavigateToProfile: () -> Void
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
        guard !viewModel.dockManager.isModeSelectorExpanded else { return }
        guard !viewModel.dockManager.isBinauralSelectorExpanded else { return }
        
        if viewModel.isSessionActive {
            guard canSwipeInCurrentPhase else { return }
        }
        
        let translation = value.translation.height
        
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
    
    // MARK: - Helpers
    
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

// MARK: - PromptsPageView

/// Placeholder for the AI Prompts page.
struct PromptsPageView: View {
    
    let onNavigateToCenter: () -> Void
    
    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()
            
            VStack(spacing: AppTheme.Spacing.xl) {
                // Back button (navigate right to center)
                HStack {
                    Spacer()
                    
                    Button {
                        onNavigateToCenter()
                    } label: {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            Text("Practice")
                                .font(AppTypography.body)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(AppColors.accent)
                    }
                    .padding(.trailing, AppTheme.Spacing.lg)
                    .padding(.top, AppTheme.Spacing.xl)
                }
                
                Spacer()
                
                // Placeholder content
                VStack(spacing: AppTheme.Spacing.lg) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 60))
                        .foregroundStyle(AppColors.accent.opacity(0.6))
                    
                    Text("AI Prompts")
                        .font(AppTypography.title1)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text("Create custom prompts to generate\npersonalized affirmations.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                    
                    Text("Coming Soon")
                        .font(AppTypography.caption1.weight(.medium))
                        .foregroundStyle(AppColors.accent)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.vertical, AppTheme.Spacing.sm)
                        .background(AppColors.accent.opacity(0.15))
                        .clipShape(Capsule())
                        .padding(.top, AppTheme.Spacing.md)
                }
                
                Spacer()
                Spacer()
            }
        }
    }
}

// MARK: - Previews

#Preview("Main Practice View") {
    MainPracticeView()
        .previewEnvironment()
}

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

#Preview("Prompts Page") {
    PromptsPageView(onNavigateToCenter: {})
}
