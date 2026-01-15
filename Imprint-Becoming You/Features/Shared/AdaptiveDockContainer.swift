//
//  AdaptiveDockContainer.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/14/26.
//

import SwiftUI

// MARK: - AdaptiveDockContainer

/// A unified container that handles ALL dock positioning AND menu expansion.
///
/// This container provides consistent dock/menu UX across all contexts:
/// - Practice mode (home and active session)
/// - Configuration mode (Results Summary, Favorites, Saved Sessions)
///
/// ## Architecture
/// The container uses ZStack layering:
/// 1. **Dismiss overlay** (zIndex 1) - Full-screen tap target to close menus
/// 2. **Menu panels** (zIndex 2) - Slide up from behind dock, positioned above dock
/// 3. **Dock content** (zIndex 3) - Always visible, grows upward from bottom
///
/// ## Two Modes
///
/// ### Practice Mode (`init(store:)`)
/// - Full PracticeStore integration
/// - Shows both Mode selector AND Binaural selector
/// - Dynamic dock height based on session state
/// - No gradient (practice page has its own background)
/// - No label
///
/// ### Configuration Mode (`init(isModeSelectorExpanded:selectedMode:...)`)
/// - Explicit bindings for state management
/// - Shows Mode selector ONLY (no Binaural)
/// - Optional gradient fade for scrollable content
/// - Optional label below dock
///
/// ## Menu Behavior
/// - Animation: `AppTheme.Animation.standard`
/// - Transition: `.move(edge: .bottom).combined(with: .opacity)`
/// - Menu positioned above dock with `AppTheme.Spacing.sm` gap
/// - Dismiss: Tap anywhere outside menu closes it
///
/// ## Layout
/// ```
/// ┌─────────────────────────────────────────────────────────────────┐
/// │                                                                 │
/// │                    [Content above dock]                         │
/// │                                                                 │
/// ├─────────────────────────────────────────────────────────────────┤
/// │  ░░░░░░░░ (optional gradient) ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │
/// │  ┌─────────────────────────────────────────────────────────┐   │
/// │  │  Menu (slides up, positioned ABOVE dock)                │   │
/// │  └─────────────────────────────────────────────────────────┘   │
/// │  [Mode ▼]       [🔁 3] [🔀]         [▶]   ← Dock (FRONT)      │
/// │                 "Label text"              ← Optional label     │
/// └─────────────────────────────────────────────────────────────────┘
/// ```
struct AdaptiveDockContainer<DockContent: View>: View {
    
    // MARK: - Container Mode
    
    private enum ContainerMode {
        case practice
        case configuration
    }
    
    private let containerMode: ContainerMode
    
    // MARK: - Practice Mode Properties
    
    private var store: PracticeStore?
    
    // MARK: - Configuration Mode Properties
    
    @Binding private var configIsModeSelectorExpanded: Bool
    @Binding private var configSelectedMode: SessionMode
    private let configOnModeSelected: ((SessionMode) -> Void)?
    private let configLabel: String
    private let configShowGradient: Bool
    
    // MARK: - Shared Properties
    
    /// The dock content to display
    @ViewBuilder private let dockContent: () -> DockContent
    
    // MARK: - Constants
    
    /// Height of the gradient fade zone
    private let gradientHeight: CGFloat = 48
    
    /// Base dock height for practice home mode.
    /// Accounts for the taller dock with both Mode and Binaural buttons.
    /// Tune this value to adjust menu-to-dock spacing in PracticePageView.
    private let practiceHomeDockHeight: CGFloat = 72
    
    /// Base dock height for configuration mode (Results Summary, Favorites, Saved Sessions).
    /// Accounts for the shorter dock with Mode button only (no Binaural).
    /// Tune this value to adjust menu-to-dock spacing in config sheets.
    private let configDockBaseHeight: CGFloat = 72
    
    /// Dock height for practice active mode (progress + waveform + buttons)
    private let practiceActiveDockHeight: CGFloat = 180
    
