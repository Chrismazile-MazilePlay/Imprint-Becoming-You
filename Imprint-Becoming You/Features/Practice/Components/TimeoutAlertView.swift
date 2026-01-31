//
//  TimeoutAlertView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/9/26.
//

import SwiftUI

// MARK: - TimeoutAlertView

/// Centered alert displayed when word detection times out during listening.
///
/// Presented when no matching words are detected for the timeout duration
/// (default 10 seconds). Gives user options to:
/// - **Retry**: Try speaking the affirmation again
/// - **Skip**: Move to the next affirmation (0 score recorded)
/// - **Exit**: Return to home/browse mode
///
/// ## Usage
/// ```swift
/// TimeoutAlertView(
///     affirmationText: "I am confident and capable",
///     onRetry: { store.send(.retryListening) },
///     onSkip: { store.send(.skipAffirmation) },
///     onExit: { store.send(.exitSession) }
/// )
/// ```
struct TimeoutAlertView: View {
    
    // MARK: - Properties
    
    /// The affirmation text that timed out
    let affirmationText: String
    
    /// Action when user taps Retry
    let onRetry: () -> Void
    
    /// Action when user taps Skip
    let onSkip: () -> Void
    
    /// Action when user taps Exit
    let onExit: () -> Void
    
    // MARK: - State
    
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    // Tapping outside dismisses (retries)
                    onRetry()
                }
                .accessibilityHidden(true)
            
            // Alert card
            VStack(spacing: AppTheme.Spacing.lg) {
                // Icon
                ZStack {
                    Circle()
                        .fill(AppColors.warning.opacity(0.15))
                        .frame(width: 64, height: 64)
                    
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(AppColors.warning)
                }
                .accessibilityHidden(true)
                
                // Title
                Text("Listening Timed Out")
                    .font(AppTypography.title3)
                    .foregroundStyle(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                
                // Message
                Text("We didn't detect speech matching the affirmation. Would you like to try again?")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Affirmation preview
                Text("\"\(affirmationText)\"")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textTertiary)
                    .italic()
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .accessibilityLabel("Affirmation: \(affirmationText)")
                
                // Action buttons
                VStack(spacing: AppTheme.Spacing.sm) {
                    // Retry - Primary action
                    Button(action: {
                        HapticFeedback.selection()
                        onRetry()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Try Again")
                        }
                        .font(AppTypography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.md)
                        .background(AppColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
                    }
                    .accessibilityLabel("Try again")
                    .accessibilityHint("Retry speaking the affirmation")
                    
                    // Skip - Secondary action
                    Button(action: {
                        HapticFeedback.selection()
                        onSkip()
                    }) {
                        HStack {
                            Image(systemName: "forward.fill")
                            Text("Skip")
                        }
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.md)
                        .background(AppColors.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
                    }
                    .accessibilityLabel("Skip")
                    .accessibilityHint("Skip this affirmation and move to the next one")
                    
                    // Exit - Tertiary action
                    Button(action: {
                        HapticFeedback.selection()
                        onExit()
                    }) {
                        Text("Exit Session")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(.top, AppTheme.Spacing.md)
                    .accessibilityLabel("Exit session")
                    .accessibilityHint("End the current practice session")
                }
            }
            .padding(AppTheme.Spacing.xl)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                    .fill(AppColors.backgroundPrimary)
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            )
            .scaleEffect(scale)
            .opacity(opacity)
            .accessibilityElement(children: .contain)
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                scale = 1.0
                opacity = 1.0
            }
            HapticFeedback.notification(.warning)
        }
    }
}

// MARK: - Timeout Alert Modifier

extension View {
    
    /// Presents timeout alert as an overlay
    func timeoutAlert(
        isPresented: Binding<Bool>,
        affirmationText: String,
        onRetry: @escaping () -> Void,
        onSkip: @escaping () -> Void,
        onExit: @escaping () -> Void
    ) -> some View {
        self.overlay {
            if isPresented.wrappedValue {
                TimeoutAlertView(
                    affirmationText: affirmationText,
                    onRetry: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isPresented.wrappedValue = false
                        }
                        onRetry()
                    },
                    onSkip: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isPresented.wrappedValue = false
                        }
                        onSkip()
                    },
                    onExit: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isPresented.wrappedValue = false
                        }
                        onExit()
                    }
                )
                .transition(.opacity)
            }
        }
    }
}

// MARK: - Permission Denied Alert

/// Alert shown when microphone or speech recognition permission is denied
struct PermissionDeniedAlertView: View {
    
    // MARK: - Properties
    
