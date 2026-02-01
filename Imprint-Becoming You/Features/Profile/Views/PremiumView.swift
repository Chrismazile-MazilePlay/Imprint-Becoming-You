//
//  PremiumView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/1/26.
//

import SwiftUI

// MARK: - PremiumView

/// Placeholder view for premium upsell and subscription management.
///
/// This view will be expanded to include:
/// - Feature comparison (Free vs Premium)
/// - Subscription plans and pricing
/// - Purchase flow integration
/// - Restore purchases option
///
/// ## Navigation
/// This view is pushed onto the Profile navigation stack.
struct PremiumView: View {
    
    // MARK: - Environment
    
    @Environment(\.appState) private var appState
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    // Header
                    headerSection
                    
                    // Features
                    featuresSection
                    
                    // Pricing (placeholder)
                    pricingSection
                    
                    // Footer
                    footerSection
                }
                .padding(AppTheme.Spacing.lg)
            }
        }
        .navigationTitle("Premium")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Star icon
            Image(systemName: "star.fill")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .accessibilityHidden(true)
            
            Text("Unlock Your Full Potential")
                .font(AppTypography.title2)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            
            Text("Get unlimited access to all features")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.vertical, AppTheme.Spacing.lg)
    }
    
    // MARK: - Features Section
    
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("PREMIUM FEATURES")
                .font(AppTypography.caption2)
                .fontWeight(.medium)
                .tracking(1.2)
                .foregroundStyle(AppColors.textTertiary)
            
            VStack(spacing: AppTheme.Spacing.sm) {
                featureRow(icon: "infinity", title: "Unlimited Sessions", description: "Practice as much as you want")
                featureRow(icon: "waveform", title: "All Voice Options", description: "Access to all neural voices")
                featureRow(icon: "icloud", title: "Cloud Sync", description: "Sync across all your devices")
                featureRow(icon: "chart.line.uptrend.xyaxis", title: "Advanced Analytics", description: "Detailed progress insights")
                featureRow(icon: "person.2", title: "Family Sharing", description: "Share with up to 5 family members")
            }
            .padding(AppTheme.Spacing.md)
            .background(AppColors.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
        }
    }
    
    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.yellow)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                
                Text(description)
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
            }
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppColors.success)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(description)")
    }
    
    // MARK: - Pricing Section
    
    private var pricingSection: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Annual plan
            pricingCard(
                title: "Annual",
                price: "$49.99",
                period: "per year",
                savings: "Save 58%",
                isPopular: true
            )
            
            // Monthly plan
            pricingCard(
                title: "Monthly",
                price: "$9.99",
                period: "per month",
                savings: nil,
                isPopular: false
            )
        }
    }
    
    private func pricingCard(
        title: String,
        price: String,
        period: String,
        savings: String?,
        isPopular: Bool
    ) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            if isPopular {
                Text("MOST POPULAR")
                    .font(AppTypography.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .background(AppColors.accent)
                    .clipShape(Capsule())
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    if let savings = savings {
                        Text(savings)
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.success)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(price)
                        .font(AppTypography.title3)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text(period)
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .padding(AppTheme.Spacing.md)
            .background(AppColors.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                    .strokeBorder(
                        isPopular ? AppColors.accent : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .opacity(0.6) // Disabled state
    }
    
    // MARK: - Footer Section
    
    private var footerSection: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Subscribe button (placeholder)
            Button {
                // TODO: Implement purchase flow
            } label: {
                Text("Continue")
                    .font(AppTypography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(AppTheme.Spacing.md)
                    .background(AppColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
            }
            .disabled(true) // Placeholder
            .opacity(0.5)
            
            // Restore purchases
            Button {
                // TODO: Implement restore
            } label: {
                Text("Restore Purchases")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .disabled(true) // Placeholder
            
            // Legal text
            Text("Subscriptions will be charged to your Apple ID. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period.")
                .font(AppTypography.caption2)
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
            
            // Coming soon badge
            Text("Subscriptions coming soon")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(AppColors.surfaceTertiary)
                .clipShape(Capsule())
        }
        .padding(.top, AppTheme.Spacing.lg)
    }
}

// MARK: - Previews

#Preview("Premium View") {
    NavigationStack {
        PremiumView()
    }
    .previewEnvironment()
}
