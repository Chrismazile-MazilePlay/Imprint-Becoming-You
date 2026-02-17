//
//  BackgroundSheetView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/17/26.
//

import SwiftUI

// MARK: - BackgroundSheetView

/// Sheet presenting background selection options with a tabbed interface and
/// a large-to-inline title transition.
///
/// Uses `TabbedPageView` with a header slot containing the large "Background"
/// title. A fixed overlay bar at the top provides an X dismiss button (always
/// visible) and an inline title that fades in as the large title scrolls away.
///
/// ## Tabs
/// - **Colors**: Grid of solid color backgrounds + morphing gradient.
/// - **Images**: Placeholder for future image background support.
///
/// Background changes apply **immediately** on tap — no pending/save pattern.
/// The practice view updates reactively because it reads
/// `appState.userProfile?.backgroundStyle` on every body evaluation.
///
/// ## Presentation
///
/// Present as a nearly full-screen sheet:
/// ```swift
/// .sheet(isPresented: $showingBackgroundSheet) {
///     BackgroundSheetView()
/// }
/// ```
struct BackgroundSheetView: View {

    // MARK: - Constants

    /// Height of the fixed navigation bar containing X button and inline title.
    private let fixedBarHeight: CGFloat = 52

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appState) private var appState
    @Environment(\.modelContext) private var modelContext

    // MARK: - State

    /// Active tab's vertical scroll offset, reported by `TabbedPageView`.
    @State private var scrollOffsetY: CGFloat = 0

    /// Measured height of the full header (spacer + large title).
    @State private var largeTitleHeight: CGFloat = 0

    // MARK: - Computed

    /// The currently active background style from the user profile.
    private var currentStyle: BackgroundStyle {
        appState.userProfile?.backgroundStyle ?? .morphingGradient
    }

    /// Progress of the large title collapsing behind the fixed bar (0 = at rest, 1 = fully collapsed).
    private var titleCollapseProgress: CGFloat {
        let effectiveRange = largeTitleHeight - fixedBarHeight
        guard effectiveRange > 0 else { return 0 }
        return min(max(scrollOffsetY / effectiveRange, 0), 1)
    }

    /// Opacity of the inline title in the fixed bar. Fades in during the last 30% of collapse.
    private var inlineTitleOpacity: CGFloat {
        let fadeStart: CGFloat = 0.7
        guard titleCollapseProgress > fadeStart else { return 0 }
        return (titleCollapseProgress - fadeStart) / (1.0 - fadeStart)
    }

    /// Opacity of the fixed bar background. Transitions from transparent to opaque.
    private var fixedBarBackgroundOpacity: CGFloat {
        let fadeStart: CGFloat = 0.3
        guard titleCollapseProgress > fadeStart else { return 0 }
        return min((titleCollapseProgress - fadeStart) / (1.0 - fadeStart), 1)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Tabbed content with large title header
            TabbedPageView(
                onActiveScrollOffsetChange: { offset in
                    scrollOffsetY = offset
                }
            ) {
                largeTitleHeader
            } labels: {
                TabLabel(title: "Colors", symbolImage: "paintbrush.fill")
                TabLabel(title: "Images", symbolImage: "photo.fill")
            } pages: {
                colorsTab
                imagesTab
            }

            // Fixed overlay: X button + inline title
            fixedNavigationBar
        }
        .background(AppColors.backgroundPrimary)
        .presentationDetents([.fraction(0.999)])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Large Title Header

    /// Scrollable header containing a spacer (for the fixed bar) and the large title.
    ///
    /// Placed in TabbedPageView's header slot — scrolls naturally with content.
    /// When the large title scrolls behind the fixed bar, the inline title fades in.
    private var largeTitleHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Reserve space so content doesn't hide behind the fixed navigation bar
            Color.clear.frame(height: fixedBarHeight)

            Text("Background")
                .font(AppTypography.largeTitle)
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.top, AppTheme.Spacing.sm)
                .padding(.bottom, AppTheme.Spacing.md)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: { newValue in
            largeTitleHeight = newValue
        }
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Fixed Navigation Bar

    /// Pinned bar at the top with X dismiss button and inline title.
    ///
    /// The X button is always visible. The inline title and opaque background
    /// fade in as the large title scrolls out of view.
    private var fixedNavigationBar: some View {
        HStack {
            // X dismiss button (top-left, always visible)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .accessibilityLabel("Dismiss")

            Spacer()

            // Inline title (fades in as large title scrolls away)
            Text("Background")
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)
                .opacity(inlineTitleOpacity)

            Spacer()

            // Invisible spacer to balance X button width
            Color.clear
                .frame(width: 28, height: 28)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(height: fixedBarHeight)
        .background(
            AppColors.backgroundPrimary
                .opacity(fixedBarBackgroundOpacity)
        )
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