    /// Type of permission that was denied
    let permissionType: PermissionType
    
    /// Action to open Settings app
    let onOpenSettings: () -> Void
    
    /// Action to continue without permission
    let onContinue: () -> Void
    
    enum PermissionType {
        case microphone
        case speechRecognition
        case both
        
        var title: String {
            switch self {
            case .microphone:
                return "Microphone Access Required"
            case .speechRecognition:
                return "Speech Recognition Required"
            case .both:
                return "Permissions Required"
            }
        }
        
        var message: String {
            switch self {
            case .microphone:
                return "Imprint needs microphone access to listen to your affirmations and calculate your Resonance Score."
            case .speechRecognition:
                return "Imprint needs speech recognition to understand what you're saying and provide feedback."
            case .both:
                return "Imprint needs microphone and speech recognition access to analyze your affirmations."
            }
        }
        
        var icon: String {
            switch self {
            case .microphone:
                return "mic.slash.fill"
            case .speechRecognition:
                return "waveform.badge.exclamationmark"
            case .both:
                return "exclamationmark.shield.fill"
            }
        }
    }
    
    // MARK: - State
    
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            
            // Alert card
            VStack(spacing: AppTheme.Spacing.lg) {
                // Icon
                ZStack {
                    Circle()
                        .fill(AppColors.error.opacity(0.15))
                        .frame(width: 64, height: 64)
                    
                    Image(systemName: permissionType.icon)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(AppColors.error)
                }
                .accessibilityHidden(true)
                
                // Title
                Text(permissionType.title)
                    .font(AppTypography.title3)
                    .foregroundStyle(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                
                // Message
                Text(permissionType.message)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Action buttons
                VStack(spacing: AppTheme.Spacing.sm) {
                    // Open Settings - Primary action
                    Button(action: {
                        HapticFeedback.selection()
                        onOpenSettings()
                    }) {
                        HStack {
                            Image(systemName: "gear")
                            Text("Open Settings")
                        }
                        .font(AppTypography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.md)
                        .background(AppColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
                    }
                    .accessibilityLabel("Open Settings")
                    .accessibilityHint("Open the Settings app to enable permissions")
                    
                    // Continue without - Secondary action
                    Button(action: {
                        HapticFeedback.selection()
                        onContinue()
                    }) {
                        Text("Continue in Read-Only Mode")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(.top, AppTheme.Spacing.xs)
                    .accessibilityLabel("Continue in read-only mode")
                    .accessibilityHint("Use the app without voice features")
                }
            }
            .padding(AppTheme.Spacing.xl)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                    .fill(AppColors.backgroundPrimary)
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            )
            .scaleEffect(scale)
            .opacity(opacity)
            .accessibilityElement(children: .contain)
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                scale = 1.0
                opacity = 1.0
            }
            HapticFeedback.notification(.error)
        }
    }
}

// MARK: - Permission Alert Modifier

extension View {
    
    /// Presents permission denied alert as an overlay
    func permissionDeniedAlert(
        isPresented: Binding<Bool>,
        permissionType: PermissionDeniedAlertView.PermissionType,
        onOpenSettings: @escaping () -> Void,
        onContinue: @escaping () -> Void
    ) -> some View {
        self.overlay {
            if isPresented.wrappedValue {
                PermissionDeniedAlertView(
                    permissionType: permissionType,
                    onOpenSettings: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isPresented.wrappedValue = false
                        }
                        onOpenSettings()
                    },
                    onContinue: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isPresented.wrappedValue = false
                        }
                        onContinue()
                    }
                )
                .transition(.opacity)
            }
        }
    }
}

// MARK: - Previews

#Preview("Timeout Alert") {
    ZStack {
        AppColors.backgroundPrimary
            .ignoresSafeArea()
        
        TimeoutAlertView(
            affirmationText: "I am confident and capable of achieving my goals",
            onRetry: { print("Retry tapped") },
            onSkip: { print("Skip tapped") },
            onExit: { print("Exit tapped") }
        )
    }
}

#Preview("Permission Denied - Microphone") {
    ZStack {
        AppColors.backgroundPrimary
            .ignoresSafeArea()
        
        PermissionDeniedAlertView(
            permissionType: .microphone,
            onOpenSettings: { print("Open Settings") },
            onContinue: { print("Continue") }
        )
    }
}

#Preview("Permission Denied - Both") {
    ZStack {
        AppColors.backgroundPrimary
            .ignoresSafeArea()
        
        PermissionDeniedAlertView(
            permissionType: .both,
            onOpenSettings: { print("Open Settings") },
            onContinue: { print("Continue") }
        )
    }
}
