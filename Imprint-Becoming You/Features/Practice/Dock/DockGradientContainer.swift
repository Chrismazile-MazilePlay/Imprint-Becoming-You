//
//  DockGradientContainer.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/14/26.
//

import SwiftUI

// MARK: - DockGradientContainer

/// A container providing subtle gradient background for dock-based views.
///
/// Creates clean visual separation between scrolling content and the
/// fixed dock area using an industry-standard content fade gradient.
///
/// ## Z-Stack Layering (Back to Front)
/// 1. **Gradient** (BACK) - Subtle fade for content separation
/// 2. **Mode Menu** (MIDDLE) - Slides up from behind the dock
/// 3. **Dock + Label** (FRONT) - Always visible, covers collapsed menu
///
/// ## Layout
/// ```
/// ┌─────────────────────────────────────────────────────────────────┐
/// │  ░░░░░░░░ (gradient - BACK layer) ░░░░░░░░░░░░░░░░░░░░░░░░░░░  │
/// │  ┌─────────────────────────────────────────────────────────┐   │
/// │  │  Mode Menu (MIDDLE - slides up from BEHIND dock)       │   │
/// │  └─────────────────────────────────────────────────────────┘   │
/// │  [Mode ▼]       [🔁 3] [🔀]         [▶]   ← FRONT             │
/// │  "Practice 9 affirmations"                                     │
/// └─────────────────────────────────────────────────────────────────┘
/// ```
struct DockGradientContainer<DockContent: View>: View {
    
    // MARK: - Properties
    
    /// Label text displayed below the dock (empty string = no label)
    let label: String
    
    /// Whether the mode selector is expanded (for showing above gradient)
    @Binding var isModeSelectorExpanded: Bool
    
    /// Currently selected mode
    @Binding var selectedMode: SessionMode
    
    /// The dock content to display
    @ViewBuilder let dockContent: () -> DockContent
    
    // MARK: - Constants
    
    /// Height of the subtle gradient fade zone
    private let gradientHeight: CGFloat = 48
    
    // MARK: - Initialization
    
    init(
        label: String = "",
        isModeSelectorExpanded: Binding<Bool>,
        selectedMode: Binding<SessionMode>,
        @ViewBuilder dockContent: @escaping () -> DockContent
    ) {
        self.label = label
        self._isModeSelectorExpanded = isModeSelectorExpanded
        self._selectedMode = selectedMode
        self.dockContent = dockContent
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Dismiss overlay when selector is expanded (full screen tap target)
            if isModeSelectorExpanded {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(AppTheme.Animation.standard) {
                            isModeSelectorExpanded = false
                        }
                    }
                    .ignoresSafeArea()
            }
            
            // Layer 1 (BACK): Gradient
            VStack(spacing: 0) {
                gradientOverlay
                
                // Solid background that extends behind dock area
                AppColors.backgroundPrimary
                    .frame(height: dockAreaHeight)
            }
            
            // Layer 2 (MIDDLE): Mode menu - slides up from behind dock
            expandedModeSelector
            
            // Layer 3 (FRONT): Dock + Label
            dockAndLabel
        }
    }
    
    // MARK: - Dock Area Height
    
    /// Calculated height for the dock area (dock + label + padding)
    private var dockAreaHeight: CGFloat {
        // Approximate height: dock (~60) + label (~20) + padding
        let baseHeight: CGFloat = 80
        let labelHeight: CGFloat = label.isEmpty ? 0 : 24
        return baseHeight + labelHeight
    }
    
    // MARK: - Gradient Overlay
    
    /// Industry-standard content fade gradient.
    /// Uses soft exponential opacity curve for natural visual transition.
    private var gradientOverlay: some View {
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
    }
    
    // MARK: - Expanded Mode Selector (Middle Layer)
    
    @ViewBuilder
    private var expandedModeSelector: some View {
        VStack(spacing: 0) {
            if isModeSelectorExpanded {
                ModeSelectorExpanded(
                    selectedMode: selectedMode,
                    showOnlyPlayableModes: true,
                    onSelect: { mode in
                        selectedMode = mode
                        withAnimation(AppTheme.Animation.standard) {
                            isModeSelectorExpanded = false
                        }
                        HapticFeedback.selection()
                    }
                )
                .padding(.horizontal, AppTheme.Spacing.lg)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Spacer to position menu just above dock
            Spacer()
                .frame(height: dockAreaHeight)
        }
        .animation(AppTheme.Animation.standard, value: isModeSelectorExpanded)
    }
    
    // MARK: - Dock and Label (Front Layer)
    
    private var dockAndLabel: some View {
        VStack(spacing: 0) {
            // Dock content
            dockContent()
            
            // Label below dock (if provided)
            if !label.isEmpty {
                Text(label)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.top, AppTheme.Spacing.xs)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.bottom, AppTheme.Spacing.sm)
        .background(AppColors.backgroundPrimary)
    }
}

