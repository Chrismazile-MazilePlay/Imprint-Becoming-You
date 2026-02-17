//
//  TabbedPageView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/17/26.
//

import SwiftUI

// MARK: - TabLabel

/// Defines a single tab in a `TabbedPageView`.
///
/// Each label has a title (used as tab text and unique ID) and an SF Symbol
/// image (used when `displaysSymbols` is enabled).
struct TabLabel {
    var title: String
    var symbolImage: String
}

// MARK: - TabLabelBuilder

/// Result builder for declaring `TabLabel` arrays in a trailing-closure style.
///
/// ```swift
/// TabbedPageView {
///     TabLabel(title: "Colors", symbolImage: "paintbrush.fill")
///     TabLabel(title: "Images", symbolImage: "photo.fill")
/// } pages: { ... }
/// ```
@resultBuilder
struct TabLabelBuilder {
    static func buildBlock(_ components: TabLabel...) -> [TabLabel] {
        components.compactMap { $0 }
    }
}

// MARK: - TabbedPageView

/// A reusable tabbed content viewer with horizontal paging and a pinned tab bar.
///
/// Adapted from the InstagramProfileScroll pattern. Each tab has its own vertical
/// `ScrollView` and the tab bar pins at the top using `LazyVStack(pinnedViews:)`.
///
/// ## Header
///
/// The header is **optional**. When provided, it sticks at the top (negating
/// horizontal offset via `.visualEffect`) and cross-tab scroll positions sync
/// so tabs share the same vertical offset while the header is visible. When no
/// header is provided (the default), all header-related logic is omitted.
///
/// ## Design
///
/// - Tab bar uses `AppColors` and `AppTypography` for Imprint's dark theme.
/// - Animated capsule indicator tracks scroll progress.
/// - `TabViewPanGesture` prevents accidental tab switches during vertical scrolling.
///
/// ## Usage (without header)
///
/// ```swift
/// TabbedPageView {
///     TabLabel(title: "Colors", symbolImage: "paintbrush.fill")
///     TabLabel(title: "Images", symbolImage: "photo.fill")
/// } pages: {
///     ColorsGridView()
///     ImagesGridView()
/// }
/// ```
///
/// ## Usage (with header)
///
/// ```swift
/// TabbedPageView {
///     ProfileHeaderView()
/// } labels: {
///     TabLabel(title: "Posts", symbolImage: "square.grid.3x3.fill")
///     TabLabel(title: "Reels", symbolImage: "photo.stack.fill")
/// } pages: {
///     PostsGridView()
///     ReelsGridView()
/// }
/// ```
struct TabbedPageView<Header: View, Pages: View>: View {

    // MARK: - Properties

    /// Whether to display SF Symbols instead of text in the tab bar.
    var displaysSymbols: Bool = false

    /// Optional sticky header above the tab content.
    var header: Header?

    /// Tab definitions (one per page).
    var labels: [TabLabel]

    /// Tab content views (must match label count).
    var pages: Pages

    // MARK: - State

    /// Currently active tab, identified by `TabLabel.title`.
    @State private var activeTab: String?

    /// Measured height of the header view (only tracked when header is present).
    @State private var headerHeight: CGFloat = 0

    /// Per-tab vertical scroll offsets for cross-tab synchronization.
    @State private var scrollOffsetsY: [CGFloat]

    /// Per-tab scroll positions for programmatic scroll control.
    @State private var scrollPositions: [ScrollPosition]

    /// Locks horizontal scroll during vertical drag to prevent accidental tab switches.
    @State private var mainScrollDisabled: Bool = false

    /// Current scroll animation phase (used to disable hit testing during animation).
    @State private var mainScrollPhase: ScrollPhase = .idle

    /// Horizontal scroll offset for tab indicator progress calculation.
    @State private var mainScrollOffsetX: CGFloat = .zero

    /// Container width for tab indicator progress normalization.
    @State private var mainContainerSize: CGSize = .zero

    // MARK: - Computed

    /// Whether a header view is present.
    private var hasHeader: Bool {
        header != nil
    }

    // MARK: - Initialization (with header)