    /// Extra spacing between menu bottom and dock top
    private let menuDockSpacing: CGFloat = 12
    
    // MARK: - Practice Mode Initializer
    
    /// Creates a dock container for practice mode with full PracticeStore integration.
    ///
    /// In practice mode:
    /// - Both Mode and Binaural selectors are available
    /// - Dock height adapts to session state (home vs active)
    /// - No gradient (practice page has its own background)
    /// - No label below dock
    ///
    /// - Parameters:
    ///   - store: The PracticeStore managing session state
    ///   - dock: The dock content builder
    init(
        store: PracticeStore,
        @ViewBuilder dock: @escaping () -> DockContent
    ) {
        self.containerMode = .practice
        self.store = store
        self._configIsModeSelectorExpanded = .constant(false)
        self._configSelectedMode = .constant(.readThenSpeak)
        self.configOnModeSelected = nil
        self.configLabel = ""
        self.configShowGradient = false
        self.dockContent = dock
    }
    
    // MARK: - Configuration Mode Initializer
    
    /// Creates a dock container for configuration mode with explicit bindings.
    ///
    /// In configuration mode:
    /// - Only Mode selector is available (no Binaural)
    /// - Shows only playable modes (excludes Read Only)
    /// - Optional gradient and label
    ///
    /// - Parameters:
    ///   - isModeSelectorExpanded: Binding to mode selector expansion state
    ///   - selectedMode: Binding to the selected session mode
    ///   - onModeSelected: Callback when a mode is selected (optional, for side effects)
    ///   - label: Text to display below the dock (empty string = no label)
    ///   - showGradient: Whether to show the content fade gradient
    ///   - dock: The dock content builder
    init(
        isModeSelectorExpanded: Binding<Bool>,
        selectedMode: Binding<SessionMode>,
        onModeSelected: ((SessionMode) -> Void)? = nil,
        label: String = "",
        showGradient: Bool = true,
        @ViewBuilder dock: @escaping () -> DockContent
    ) {
        self.containerMode = .configuration
        self.store = nil
        self._configIsModeSelectorExpanded = isModeSelectorExpanded
        self._configSelectedMode = selectedMode
        self.configOnModeSelected = onModeSelected
        self.configLabel = label
        self.configShowGradient = showGradient
        self.dockContent = dock
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Layer 0: Dismiss overlay (full-screen tap target)
            dismissOverlay
                .zIndex(1)
            
            // Layer 1: Optional gradient (configuration mode only)
            if configShowGradient {
                gradientLayer
            }
            
            // Layer 2: Expanded menu panels (above dock)
            expandedMenus
                .zIndex(2)
            
            // Layer 3: Dock + optional label (always on top)
            dockLayer
                .zIndex(3)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .ignoresSafeArea(.keyboard)
    }
    
    // MARK: - Dismiss Overlay
    