// MARK: - Convenience Extensions

extension DockGradientContainer {
    
    /// Creates a container for Results Summary context
    static func resultsSummary(
        isModeSelectorExpanded: Binding<Bool>,
        selectedMode: Binding<SessionMode>,
        @ViewBuilder dockContent: @escaping () -> DockContent
    ) -> DockGradientContainer {
        DockGradientContainer(
            label: "Repeat Session",
            isModeSelectorExpanded: isModeSelectorExpanded,
            selectedMode: selectedMode,
            dockContent: dockContent
        )
    }
    
    /// Creates a container for Favorites context
    static func favorites(
        count: Int,
        isModeSelectorExpanded: Binding<Bool>,
        selectedMode: Binding<SessionMode>,
        @ViewBuilder dockContent: @escaping () -> DockContent
    ) -> DockGradientContainer {
        DockGradientContainer(
            label: "Practice \(count) affirmation\(count == 1 ? "" : "s")",
            isModeSelectorExpanded: isModeSelectorExpanded,
            selectedMode: selectedMode,
            dockContent: dockContent
        )
    }
    
    /// Creates a container for Saved Sessions context (no label)
    static func savedSessions(
        isModeSelectorExpanded: Binding<Bool>,
        selectedMode: Binding<SessionMode>,
        @ViewBuilder dockContent: @escaping () -> DockContent
    ) -> DockGradientContainer {
        DockGradientContainer(
            label: "",
            isModeSelectorExpanded: isModeSelectorExpanded,
            selectedMode: selectedMode,
            dockContent: dockContent
        )
    }
}

// MARK: - Previews

#Preview("Gradient Container - Results Summary") {
    struct PreviewWrapper: View {
        @State private var expanded = false
        @State private var mode: SessionMode = .readThenSpeak
        
        var body: some View {
            ZStack {
                AppColors.backgroundPrimary
                    .ignoresSafeArea()
                
                // Simulated card content
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.md) {
                        ForEach(0..<10) { i in
                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                                .fill(AppColors.backgroundSecondary)
                                .frame(height: 120)
                                .overlay(
                                    Text("Card \(i + 1)")
                                        .foregroundStyle(AppColors.textSecondary)
                                )
                        }
                    }
                    .padding()
                    .padding(.bottom, 200)
                }
                
                // Gradient container
                VStack {
                    Spacer()
                    
                    DockGradientContainer.resultsSummary(
                        isModeSelectorExpanded: $expanded,
                        selectedMode: $mode
                    ) {
                        // Simulated dock
                        HStack {
                            Button("Mode ▼") { expanded.toggle() }
                                .padding()
                                .background(AppColors.backgroundSecondary)
                                .clipShape(Capsule())
                            
                            Spacer()
                            
                            Circle()
                                .fill(AppColors.accent)
                                .frame(width: 56, height: 56)
                        }
                    }
                }
            }
        }
    }
    
    return PreviewWrapper()
}

#Preview("Gradient Container - Favorites") {
    struct PreviewWrapper: View {
        @State private var expanded = false
        @State private var mode: SessionMode = .readThenSpeak
        
        var body: some View {
            ZStack {
                AppColors.backgroundPrimary
                    .ignoresSafeArea()
                
                VStack {
                    Spacer()
                    
                    DockGradientContainer.favorites(
                        count: 9,
                        isModeSelectorExpanded: $expanded,
                        selectedMode: $mode
                    ) {
                        RoundedRectangle(cornerRadius: AppTheme.CornerRadius.extraLarge)
                            .fill(AppColors.backgroundSecondary)
                            .frame(height: 60)
                            .overlay(
                                Text("Dock Content")
                                    .foregroundStyle(AppColors.textSecondary)
                            )
                    }
                }
            }
        }
    }
    
    return PreviewWrapper()
}