    /// Creates a tabbed page view with a sticky header.
    ///
    /// - Parameters:
    ///   - displaysSymbols: Show SF Symbols in the tab bar instead of text.
    ///   - header: A sticky header view pinned above the tab content.
    ///   - labels: Tab definitions built via `TabLabelBuilder`.
    ///   - pages: Tab content views built via `@ViewBuilder`.
    init(
        displaysSymbols: Bool = false,
        @ViewBuilder header: @escaping () -> Header,
        @TabLabelBuilder labels: @escaping () -> [TabLabel],
        @ViewBuilder pages: @escaping () -> Pages
    ) {
        self.displaysSymbols = displaysSymbols
        self.header = header()
        self.labels = labels()
        self.pages = pages()

        let count = labels().count
        self._scrollPositions = .init(initialValue: .init(repeating: .init(), count: count))
        self._scrollOffsetsY = .init(initialValue: .init(repeating: .zero, count: count))
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    Group(subviews: pages) { collection in
                        if collection.count != labels.count {
                            Text("Tab views and labels count must match.")
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textTertiary)
                                .frame(width: size.width, height: size.height)
                        } else {
                            ForEach(labels, id: \.title) { label in
                                pageScrollView(label: label, size: size, collection: collection)
                            }
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $activeTab)
            .scrollIndicators(.hidden)
            .scrollDisabled(mainScrollDisabled)
            .allowsHitTesting(mainScrollPhase == .idle)
            .onScrollPhaseChange { _, newPhase in
                mainScrollPhase = newPhase
            }
            .onScrollGeometryChange(for: CGFloat.self, of: {
                $0.contentOffset.x + $0.contentInsets.leading
            }, action: { _, newValue in
                mainScrollOffsetX = newValue
            })
            .onScrollGeometryChange(for: CGSize.self, of: {
                $0.containerSize
            }, action: { _, newValue in
                mainContainerSize = newValue
            })
            .mask {
                Rectangle()
                    .ignoresSafeArea(.all, edges: .bottom)
            }
            .onAppear {
                guard activeTab == nil else { return }
                activeTab = labels.first?.title
            }
        }
    }

    // MARK: - Page Scroll View

    /// A single tab's vertical scroll view containing the header (if present),
    /// pinned tab bar, and tab content.
    @ViewBuilder
    private func pageScrollView(
        label: PageLabel,
        size: CGSize,
        collection: SubviewsCollection
    ) -> some View {
        // Use the renamed local type to avoid ambiguity
        pageScrollViewContent(label: label, size: size, collection: collection)
    }

    @ViewBuilder
    private func pageScrollViewContent(
        label: PageLabel,
        size: CGSize,
        collection: SubviewsCollection
    ) -> some View {
        let index = labels.firstIndex(where: { $0.title == label.title }) ?? 0

        ScrollView(.vertical) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                // Header section (only when header is provided)
                if hasHeader {
                    headerSection(label: label)
                }

                // Pinned tab bar + tab content
                Section {
                    collection[index]
                        // Ensure minimum height so content is scrollable even when sparse
                        .frame(minHeight: hasHeader ? size.height - 40 : size.height - 40, alignment: .top)
                } header: {
                    tabBarSection(label: label)
                }
            }
        }
        .onScrollGeometryChange(for: CGFloat.self, of: {
            $0.contentOffset.y + $0.contentInsets.top
        }, action: { _, newValue in
            scrollOffsetsY[index] = newValue

            if hasHeader && newValue < 0 {
                resetScrollViews(label)
            }
        })
        .scrollPosition($scrollPositions[index])
        .onScrollPhaseChange { _, newPhase in
            if hasHeader {
                let offsetY = scrollOffsetsY[index]
                let maxOffset = min(offsetY, headerHeight)

                if newPhase == .idle && maxOffset <= headerHeight {
                    updateOtherScrollViews(label, to: maxOffset)
                }
            }

            // Fail-safe: re-enable horizontal scroll if it got stuck
            if newPhase == .idle && mainScrollDisabled {
                mainScrollDisabled = false
            }
        }
        .frame(width: size.width)
        .scrollClipDisabled()
        .zIndex(activeTab == label.title ? 1000 : 0)
    }

    // MARK: - Header Section

    /// Renders the sticky header for the active tab, or a spacer for inactive tabs.
    @ViewBuilder
    private func headerSection(label: PageLabel) -> some View {
        ZStack {
            if activeTab == label.title, let header {
                header
                    .visualEffect { content, proxy in
                        content
                            .offset(x: -proxy.frame(in: .scrollView(axis: .horizontal)).minX)
                    }
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.height
                    } action: { newValue in
                        headerHeight = newValue
                    }
                    .transition(.identity)
            } else {
                Rectangle()
                    .foregroundStyle(.clear)
                    .frame(height: headerHeight)
                    .transition(.identity)
            }
        }
        .contentShape(.rect)
        .gesture(horizontalScrollDisableGesture)
    }

    // MARK: - Tab Bar Section

    /// The pinned tab bar with animated indicator.
    @ViewBuilder
    private func tabBarSection(label: PageLabel) -> some View {
        ZStack {
            if activeTab == label.title {
                tabBar
                    .visualEffect { content, proxy in
                        content
                            .offset(x: -proxy.frame(in: .scrollView(axis: .horizontal)).minX)
                    }
                    .transition(.identity)
            } else {
                Rectangle()
                    .foregroundStyle(.clear)
                    .frame(height: 44)
                    .transition(.identity)
            }
        }
        .contentShape(.rect)
        .gesture(horizontalScrollDisableGesture)
    }

    // MARK: - Tab Bar

    /// Custom tab bar with text/symbol labels and animated capsule indicator.
    private var tabBar: some View {
        let progress = max(min(mainScrollOffsetX / mainContainerSize.width, CGFloat(labels.count - 1)), 0)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                ForEach(labels, id: \.title) { label in
                    Group {
                        if displaysSymbols {
                            Image(systemName: label.symbolImage)
                                .font(.system(size: 16, weight: .medium))
                        } else {
                            Text(label.title)
                                .font(AppTypography.subheadline.weight(.medium))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(activeTab == label.title ? AppColors.textPrimary : AppColors.textSecondary)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            activeTab = label.title
                        }
                    }
                    .accessibilityLabel(label.title)
                    .accessibilityAddTraits(activeTab == label.title ? .isSelected : [])
                }
            }
            .frame(maxHeight: .infinity)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(AppColors.textTertiary.opacity(0.3))
                    .frame(height: 1)

                Capsule()
                    .fill(AppColors.accent)
                    .frame(width: 50, height: 3)
                    .containerRelativeFrame(.horizontal) { value, _ in
                        value / CGFloat(labels.count)
                    }
                    .visualEffect { content, proxy in
                        content
                            .offset(x: proxy.size.width * progress, y: -1)
                    }
            }
        }
        .frame(height: 44)
        .background(AppColors.backgroundPrimary)
    }

    // MARK: - Gesture

    /// Disables horizontal scroll during vertical drag to prevent accidental tab switches.
    private var horizontalScrollDisableGesture: some UIGestureRecognizerRepresentable {
        TabViewPanGesture { gesture in
            switch gesture.state {
            case .began, .changed:
                mainScrollDisabled = true
            case .ended, .cancelled, .failed:
                mainScrollDisabled = false
            default:
                break
            }
        }
    }

    // MARK: - Scroll Synchronization (header mode only)

    /// Resets all non-active tabs to the top when the active tab bounces (overscroll).
    private func resetScrollViews(_ from: PageLabel) {
        for index in labels.indices {
            let label = labels[index]
            if label.title != from.title {
                scrollPositions[index].scrollTo(y: 0)
            }
        }
    }

    /// Syncs non-active tabs to match the active tab's scroll position.
    ///
    /// Only syncs while within the header region. Once the header is fully
    /// scrolled away, tabs scroll independently.
    private func updateOtherScrollViews(_ from: PageLabel, to offset: CGFloat) {
        for index in labels.indices {
            let label = labels[index]
            let currentOffset = scrollOffsetsY[index]
            let wantsUpdate = currentOffset < headerHeight || offset < headerHeight

            if wantsUpdate && label.title != from.title {
                scrollPositions[index].scrollTo(y: offset)
            }
        }
    }
}

