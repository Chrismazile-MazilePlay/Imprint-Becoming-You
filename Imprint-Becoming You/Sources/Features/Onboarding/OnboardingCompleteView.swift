//
//  OnboardingCompleteView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import SwiftUI

// MARK: - OnboardingCompleteView

/// Final onboarding screen showing success and transitioning to main app.
///
/// Features:
/// - Animated success state
/// - Summary of selected goals
/// - Transition to main app
struct OnboardingCompleteView: View {
    
    // MARK: - Environment
    
    @Environment(\.appState) private var appState
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - Properties
    
    @Bindable var viewModel: OnboardingViewModel
    
    // MARK: - State
    
    @State private var showCheckmark: Bool = false
    @State private var showContent: Bool = false
    @State private var checkmarkScale: CGFloat = 0
    @State private var confettiTrigger: Int = 0
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Success animation
            VStack(spacing: AppTheme.Spacing.xl) {
                // Checkmark animation
                ZStack {
                    // Outer ring
                    Circle()
                        .stroke(AppColors.success.opacity(0.3), lineWidth: 4)
                        .frame(width: 120, height: 120)
                    
                    // Inner fill
                    Circle()
                        .fill(AppColors.success)
                        .frame(width: 100, height: 100)
                        .scaleEffect(checkmarkScale)
                    
                    // Checkmark
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(AppColors.backgroundPrimary)
                        .opacity(showCheckmark ? 1 : 0)
                        .scaleEffect(showCheckmark ? 1 : 0.5)
                }
                
                // Success message
                VStack(spacing: AppTheme.Spacing.sm) {
                    Text("You're All Set!")
                        .font(AppTypography.largeTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text("Your personalized affirmation journey begins now")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)
            }
            
            Spacer()
            
            // Selected goals summary
            if !viewModel.selectedGoals.isEmpty && showContent {
                VStack(spacing: AppTheme.Spacing.md) {
                    Text("Your Focus Areas")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textSecondary)
                    
                    FlowLayout(spacing: AppTheme.Spacing.sm) {
                        ForEach(Array(viewModel.selectedGoals), id: \.self) { goal in
                            GoalBadge(category: goal)
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .opacity(showContent ? 1 : 0)
            }
            
            Spacer()
            
            // Start button
            VStack(spacing: AppTheme.Spacing.md) {
                Button {
                    completeOnboarding()
                } label: {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        if viewModel.isCompleting {
                            ProgressView()
                                .tint(AppColors.backgroundPrimary)
                        } else {
                            Text("Begin Your Journey")
                            Image(systemName: "arrow.right")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                .disabled(viewModel.isCompleting)
                
                // Calibration status
                if viewModel.skippedCalibration {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Image(systemName: "info.circle")
                        Text("Voice calibration skipped – you can do this later in Settings")
                    }
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textTertiary)
                } else if viewModel.calibrationData != nil {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppColors.success)
                        Text("Voice calibrated for personalized scoring")
                    }
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.xl)
            .opacity(showContent ? 1 : 0)
        }
        .onAppear {
            animateIn()
        }
    }
    
    // MARK: - Actions
    
    private func completeOnboarding() {
        Task {
            await viewModel.completeOnboarding(
                modelContext: modelContext,
                appState: appState
            )
        }
    }
    
    // MARK: - Animation
    
    private func animateIn() {
        // Checkmark scale animation
        withAnimation(.spring(duration: 0.5, bounce: 0.4).delay(0.2)) {
            checkmarkScale = 1.0
        }
        
        // Checkmark visibility
        withAnimation(.easeOut(duration: 0.3).delay(0.5)) {
            showCheckmark = true
        }
        
        // Content fade in
        withAnimation(.easeOut(duration: 0.5).delay(0.7)) {
            showContent = true
        }
        
        // Haptic feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            HapticFeedback.notification(.success)
        }
    }
}

// MARK: - GoalBadge

/// Badge showing a selected goal
struct GoalBadge: View {
    
    let category: GoalCategory
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: category.iconName)
                .font(.system(size: 12))
            
            Text(category.rawValue)
                .font(AppTypography.caption1)
        }
        .foregroundStyle(AppColors.accent)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xs)
        .background(AppColors.accent.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - FlowLayout

/// A layout that arranges views in a flowing manner
struct FlowLayout: Layout {
    
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(
                    x: bounds.minX + result.positions[index].x,
                    y: bounds.minY + result.positions[index].y
                ),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }
    
    struct FlowResult {
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var size: CGSize = .zero
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            var maxX: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > maxWidth && currentX > 0 {
                    // Move to next line
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: currentX, y: currentY))
                sizes.append(size)
                
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
                maxX = max(maxX, currentX)
            }
            
            size = CGSize(width: maxX, height: currentY + lineHeight)
        }
    }
}

// MARK: - Previews

#Preview("Onboarding Complete") {
    let vm = OnboardingViewModel()
    vm.selectedGoals = [.confidence, .focus, .faith, .peace]
    vm.calibrationData = CalibrationData(
        baselineRMS: 0.3,
        pitchMin: 100,
        pitchMax: 250,
        volumeMin: -30,
        volumeMax: -10
    )
    
    return OnboardingCompleteView(viewModel: vm)
        .background(AppColors.backgroundPrimary)
        .previewEnvironment()
}

#Preview("Onboarding Complete - Skipped Calibration") {
    let vm = OnboardingViewModel()
    vm.selectedGoals = [.confidence, .abundance]
    vm.skippedCalibration = true
    
    return OnboardingCompleteView(viewModel: vm)
        .background(AppColors.backgroundPrimary)
        .previewEnvironment()
}

#Preview("Goal Badge") {
    HStack(spacing: 8) {
        GoalBadge(category: .confidence)
        GoalBadge(category: .focus)
        GoalBadge(category: .faith)
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("Flow Layout") {
    FlowLayout(spacing: 8) {
        ForEach([GoalCategory.confidence, .focus, .faith, .abundance, .peace], id: \.self) { goal in
            GoalBadge(category: goal)
        }
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}
