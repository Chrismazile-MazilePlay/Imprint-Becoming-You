//
//  SessionPreparationView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/26/26.
//

import SwiftUI
import Combine

// MARK: - Session Preparation View

/// Loading screen shown while pre-synthesizing session affirmations.
///
/// Features:
/// - **Phase-based progress**: Warm-up (0→15%), Synthesis (15→99%), Complete (100%)
/// - **Smooth animation**: Time-based progress with easing catch-up (60fps)
/// - **Game-style status text**: Fades between status messages
/// - **Xbox "Ready to Start" pattern**: Large sessions show "Start Now" at 15 ready
/// - **Fallback UI**: Timeout shows "Continue with System Voice" and "Retry" buttons
///
/// ## Progress Bar Behavior
/// ```
/// Phase 0: Immediate      0% → 2%     Instant (feels responsive)
/// Phase 1: Kokoro Warmup  2% → 15%    ~1-9 seconds
/// Phase 2: Synthesis     15% → 99%    Time-based with actual catch-up
/// Phase 3: Complete      99% → 100%   On true completion only
/// ```
struct SessionPreparationView: View {
    
    // MARK: - Properties
    
    /// Current preparation phase
    let phase: SessionPreparationPhase
    
    /// Number of affirmations prepared
    let preparedCount: Int
    
    /// Total number of affirmations to prepare
    let totalCount: Int
    
    /// Whether the "Start Now" threshold has been reached (for large sessions)
    let canStartEarly: Bool
    
    /// Called when user taps "Start Now" (large sessions only)
    let onStartNow: () -> Void
    
    /// Called when user taps "Continue with System Voice" (timeout only)
    let onContinueWithSystemVoice: () -> Void
    
    /// Called when user taps "Retry" (timeout only)
    let onRetry: () -> Void
    
    /// Called when user taps cancel
    let onCancel: () -> Void
    
    // MARK: - Computed Properties
    
    /// Whether this is a large session that shows "Start Now" button
    private var isLargeSession: Bool {
        totalCount > Constants.SessionPreparation.largeSessionThreshold
    }
    
    // MARK: - State
    
    /// Displayed progress (smooth animation target)
    @State private var displayedProgress: CGFloat = Constants.SessionPreparation.immediateProgress
    
    /// Animation phase for breathing effect
    @State private var breathingPhase: CGFloat = 0
    
    /// Current status message index
    @State private var statusMessageIndex: Int = 0
    
    /// Status message opacity for fade animation
    @State private var statusMessageOpacity: Double = 1.0
    
    /// Warm-up start time (for time-based progress)
    @State private var warmupStartTime: Date?
    
    /// Synthesis start time (for time-based progress)
    @State private var synthesisStartTime: Date?
    
    /// Timer for smooth progress animation
    private let animationTimer = Timer.publish(
        every: Constants.SessionPreparation.progressAnimationInterval,
        on: .main,
        in: .common
    ).autoconnect()
    