// MARK: - Convenience Init (no header)

extension TabbedPageView where Header == EmptyView {

    /// Creates a tabbed page view without a header.
    ///
    /// - Parameters:
    ///   - displaysSymbols: Show SF Symbols in the tab bar instead of text.
    ///   - labels: Tab definitions built via `TabLabelBuilder`.
    ///   - pages: Tab content views built via `@ViewBuilder`.
    init(
        displaysSymbols: Bool = false,
        @TabLabelBuilder labels: @escaping () -> [TabLabel],
        @ViewBuilder pages: @escaping () -> Pages
    ) {
        self.displaysSymbols = displaysSymbols
        self.header = nil
        self.labels = labels()
        self.pages = pages()

        let count = labels().count
        self._scrollPositions = .init(initialValue: .init(repeating: .init(), count: count))
        self._scrollOffsetsY = .init(initialValue: .init(repeating: .zero, count: count))
    }
}

// MARK: - TabViewPanGesture

/// Pan gesture recognizer that allows simultaneous recognition with other gestures.
///
/// Used by `TabbedPageView` to detect vertical drags on the header and tab bar
/// areas, temporarily disabling horizontal scroll to prevent accidental tab switches.
///
/// Unlike the app's existing `PanGesture` (which is horizontal-only for VerticalPager),
/// this gesture fires for all directions so it can lock horizontal scroll during
/// any vertical interaction.
private struct TabViewPanGesture: UIGestureRecognizerRepresentable {

