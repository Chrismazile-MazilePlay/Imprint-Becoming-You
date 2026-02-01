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
/// - Tap to select: Immediately saves selection
/// - Live preview: Each option shows animated waveform
/// - Back navigation: Standard navigation bar back button
///
/// ## Navigation
/// This view is pushed onto the Profile navigation stack.
struct WaveformSelectionView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - Bindings
    
    /// The currently selected waveform type (bound to UserProfile)
    @Binding var selectedType: DockWaveformType
    
    // MARK: - State
    
    /// Animation state for previews
    @State private var previewState: DockCenterContentState = .playing(audioLevel: 0.6)
    
    /// Timer for cycling preview states
    @State private var previewTimer: Timer?
    
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
                        isSelected: selectedType == type,
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
        .onAppear {
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
            
            Text("Tap to select")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(.vertical, AppTheme.Spacing.sm)
    }
    
    // MARK: - Selection
    
    private func selectWaveform(_ type: DockWaveformType) {
        guard selectedType != type else { return }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedType = type
        }
        
        // Save to persistence
        try? modelContext.save()
        
        // Haptic feedback
        HapticFeedback.selection()
        
        #if DEBUG
        print("🌊 WaveformSelectionView: Selected \(type.displayName)")
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