    /// Timer for status message cycling
    private let statusTimer = Timer.publish(
        every: Constants.SessionPreparation.statusMessageInterval,
        on: .main,
        in: .common
    ).autoconnect()
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.9)
                .ignoresSafeArea()
            
            if phase == .kokoroTimeout {
                // Fallback UI for timeout
                timeoutContent
            } else if case .error(let message) = phase {
                // Error UI
                errorContent(message: message)
            } else {
                // Normal preparation UI
                preparationContent
            }
        }
        .onAppear {
            startAnimations()
        }
        .onChange(of: phase) { oldPhase, newPhase in
            handlePhaseChange(from: oldPhase, to: newPhase)
        }
        .onReceive(animationTimer) { _ in
            updateSmoothProgress()
        }
        .onReceive(statusTimer) { _ in
            cycleStatusMessage()
        }
    }
    
    // MARK: - Preparation Content
    
    private var preparationContent: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer()
            
            // Breathing animation
            breathingIndicator
            
            // Status text with fade animation
            statusTextView
            
            // Progress bar
            smoothProgressBar
                .padding(.horizontal, AppTheme.Spacing.xxl)
            
            // Start Now button (for large sessions during synthesis)
            if isLargeSession && phase == .synthesizing {
                startNowButton
                    .padding(.top, AppTheme.Spacing.lg)
            }
            
            Spacer()
            
            // Cancel button
            cancelButton
                .padding(.bottom, AppTheme.Spacing.xxl)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }
    
    // MARK: - Timeout Content
    
    private var timeoutContent: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer()
            
            // Paused indicator
            Image(systemName: "waveform.circle")
                .font(.system(size: 60))
                .foregroundStyle(AppColors.textSecondary)
            
            // Message
            VStack(spacing: AppTheme.Spacing.sm) {
                Text("Voice engine taking longer")
                    .font(AppTypography.title3)
                    .foregroundStyle(AppColors.textPrimary)
                
                Text("than expected to load")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.top, AppTheme.Spacing.md)
            
            // Action buttons
            VStack(spacing: AppTheme.Spacing.md) {
                // Continue with System Voice
                Button {
                    HapticFeedback.impact(.medium)
                    onContinueWithSystemVoice()
                } label: {
                    Text("Continue with System Voice")
                        .font(AppTypography.body.weight(.semibold))
                        .foregroundStyle(AppColors.backgroundPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.md)
                        .background(AppColors.accent)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, AppTheme.Spacing.xxl)
                
                // Retry button
                Button {
                    HapticFeedback.impact(.light)
                    onRetry()
                } label: {
                    Text("Retry")
                        .font(AppTypography.body.weight(.medium))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.md)
                        .background(AppColors.surfaceTertiary)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, AppTheme.Spacing.xxl)
            }
            .padding(.top, AppTheme.Spacing.xl)
            
            Spacer()
            
            // Cancel button
            cancelButton
                .padding(.bottom, AppTheme.Spacing.xxl)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Voice engine timeout. Choose to continue with system voice or retry.")
    }
    
    // MARK: - Error Content
    
    private func errorContent(message: String) -> some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer()
            
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(AppColors.warning)
            
            VStack(spacing: AppTheme.Spacing.sm) {
                Text("Preparation Failed")
                    .font(AppTypography.title3)
                    .foregroundStyle(AppColors.textPrimary)
                
                Text(message)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppTheme.Spacing.xl)
            
            Button {
                HapticFeedback.impact(.light)
                onRetry()
            } label: {
                Text("Retry")
                    .font(AppTypography.body.weight(.semibold))
                    .foregroundStyle(AppColors.backgroundPrimary)
                    .padding(.horizontal, AppTheme.Spacing.xl)
                    .padding(.vertical, AppTheme.Spacing.md)
                    .background(AppColors.accent)
                    .clipShape(Capsule())
            }
            .padding(.top, AppTheme.Spacing.lg)
            
            Spacer()
            
            cancelButton
                .padding(.bottom, AppTheme.Spacing.xxl)
        }
    }
    
    // MARK: - Subviews
    
    private var breathingIndicator: some View {
        ZStack {
            Circle()
                .fill(AppColors.accent.opacity(0.15))
                .frame(width: 120 + breathingPhase * 20, height: 120 + breathingPhase * 20)
            
            Circle()
                .fill(AppColors.accent.opacity(0.25))
                .frame(width: 80 + breathingPhase * 15, height: 80 + breathingPhase * 15)
            
            Circle()
                .fill(AppColors.accent.opacity(0.4))
                .frame(width: 50 + breathingPhase * 10, height: 50 + breathingPhase * 10)
            
            Circle()
                .fill(AppColors.accent)
                .frame(width: 16, height: 16)
        }
        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: breathingPhase)
    }
    
    private var statusTextView: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Text("Preparing Session")
                .font(AppTypography.title3)
                .foregroundStyle(AppColors.textPrimary)
            
            // Cycling status message with fade
            Text(currentStatusMessage)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textTertiary)
                .opacity(statusMessageOpacity)
                .animation(.easeInOut(duration: 0.3), value: statusMessageOpacity)
        }
    }
    
    private var currentStatusMessage: String {
        switch phase {
        case .waitingForKokoro:
            let messages = Constants.SessionPreparation.warmupStatusMessages
            guard !messages.isEmpty else { return "" }
            return messages[statusMessageIndex % messages.count]
            
        case .synthesizing:
            let messages = Constants.SessionPreparation.synthesisStatusMessages
            guard !messages.isEmpty else { return "" }
            return messages[statusMessageIndex % messages.count]
            
        case .complete:
            return "Ready!"
            
        case .kokoroTimeout:
            return "Taking longer than usual..."
            
        case .error:
            return ""
        }
    }
    
    private var smoothProgressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(AppColors.surfaceTertiary)
                    .frame(height: 6)
                
                // Progress fill with smooth animation
                Capsule()
                    .fill(AppColors.accent)
                    .frame(width: max(0, geometry.size.width * displayedProgress), height: 6)
                
                // Threshold marker for large sessions (shows where "Start Now" becomes available)
                if isLargeSession {
                    thresholdMarker(in: geometry)
                }
            }
        }
        .frame(height: 6)
    }
    
    /// Vertical line indicating the "Start Now" threshold position.
    ///
    /// Only shown for large sessions (>30 affirmations).
    /// Position: 15/totalCount into the synthesis phase (15% → 99% range).
    @ViewBuilder
    private func thresholdMarker(in geometry: GeometryProxy) -> some View {
        let immediate = Constants.SessionPreparation.immediateProgress
        let warmupWeight = Constants.SessionPreparation.warmupPhaseWeight
        let synthesisWeight = Constants.SessionPreparation.synthesisPhaseWeight
        let warmupEnd = immediate + warmupWeight  // 15%
        
        // Calculate threshold position within synthesis phase
        let thresholdRatio = CGFloat(Constants.SessionPreparation.readyToStartThreshold) / CGFloat(totalCount)
        let thresholdProgress = warmupEnd + (thresholdRatio * synthesisWeight)
        let xPosition = geometry.size.width * thresholdProgress
        
        Rectangle()
            .fill(Color.white.opacity(0.6))
            .frame(width: 2, height: 12)
            .position(x: xPosition, y: 3)
    }
    
    private var startNowButton: some View {
        Button {
            HapticFeedback.impact(.medium)
            onStartNow()
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                
                Text("Start Now")
                    .font(AppTypography.body.weight(.semibold))
            }
            .foregroundStyle(canStartEarly ? AppColors.backgroundPrimary : AppColors.textTertiary)
            .padding(.horizontal, AppTheme.Spacing.xl)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(
                Capsule()
                    .fill(canStartEarly ? AppColors.accent : AppColors.surfaceTertiary)
            )
            .opacity(canStartEarly ? 1.0 : 0.5)
        }
        .disabled(!canStartEarly)
        .accessibilityLabel(canStartEarly ? "Start session now with \(preparedCount) affirmations ready" : "Waiting for more affirmations")
    }
    
    private var cancelButton: some View {
        Button {
            HapticFeedback.impact(.light)
            onCancel()
        } label: {
            Text("Cancel")
                .font(AppTypography.body.weight(.medium))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(AppColors.surfaceTertiary.opacity(0.8))
                .clipShape(Capsule())
        }
        .accessibilityLabel("Cancel session preparation")
    }
    
    private var accessibilityDescription: String {
        let percentage = Int(displayedProgress * 100)
        return "Preparing session, \(percentage) percent complete, \(preparedCount) of \(totalCount) affirmations ready"
    }
    
    // MARK: - Animation Logic
    
    private func startAnimations() {
        // Start breathing animation
        breathingPhase = 1
        
        // Initialize phase timestamps
        if phase == .waitingForKokoro {
            warmupStartTime = Date()
        } else if phase == .synthesizing {
            synthesisStartTime = Date()
        }
    }
    
    private func handlePhaseChange(from oldPhase: SessionPreparationPhase, to newPhase: SessionPreparationPhase) {
        // Reset status message index to start fresh for new phase
        statusMessageIndex = 0
        statusMessageOpacity = 1.0
        
        switch newPhase {
        case .waitingForKokoro:
            warmupStartTime = Date()
            
        case .synthesizing:
            synthesisStartTime = Date()
            
        case .complete:
            // Animate to 100%
            withAnimation(.easeOut(duration: 0.3)) {
                displayedProgress = 1.0
            }
            
        default:
            break
        }
    }
    
    private func updateSmoothProgress() {
        let targetProgress = calculateTargetProgress()
        
        // Smooth easing toward target (never go backwards)
        let easingFactor = Constants.SessionPreparation.progressEasingFactor
        if targetProgress > displayedProgress {
            displayedProgress += (targetProgress - displayedProgress) * easingFactor
        }
    }
    
    /// Calculates target progress based on current phase and actual synthesis count.
    ///
    /// ## Progress Ranges
    /// - Immediate: 0% → 2%
    /// - Warm-up: 2% → 15%
    /// - Synthesis: 15% → 99% (driven by actual preparedCount)
    /// - Complete: 100%
    private func calculateTargetProgress() -> CGFloat {
        let immediate = Constants.SessionPreparation.immediateProgress
        let warmupWeight = Constants.SessionPreparation.warmupPhaseWeight
        let synthesisWeight = Constants.SessionPreparation.synthesisPhaseWeight
        let maxPreComplete = Constants.SessionPreparation.maxPreCompleteProgress
        
        switch phase {
        case .waitingForKokoro:
            // Time-based progress during warm-up (2% → 15%)
            guard let start = warmupStartTime else { return immediate }
            
            let elapsed = Date().timeIntervalSince(start)
            let estimatedDuration = Constants.SessionPreparation.estimatedKokoroWarmupSeconds
            
            let warmupProgress = min(elapsed / estimatedDuration, 1.0)
            return immediate + (CGFloat(warmupProgress) * warmupWeight)
            
        case .synthesizing:
            // Actual progress only (15% → 99%) - no time-based floor
            let warmupEnd = immediate + warmupWeight  // 15%
            
            // Progress driven purely by actual synthesis count
            let actualProgress = totalCount > 0
                ? CGFloat(preparedCount) / CGFloat(totalCount)
                : 0
            
            let result = warmupEnd + (actualProgress * synthesisWeight)
            return min(result, maxPreComplete)
            
        case .complete:
            return 1.0
            
        case .kokoroTimeout, .error:
            // Freeze at current position
            return displayedProgress
        }
    }
    
    private func cycleStatusMessage() {
        // Only cycle messages during active preparation phases
        guard phase == .waitingForKokoro || phase == .synthesizing else { return }
        
        // Fade out
        withAnimation(.easeOut(duration: 0.3)) {
            statusMessageOpacity = 0
        }
        
        // Change message and fade in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            statusMessageIndex += 1
            withAnimation(.easeIn(duration: 0.3)) {
                statusMessageOpacity = 1.0
            }
        }
    }
}

