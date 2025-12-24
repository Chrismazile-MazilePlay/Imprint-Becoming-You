//
//  WelcomeView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import SwiftUI

// MARK: - WelcomeView

/// Welcome screen introducing the app's purpose.
///
/// Features:
/// - App branding and tagline
/// - Brief value proposition
/// - "Get Started" button to begin onboarding
struct WelcomeView: View {
    
    // MARK: - Properties
    
    @Bindable var viewModel: OnboardingViewModel
    
    // MARK: - State
    
    @State private var logoOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.8
    @State private var textOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Logo and branding
            VStack(spacing: AppTheme.Spacing.lg) {
                // App icon
                ZStack {
                    Circle()
                        .fill(AppColors.accent.opacity(0.15))
                        .frame(width: 140, height: 140)
                    
                    Circle()
                        .fill(AppColors.accent.opacity(0.25))
                        .frame(width: 110, height: 110)
                    
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 70))
                        .foregroundStyle(AppColors.accent)
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
                
                // App name
                VStack(spacing: AppTheme.Spacing.xs) {
                    Text("Imprint")
                        .font(AppTypography.largeTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text("Becoming You")
                        .font(AppTypography.title3)
                        .foregroundStyle(AppColors.accent)
                }
                .opacity(textOpacity)
            }
            
            Spacer()
            
            // Value proposition
            VStack(spacing: AppTheme.Spacing.md) {
                FeatureRow(
                    icon: "sparkles",
                    title: "Transform Your Identity",
                    description: "Rewire your mind with personalized affirmations"
                )
                
                FeatureRow(
                    icon: "waveform",
                    title: "Your Voice, Your Power",
                    description: "Hear affirmations in your own cloned voice"
                )
                
                FeatureRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Track Your Growth",
                    description: "See your progress with resonance scoring"
                )
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .opacity(textOpacity)
            
            Spacer()
            
            // Get Started button
            VStack(spacing: AppTheme.Spacing.md) {
                Button {
                    viewModel.nextStep()
                } label: {
                    Text("Get Started")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                
                Text("Your journey to becoming you starts now")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.xl)
            .opacity(buttonOpacity)
        }
        .onAppear {
            animateIn()
        }
    }
    
    // MARK: - Animation
    
    private func animateIn() {
        // Logo animation
        withAnimation(AppTheme.Animation.slow.delay(0.2)) {
            logoOpacity = 1
            logoScale = 1
        }
        
        // Text animation
        withAnimation(AppTheme.Animation.standard.delay(0.5)) {
            textOpacity = 1
        }
        
        // Button animation
        withAnimation(AppTheme.Animation.standard.delay(0.8)) {
            buttonOpacity = 1
        }
    }
}

// MARK: - FeatureRow

/// A row displaying a feature with icon and description
struct FeatureRow: View {
    
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // Icon
            ZStack {
                Circle()
                    .fill(AppColors.accent.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
            }
            
            // Text
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(title)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                
                Text(description)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
            }
            
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("Welcome View") {
    WelcomeView(viewModel: OnboardingViewModel())
        .background(AppColors.backgroundPrimary)
}

#Preview("Feature Row") {
    VStack(spacing: 16) {
        FeatureRow(
            icon: "sparkles",
            title: "Transform Your Identity",
            description: "Rewire your mind with personalized affirmations"
        )
        
        FeatureRow(
            icon: "waveform",
            title: "Your Voice, Your Power",
            description: "Hear affirmations in your own cloned voice"
        )
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}
