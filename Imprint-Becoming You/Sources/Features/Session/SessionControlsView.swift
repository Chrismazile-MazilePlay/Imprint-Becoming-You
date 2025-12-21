//
//  SessionControlsView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/21/25.
//

import SwiftUI

// MARK: - SessionControlsView

/// Bottom control bar for the session with mode and binaural controls.
///
/// The expanded selectors are rendered as overlays in SessionContainerView
/// to avoid clipping issues.
struct SessionControlsView: View {
    
    // MARK: - Properties
    
    @Bindable var viewModel: SessionViewModel
    
    /// Whether the binaural selector is expanded (passed from parent)
    @Binding var showBinauralSelector: Bool
    
    /// Callback when binaural preset changes
    let onBinauralChange: (BinauralPreset) async -> Void
    
    // MARK: - Body
    
    var body: some View {
        // Main controls bar only - menus are overlays in parent
        HStack(spacing: AppTheme.Spacing.md) {
            // Mode button
            ModeButton(
                mode: viewModel.sessionMode,
                isExpanded: viewModel.showModeSelector
            ) {
                withAnimation(AppTheme.Animation.standard) {
                    viewModel.showModeSelector.toggle()
                    showBinauralSelector = false
                }
            }
            
            Spacer(minLength: 0)
            
            // Progress indicator
            ProgressPill(
                current: viewModel.currentIndex + 1,
                total: viewModel.affirmations.count
            )
            
            Spacer(minLength: 0)
            
            // Binaural button
            BinauralButton(
                preset: viewModel.binauralPreset,
                isExpanded: showBinauralSelector
            ) {
                withAnimation(AppTheme.Animation.standard) {
                    showBinauralSelector.toggle()
                    viewModel.showModeSelector = false
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
        .background(
            AppColors.backgroundSecondary
                .opacity(0.95)
        )
    }
}

// MARK: - ModeButton

/// Button showing current mode with tap to expand
struct ModeButton: View {
    
    let mode: SessionMode
    let isExpanded: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 14, weight: .semibold))
                
                Text(mode.displayName)
                    .font(AppTypography.caption1.weight(.medium))
                    .lineLimit(1)
                
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(AppColors.accent)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(AppColors.accent.opacity(0.15))
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityLabel("Session mode: \(mode.displayName)")
        .accessibilityHint("Double tap to change mode")
    }
}

// MARK: - ModeSelectorExpanded

/// Expanded mode selector showing all options
struct ModeSelectorExpanded: View {
    
    let selectedMode: SessionMode
    let onSelect: (SessionMode) -> Void
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ForEach(SessionMode.allCases) { mode in
                ModeOptionRow(
                    mode: mode,
                    isSelected: mode == selectedMode
                ) {
                    onSelect(mode)
                    HapticFeedback.selection()
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large))
        .shadow(color: .black.opacity(0.3), radius: 20, y: -5)
        .padding(.horizontal, AppTheme.Spacing.lg)
    }
}

// MARK: - ModeOptionRow

/// Single row in the mode selector
struct ModeOptionRow: View {
    
    let mode: SessionMode
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.md) {
                // Icon
                Image(systemName: mode.iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.textSecondary)
                    .frame(width: 24)
                
                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.displayName)
                        .font(AppTypography.headline)
                        .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                    
                    Text(mode.description)
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer(minLength: 0)
                
                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppColors.accent)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(isSelected ? AppColors.accent.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ProgressPill

/// Pill showing current/total progress
struct ProgressPill: View {
    
    let current: Int
    let total: Int
    
    var body: some View {
        Text("\(current) / \(total)")
            .font(AppTypography.caption1.weight(.medium).monospacedDigit())
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(AppColors.surfaceTertiary)
            .clipShape(Capsule())
            .fixedSize()
            .accessibilityLabel("Affirmation \(current) of \(total)")
    }
}

// MARK: - BinauralButton

/// Button for binaural beat control
struct BinauralButton: View {
    
    let preset: BinauralPreset
    let isExpanded: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: preset.iconName)
                    .font(.system(size: 14, weight: .semibold))
                
                if preset != .off {
                    Text(preset.displayName)
                        .font(AppTypography.caption1.weight(.medium))
                        .lineLimit(1)
                }
                
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(preset == .off ? AppColors.textSecondary : AppColors.accentSecondary)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(
                preset == .off
                    ? AppColors.surfaceTertiary
                    : AppColors.accentSecondary.opacity(0.15)
            )
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityLabel("Binaural beats: \(preset.displayName)")
        .accessibilityHint("Double tap to change binaural preset")
    }
}

