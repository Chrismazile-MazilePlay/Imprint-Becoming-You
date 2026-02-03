//
//  WaveformSelectionView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/1/26.
//

import SwiftUI

// MARK: - WaveformSelectionView

/// View for selecting the preferred waveform visualization style.
///
/// Displays all available waveform styles with live previews,
/// allowing users to see each style in action before selecting.
///
/// ## Behavior
/// - Tap to select (pending until Save is tapped)
/// - Save button appears when selection differs from saved type
/// - Save button appears when selection differs from saved type, disables after save
/// - Live preview: Each option shows animated waveform
///
/// ## Navigation
/// This view is pushed onto the Profile navigation stack.
struct WaveformSelectionView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - Bindings
    
    /// The currently saved waveform type (bound to UserProfile)
    @Binding var selectedType: DockWaveformType
    
    // MARK: - State
    
    /// The waveform type that was last saved.
    /// Updated each time the user taps Save, so change detection stays reactive.
    @State private var savedType: DockWaveformType = .layeredWaves
    
    /// The currently selected (pending) waveform type
    @State private var pendingType: DockWaveformType = .layeredWaves
    
    /// Animation state for previews
    @State private var previewState: DockCenterContentState = .playing(audioLevel: 0.6)
    
    /// Timer for cycling preview states
    @State private var previewTimer: Timer?
    
    // MARK: - Computed Properties
    
    /// Whether the user has made a change that differs from the saved type
    private var hasUnsavedChanges: Bool {
        pendingType != savedType
    }
    
    // MARK: - Body
    
    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                // Header description
                headerSection
                
                // Waveform options
                ForEach(DockWaveformType.allCases) { type in
                    WaveformOptionCard(
                        type: type,
                        isSelected: pendingType == type,
                        previewState: previewState
                    ) {
                        selectWaveform(type)
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)
        }
        .background(AppColors.backgroundPrimary)
        .navigationTitle("Waveform Style")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SaveToolbarButton(
                    hasUnsavedChanges: hasUnsavedChanges,
                    accessibilityHint: "Saves \(pendingType.displayName) as your waveform style",
                    onSave: { saveWaveformSelection() }
                )
            }
        }
        .onAppear {
            savedType = selectedType
            pendingType = selectedType
            startPreviewAnimation()
        }
        .onDisappear {
            stopPreviewAnimation()
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Text("Choose how your waveform looks during practice sessions.")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            
            Text(hasUnsavedChanges ? "Tap Save to confirm your selection" : "Tap to select")
                .font(AppTypography.caption1)
                .foregroundStyle(hasUnsavedChanges ? AppColors.accent : AppColors.textTertiary)
        }
        .padding(.vertical, AppTheme.Spacing.sm)
    }
    
    // MARK: - Selection
    
    private func selectWaveform(_ type: DockWaveformType) {
        guard pendingType != type else { return }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            pendingType = type
        }
        
        // Haptic feedback for selection
        HapticFeedback.selection()
        
        #if DEBUG
        print("WaveformSelectionView: Pending selection \(type.displayName)")
        #endif
    }
    
    private func saveWaveformSelection() {
        // Update the binding (which updates UserProfile)
        selectedType = pendingType
        
        // Save to persistence
        try? modelContext.save()
        
        // Update saved baseline - hasUnsavedChanges becomes false
        savedType = pendingType
        
        // Haptic feedback for save
        HapticFeedback.notification(.success)
        
        #if DEBUG
        print("WaveformSelectionView: Saved \(pendingType.displayName)")
        #endif
    }
    
    // MARK: - Preview Animation
    
    private func startPreviewAnimation() {
        // Cycle through preview states for more dynamic preview
        previewTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                switch previewState {
                case .playing:
                    previewState = .listening(audioLevel: 0.7)
                case .listening:
                    previewState = .playing(audioLevel: 0.6)
                default:
                    previewState = .playing(audioLevel: 0.6)
                }
            }
        }
    }
    
    private func stopPreviewAnimation() {
        previewTimer?.invalidate()
        previewTimer = nil
    }
}

// MARK: - WaveformOptionCard

/// A card displaying a single waveform option with live preview.
private struct WaveformOptionCard: View {
    
    let type: DockWaveformType
    let isSelected: Bool
    let previewState: DockCenterContentState
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: AppTheme.Spacing.md) {
                // Live preview
                previewContainer
                
                // Info row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(type.displayName)
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColors.textPrimary)
                        
                        Text(type.description)
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    Spacer()
                    
                    // Selection indicator
                    selectionIndicator
                }
            }
            .padding(AppTheme.Spacing.md)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large))
            .overlay(selectionBorder)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(type.displayName). \(type.description)")
        .accessibilityHint(isSelected ? "Currently selected" : "Tap to select")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
    
    // MARK: - Preview Container
    
    private var previewContainer: some View {
        ZStack {
            // Dark background for preview
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                .fill(Color.black)
            
            // Waveform preview based on type - wrapped in TimelineView for animation
            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let breathingPhase = CGFloat((elapsed / 2.0).truncatingRemainder(dividingBy: 1.0))
                
                waveformPreview(breathingPhase: breathingPhase)
            }
            .frame(height: 50)
            .padding(.horizontal, AppTheme.Spacing.lg)
        }
        .frame(height: 80)
    }
    
    /// Renders the waveform preview for this type.
    @ViewBuilder
    private func waveformPreview(breathingPhase: CGFloat) -> some View {
        let tokens = DefaultDockDesignTokens()
        switch type {
        case .layeredWaves:
            LayeredWavesWaveformView(state: previewState, tokens: tokens, breathingPhase: breathingPhase)
        case .classicBars:
            ClassicBarsWaveformView(state: previewState, tokens: tokens, breathingPhase: breathingPhase)
        }
    }
    
    // MARK: - Selection Indicator
    
    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    isSelected ? AppColors.accent : AppColors.textTertiary,
                    lineWidth: 2
                )
                .frame(width: 24, height: 24)
            
            if isSelected {
                Circle()
                    .fill(AppColors.accent)
                    .frame(width: 14, height: 14)
            }
        }
    }
    
    // MARK: - Styling
    
    private var cardBackground: Color {
        isSelected ? AppColors.surfaceSecondary : AppColors.surfaceSecondary.opacity(0.6)
    }
    
    private var selectionBorder: some View {
        RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
            .strokeBorder(
                isSelected ? AppColors.accent : Color.clear,
                lineWidth: 2
            )
    }
}

// MARK: - Previews

#Preview("Waveform Selection View") {
    struct PreviewWrapper: View {
        @State private var selectedType: DockWaveformType = .layeredWaves
        
        var body: some View {
            NavigationStack {
                WaveformSelectionView(selectedType: $selectedType)
            }
        }
    }
    
    return PreviewWrapper()
}

#Preview("Waveform Option Card - Selected") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        
        WaveformOptionCard(
            type: .layeredWaves,
            isSelected: true,
            previewState: .playing(audioLevel: 0.6),
            onSelect: {}
        )
        .padding()
    }
}

#Preview("Waveform Option Card - Unselected") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        
        WaveformOptionCard(
            type: .classicBars,
            isSelected: false,
            previewState: .listening(audioLevel: 0.5),
            onSelect: {}
        )
        .padding()
    }
}