// MARK: - Previews

#Preview("Waiting for Kokoro") {
    SessionPreparationView(
        phase: .waitingForKokoro,
        preparedCount: 0,
        totalCount: 10,
        canStartEarly: false,
        onStartNow: {},
        onContinueWithSystemVoice: {},
        onRetry: {},
        onCancel: {}
    )
}

#Preview("Synthesizing - Small Session") {
    SessionPreparationView(
        phase: .synthesizing,
        preparedCount: 5,
        totalCount: 10,
        canStartEarly: false,
        onStartNow: {},
        onContinueWithSystemVoice: {},
        onRetry: {},
        onCancel: {}
    )
}

#Preview("Synthesizing - Large Session (Button Disabled)") {
    SessionPreparationView(
        phase: .synthesizing,
        preparedCount: 10,
        totalCount: 50,
        canStartEarly: false,
        onStartNow: {},
        onContinueWithSystemVoice: {},
        onRetry: {},
        onCancel: {}
    )
}

#Preview("Synthesizing - Large Session (Button Enabled)") {
    SessionPreparationView(
        phase: .synthesizing,
        preparedCount: 15,
        totalCount: 50,
        canStartEarly: true,
        onStartNow: {},
        onContinueWithSystemVoice: {},
        onRetry: {},
        onCancel: {}
    )
}

#Preview("Kokoro Timeout") {
    SessionPreparationView(
        phase: .kokoroTimeout,
        preparedCount: 0,
        totalCount: 10,
        canStartEarly: false,
        onStartNow: {},
        onContinueWithSystemVoice: {},
        onRetry: {},
        onCancel: {}
    )
}

#Preview("Error") {
    SessionPreparationView(
        phase: .error(message: "Failed to initialize audio session"),
        preparedCount: 0,
        totalCount: 10,
        canStartEarly: false,
        onStartNow: {},
        onContinueWithSystemVoice: {},
        onRetry: {},
        onCancel: {}
    )
}