    @ViewBuilder
    private var dismissOverlay: some View {
        if isAnyMenuExpanded {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    closeAllMenus()
                }
                .ignoresSafeArea()
        }
    }
    
    // MARK: - Gradient Layer
    
    private var gradientLayer: some View {
        VStack(spacing: 0) {
            Spacer()
            
            LinearGradient(
                stops: [
                    .init(color: AppColors.backgroundPrimary.opacity(0), location: 0),
                    .init(color: AppColors.backgroundPrimary.opacity(0.3), location: 0.4),
                    .init(color: AppColors.backgroundPrimary.opacity(0.7), location: 0.7),
                    .init(color: AppColors.backgroundPrimary.opacity(0.9), location: 0.85),
                    .init(color: AppColors.backgroundPrimary, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: gradientHeight)
            
            // Solid background extending behind dock area (includes bottom padding)
            AppColors.backgroundPrimary
                .frame(height: dockAreaHeight)
        }
    }
    
    // MARK: - Expanded Menus
    
    @ViewBuilder
    private var expandedMenus: some View {
        VStack(spacing: 0) {
            Spacer()
            
            switch containerMode {
            case .practice:
                practiceMenus
                
            case .configuration:
                configurationMenu
            }
            
            // Spacer to position menus above dock
            // This pushes the menu content up by the dock height + spacing
            Spacer()
                .frame(height: dockAreaHeight + menuDockSpacing)
        }
        .animation(AppTheme.Animation.standard, value: isAnyMenuExpanded)
    }
    
    // MARK: - Practice Mode Menus
    
    @ViewBuilder
    private var practiceMenus: some View {
        if let store = store {
            // Mode selector
            if store.isModeSelectorExpanded {
                ModeSelectorExpanded(
                    selectedMode: store.currentMode,
                    showOnlyPlayableModes: false,
                    onSelect: { mode in
                        store.send(.selectMode(mode))
                    }
                )
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Binaural selector
            if store.isBinauralSelectorExpanded {
                BinauralSelectorExpanded(
                    selectedPreset: store.binauralPreset,
                    onSelect: { preset in
                        store.send(.selectBinaural(preset))
                    }
                )
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Configuration Mode Menu
    
    @ViewBuilder
    private var configurationMenu: some View {
        if configIsModeSelectorExpanded {
            ModeSelectorExpanded(
                selectedMode: configSelectedMode,
                showOnlyPlayableModes: true,
                onSelect: { mode in
                    configSelectedMode = mode
                    configOnModeSelected?(mode)
                    withAnimation(AppTheme.Animation.standard) {
                        configIsModeSelectorExpanded = false
                    }
                    HapticFeedback.selection()
                }
            )
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.sm)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    // MARK: - Dock Layer
    
    private var dockLayer: some View {
        VStack(spacing: 0) {
            // Dock content
            dockContent()
                .padding(.horizontal, AppTheme.Spacing.lg)
            
            // Optional label (configuration mode only)
            if !configLabel.isEmpty {
                Text(configLabel)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.top, AppTheme.Spacing.sm)
            }
        }
        .padding(.bottom, AppTheme.Layout.dockBottomPadding)
    }
    
    // MARK: - Computed Properties
    
    /// Whether any menu is currently expanded
    private var isAnyMenuExpanded: Bool {
        switch containerMode {
        case .practice:
            guard let store = store else { return false }
            return store.isModeSelectorExpanded || store.isBinauralSelectorExpanded
            
        case .configuration:
            return configIsModeSelectorExpanded
        }
    }
    
    /// Dynamic height of the dock area (for positioning menus above and gradient behind).
    /// Uses mode-specific constants for accurate positioning.
    private var dockAreaHeight: CGFloat {
        switch containerMode {
        case .practice:
            guard let store = store else {
                return practiceHomeDockHeight + AppTheme.Layout.dockBottomPadding
            }
            let baseHeight = store.isSessionActive ? practiceActiveDockHeight : practiceHomeDockHeight
            return baseHeight + AppTheme.Layout.dockBottomPadding
            
        case .configuration:
            let labelHeight: CGFloat = configLabel.isEmpty ? 0 : 28
            return configDockBaseHeight + labelHeight + AppTheme.Layout.dockBottomPadding
        }
    }
    
    // MARK: - Actions
    
    /// Closes all expanded menus with animation
    private func closeAllMenus() {
        withAnimation(AppTheme.Animation.standard) {
            switch containerMode {
            case .practice:
                store?.send(.closeSelectors)
                
            case .configuration:
                configIsModeSelectorExpanded = false
            }
        }
    }
}

// MARK: - Convenience Extensions

extension AdaptiveDockContainer {
    
    /// Creates a container for Results Summary context.
    ///
    /// - Label: "Repeat Session"
    /// - Gradient: Yes
    /// - Binaural: No
    static func resultsSummary(
        isModeSelectorExpanded: Binding<Bool>,
        selectedMode: Binding<SessionMode>,
        @ViewBuilder dock: @escaping () -> DockContent
    ) -> AdaptiveDockContainer {
        AdaptiveDockContainer(
            isModeSelectorExpanded: isModeSelectorExpanded,
            selectedMode: selectedMode,
            label: "Repeat Session",
            showGradient: true,
            dock: dock
        )
    }
    
    /// Creates a container for Favorites context.
    ///
    /// - Label: "Practice X affirmations"
    /// - Gradient: Yes
    /// - Binaural: No
    static func favorites(
        count: Int,
        isModeSelectorExpanded: Binding<Bool>,
        selectedMode: Binding<SessionMode>,
        @ViewBuilder dock: @escaping () -> DockContent
    ) -> AdaptiveDockContainer {
        AdaptiveDockContainer(
            isModeSelectorExpanded: isModeSelectorExpanded,
            selectedMode: selectedMode,
            label: "Practice \(count) affirmation\(count == 1 ? "" : "s")",
            showGradient: true,
            dock: dock
        )
    }
    
    /// Creates a container for Saved Sessions context.
    ///
    /// - Label: None
    /// - Gradient: Yes
    /// - Binaural: No
    static func savedSessions(
        isModeSelectorExpanded: Binding<Bool>,
        selectedMode: Binding<SessionMode>,
        @ViewBuilder dock: @escaping () -> DockContent
    ) -> AdaptiveDockContainer {
        AdaptiveDockContainer(
            isModeSelectorExpanded: isModeSelectorExpanded,
            selectedMode: selectedMode,
            label: "",
            showGradient: true,
            dock: dock
        )
    }
}

// MARK: - Previews

#Preview("Practice Mode - Home") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        
        AdaptiveDockContainer(store: .preview) {
            // Simulated dock
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.extraLarge)
                .fill(AppColors.backgroundSecondary)
                .frame(height: 60)
                .overlay(
                    Text("Practice Dock")
                        .foregroundStyle(AppColors.textSecondary)
                )
        }
    }
}

#Preview("Configuration Mode - Results Summary") {
    struct PreviewWrapper: View {
        @State private var expanded = false
        @State private var mode: SessionMode = .readThenSpeak
        
        var body: some View {
            ZStack {
                AppColors.backgroundPrimary.ignoresSafeArea()
                
                // Simulated scrolling content
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.md) {
                        ForEach(0..<10) { i in
                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                                .fill(AppColors.backgroundSecondary)
                                .frame(height: 100)
                                .overlay(
                                    Text("Card \(i + 1)")
                                        .foregroundStyle(AppColors.textSecondary)
                                )
                        }
                    }
                    .padding()
                    .padding(.bottom, 160) // Space for dock
                }
                
                AdaptiveDockContainer.resultsSummary(
                    isModeSelectorExpanded: $expanded,
                    selectedMode: $mode
                ) {
                    // Simulated dock
                    HStack {
                        Button("Mode ▼") {
                            withAnimation(AppTheme.Animation.standard) {
                                expanded.toggle()
                            }
                        }
                        .padding()
                        .background(AppColors.backgroundSecondary)
                        .clipShape(Capsule())
                        
                        Spacer()
                        
                        Circle()
                            .fill(AppColors.accent)
                            .frame(width: 48, height: 48)
                    }
                }
            }
        }
    }
    
    return PreviewWrapper()
}

#Preview("Configuration Mode - Favorites") {
    struct PreviewWrapper: View {
        @State private var expanded = false
        @State private var mode: SessionMode = .readAloud
        
        var body: some View {
            ZStack {
                AppColors.backgroundPrimary.ignoresSafeArea()
                
                AdaptiveDockContainer.favorites(
                    count: 12,
                    isModeSelectorExpanded: $expanded,
                    selectedMode: $mode
                ) {
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.extraLarge)
                        .fill(AppColors.backgroundSecondary)
                        .frame(height: 60)
                        .overlay(
                            Text("Favorites Dock")
                                .foregroundStyle(AppColors.textSecondary)
                        )
                }
            }
        }
    }
    
    return PreviewWrapper()
}