    var handle: (UIPanGestureRecognizer) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let gesture = UIPanGestureRecognizer()
        gesture.delegate = context.coordinator
        return gesture
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) { }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        handle(recognizer)
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

// MARK: - PageLabel Convenience

/// Type alias bridging `TabLabel` to the internal `PageLabel` name used by
/// the scroll view methods. Keeps the public API clean while the internals
/// reference the original pattern's naming.
private typealias PageLabel = TabLabel

// MARK: - Previews

#Preview("TabbedPageView - No Header") {
    TabbedPageView {
        TabLabel(title: "Colors", symbolImage: "paintbrush.fill")
        TabLabel(title: "Images", symbolImage: "photo.fill")
    } pages: {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                ForEach(0..<12) { i in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hue: Double(i) / 12.0, saturation: 0.6, brightness: 0.3))
                        .frame(height: 120)
                }
            }
            .padding()
        }

        VStack {
            Spacer()
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textTertiary)
            Text("Coming soon")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.textTertiary)
            Spacer()
        }
    }
    .background(AppColors.backgroundPrimary)
}

#Preview("TabbedPageView - With Header") {
    TabbedPageView {
        VStack(spacing: 16) {
            Circle()
                .fill(AppColors.accent.opacity(0.2))
                .frame(width: 80, height: 80)
            Text("Profile Header")
                .font(AppTypography.title2)
                .foregroundStyle(AppColors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(AppColors.backgroundPrimary)
    } labels: {
        TabLabel(title: "Posts", symbolImage: "square.grid.3x3.fill")
        TabLabel(title: "Saved", symbolImage: "bookmark.fill")
    } pages: {
        LazyVStack(spacing: 4) {
            ForEach(0..<20) { i in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 120)
            }
        }
        .padding(2)

        VStack {
            Spacer()
            Text("No saved items")
                .foregroundStyle(AppColors.textTertiary)
            Spacer()
        }
    }
    .background(AppColors.backgroundPrimary)
}

#Preview("TabbedPageView - Symbols") {
    TabbedPageView(displaysSymbols: true) {
        TabLabel(title: "Grid", symbolImage: "square.grid.3x3.fill")
        TabLabel(title: "List", symbolImage: "list.bullet")
        TabLabel(title: "Map", symbolImage: "map.fill")
    } pages: {
        Color.red.opacity(0.1)
        Color.green.opacity(0.1)
        Color.blue.opacity(0.1)
    }
    .background(AppColors.backgroundPrimary)
}