// MARK: - BinauralSelectorExpanded

/// Expanded binaural selector showing all options
struct BinauralSelectorExpanded: View {
    
    let selectedPreset: BinauralPreset
    let onSelect: (BinauralPreset) -> Void
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ForEach(BinauralPreset.allCases) { preset in
                BinauralOptionRow(
                    preset: preset,
                    isSelected: preset == selectedPreset
                ) {
                    onSelect(preset)
                    HapticFeedback.selection()
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large))
        .shadow(color: .black.opacity(0.3), radius: 20, y: -5)
        .padding(.horizontal, AppTheme.Spacing.lg)
    }
}

// MARK: - BinauralOptionRow

/// Single row in the binaural selector
struct BinauralOptionRow: View {
    
    let preset: BinauralPreset
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.md) {
                // Icon
                Image(systemName: preset.iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? AppColors.accentSecondary : AppColors.textSecondary)
                    .frame(width: 24)
                
                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.displayName)
                        .font(AppTypography.headline)
                        .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                    
                    if preset != .off {
                        Text(preset.description)
                            .font(AppTypography.caption2)
                            .foregroundStyle(AppColors.textTertiary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                Spacer(minLength: 0)
                
                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppColors.accentSecondary)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(isSelected ? AppColors.accentSecondary.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SessionTopBar

/// Top bar with close button only
struct SessionTopBar: View {
    
    let onClose: () -> Void
    
    var body: some View {
        HStack {
            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(AppColors.surfaceTertiary)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Close session")
            
            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
    }
}

// MARK: - InactivityPopup

/// Popup shown when user is inactive
struct InactivityPopup: View {
    
    let countdown: Int
    let onContinue: () -> Void
    let onEnd: () -> Void
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            // Icon
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.accent)
            
            // Message
            VStack(spacing: AppTheme.Spacing.sm) {
                Text("Are you still there?")
                    .font(AppTypography.title3)
                    .foregroundStyle(AppColors.textPrimary)
                
                Text("Session will pause in \(countdown) seconds")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }
            
            // Buttons
            VStack(spacing: AppTheme.Spacing.sm) {
                Button {
                    onContinue()
                } label: {
                    Text("I'm Here!")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                
                Button {
                    onEnd()
                } label: {
                    Text("End Session")
                }
                .buttonStyle(.ghost)
            }
        }
        .padding(AppTheme.Spacing.xl)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.extraLarge))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .padding(.horizontal, AppTheme.Spacing.xl)
    }
}

// MARK: - Previews

#Preview("Session Controls") {
    struct PreviewWrapper: View {
        @State private var showBinaural = false
        @State private var viewModel = SessionViewModel()
        
        var body: some View {
            VStack {
                Spacer()
                SessionControlsView(
                    viewModel: viewModel,
                    showBinauralSelector: $showBinaural,
                    onBinauralChange: { _ in }
                )
            }
            .background(AppColors.backgroundPrimary)
            .onAppear {
                viewModel.affirmations = Affirmation.samples
                viewModel.currentIndex = 2
                viewModel.sessionMode = .readThenSpeak
                viewModel.binauralPreset = .focus
            }
        }
    }
    return PreviewWrapper()
}

#Preview("Mode Selector Expanded") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        
        VStack {
            Spacer()
            ModeSelectorExpanded(
                selectedMode: .readThenSpeak,
                onSelect: { _ in }
            )
        }
    }
}

#Preview("Binaural Selector Expanded") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        
        VStack {
            Spacer()
            BinauralSelectorExpanded(
                selectedPreset: .focus,
                onSelect: { _ in }
            )
        }
    }
}

#Preview("Session Top Bar") {
    SessionTopBar(onClose: {})
        .background(AppColors.backgroundPrimary)
}

#Preview("Inactivity Popup") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        
        InactivityPopup(
            countdown: 7,
            onContinue: {},
            onEnd: {}
        )
    }
}
