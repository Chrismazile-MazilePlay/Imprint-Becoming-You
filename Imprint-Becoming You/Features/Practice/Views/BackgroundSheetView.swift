//
//  BackgroundSheetView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/17/26.
//

import SwiftUI

// MARK: - BackgroundSheetView

/// Sheet presenting background selection options with a tabbed interface.
///
/// Uses `TabbedPageView` to display two tabs:
/// - **Colors**: Grid of solid color backgrounds + morphing gradient.
/// - **Images**: Placeholder for future image background support.
///
/// Background changes apply **immediately** on tap — no pending/save pattern.
/// The practice view updates reactively because it reads
/// `appState.userProfile?.backgroundStyle` on every body evaluation.
///
/// ## Presentation
///
/// Present as a sheet with medium/large detents:
/// ```swift
/// .sheet(isPresented: $showingBackgroundSheet) {
///     BackgroundSheetView()
/// }
/// ```
struct BackgroundSheetView: View {

    // MARK: - Environment

    @Environment(\.appState) private var appState
    @Environment(\.modelContext) private var modelContext

    // MARK: - Computed

    /// The currently active background style from the user profile.
    private var currentStyle: BackgroundStyle {
        appState.userProfile?.backgroundStyle ?? .morphingGradient
    }

    // MARK: - Body

    var body: some View {
        TabbedPageView {
            TabLabel(title: "Colors", symbolImage: "paintbrush.fill")
            TabLabel(title: "Images", symbolImage: "photo.fill")
        } pages: {
            colorsTab
            imagesTab
        }
        .background(AppColors.backgroundPrimary)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Colors Tab

    /// Grid of all background style options with immediate-apply behavior.
    private var colorsTab: some View {
        LazyVGrid(columns: gridColumns, spacing: 16) {
            ForEach(BackgroundStyle.allCases) { style in
                BackgroundPreviewCard(
                    style: style,
                    isSelected: currentStyle == style
                )
                .onTapGesture {
                    selectStyle(style)
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
    }

    // MARK: - Images Tab

    /// Placeholder for future image background support.
    private var imagesTab: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Spacer()

            Image(systemName: "photo.badge.plus")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppColors.textTertiary)

            Text("Coming soon")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.textTertiary)

            Text("Image backgrounds will be available in a future update.")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textTertiary.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.Spacing.xl)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Grid Columns

    /// Adaptive grid layout: 2 columns on most devices.
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 16)]
    }

    // MARK: - Selection

    /// Immediately applies the selected background style.
    ///
    /// Updates the user profile and persists to SwiftData. The practice
    /// view background updates reactively.
    private func selectStyle(_ style: BackgroundStyle) {
        guard style != currentStyle else { return }

        appState.userProfile?.backgroundStyleRawValue = style.rawValue

        // Persist to SwiftData
        try? modelContext.save()

        // Haptic feedback
        HapticFeedback.selection()

        #if DEBUG
        print("BackgroundSheetView: Applied \(style.displayName)")
        #endif
    }
}

// MARK: - Previews

#Preview("Background Sheet") {
    BackgroundSheetView()
        .previewEnvironment()
}
