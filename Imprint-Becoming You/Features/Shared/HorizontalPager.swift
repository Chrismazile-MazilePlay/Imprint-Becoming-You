//
//  HorizontalPager.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/1/26.
//

import SwiftUI

// MARK: - HorizontalPager

/// A custom horizontal paging container with controllable gesture behavior.
///
/// Unlike `TabView` with `.page` style, this pager allows complete control over
/// when horizontal swipe gestures are active. When gestures are disabled,
/// `NavigationStack`'s back gesture can take priority without conflict.
///
/// ## Architecture
/// All pages remain in the view hierarchy at all times—only their horizontal
/// offset changes. This provides smooth animations and preserves page state.
///
/// ## Gesture Priority
/// When `isGestureEnabled` is `false`, the pager's drag gesture is removed
/// entirely (`nil`), allowing `NavigationStack` edge swipes to work uncontested.
/// This is controlled by the parent based on navigation depth.
///
/// ## Exclusion Zones
/// - **Bottom area**: Reserved for dock interaction on Practice page only
///
/// ## Drag State Communication
/// The `isHorizontallyDragging` binding communicates active drag state to child
/// pages, allowing them to disable their ScrollViews during horizontal paging.
///
/// ## Usage
/// ```swift
/// HorizontalPager(
///     currentPage: $pageIndex,
///     pageCount: 3,
///     isGestureEnabled: profileNavigationDepth == 0,
///     bottomExclusionHeight: 120,
///     practicePageIndex: 1,
///     isHorizontallyDragging: $isDragging
/// ) {
///     PromptsPageView()
///     PracticePageView()
///     ProfilePageView()
/// }
/// ```
struct HorizontalPager<Content: View>: View {
    
    // MARK: - Properties
    
    /// Current page index (0-based)
    @Binding var currentPage: Int
    
    /// Total number of pages
    let pageCount: Int
    
    /// Whether horizontal swipe gestures are enabled.
    /// When false, NavigationStack's back gesture takes priority.
    let isGestureEnabled: Bool
    
    /// Bottom exclusion zone height (for dock area).
    /// Only applied on `practicePageIndex` page.
    let bottomExclusionHeight: CGFloat
    
    /// Index of the Practice page that has the dock (typically 1).
    /// Bottom exclusion only applies to this page.
    let practicePageIndex: Int
    
    /// Binding to communicate horizontal drag state to child pages.
    /// Child pages can use this to disable their ScrollViews during horizontal paging.
    @Binding var isHorizontallyDragging: Bool
    
    /// The pages to display
    @ViewBuilder let content: () -> Content
    
    // MARK: - Gesture State
    
    /// Tracks drag offset during gesture, resets to 0 when gesture ends
    @GestureState private var dragOffset: CGFloat = 0
    
    // MARK: - Constants
    
    /// Minimum drag distance to trigger page change
    private let dragThreshold: CGFloat = 50
    
    /// Animation for page transitions
    private var pageAnimation: Animation {
        .spring(response: 0.35, dampingFraction: 0.86)
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            let pageWidth = geometry.size.width
            let pageHeight = geometry.size.height
            
            HStack(spacing: 0) {
                content()
                    .frame(width: pageWidth)
            }
            .frame(width: pageWidth * CGFloat(pageCount), alignment: .leading)
            .offset(x: calculateOffset(pageWidth: pageWidth))
            .animation(pageAnimation, value: currentPage)
            .gesture(isGestureEnabled ? dragGesture(pageWidth: pageWidth, pageHeight: pageHeight) : nil)
        }
        .clipped() // Prevent pages from showing outside bounds
    }
    
    // MARK: - Offset Calculation
    
    /// Calculates the horizontal offset for the HStack based on current page and drag.
    private func calculateOffset(pageWidth: CGFloat) -> CGFloat {
        let pageOffset = -CGFloat(currentPage) * pageWidth
        return pageOffset + dragOffset
    }
    
    // MARK: - Drag Gesture
    
    /// Creates the drag gesture for horizontal paging.
    ///
    /// Exclusion zones:
    /// - Bottom area for dock interaction (Practice page only)
    ///
    /// When `isGestureEnabled` is false (Profile has navigation depth),
    /// the entire gesture is disabled, allowing NavigationStack full control.
    private func dragGesture(pageWidth: CGFloat, pageHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($dragOffset) { value, state, _ in
                // Only respond to primarily horizontal drags
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                guard isHorizontal else { return }
                
                // Exclude bottom area ONLY on Practice page (has dock)
                let startY = value.startLocation.y
                if currentPage == practicePageIndex {
                    guard startY < pageHeight - bottomExclusionHeight else { return }
                }
                
                // Update drag state for child pages
                DispatchQueue.main.async {
                    if !isHorizontallyDragging {
                        isHorizontallyDragging = true
                    }
                }
                
                // Apply resistance at page boundaries
                let translation = value.translation.width
                let isAtFirstPage = currentPage == 0 && translation > 0
                let isAtLastPage = currentPage == pageCount - 1 && translation < 0
                
                if isAtFirstPage || isAtLastPage {
                    // Rubber band effect at boundaries
                    state = translation * 0.3
                } else {
                    state = translation
                }
            }
            .onEnded { value in
                // Clear drag state
                isHorizontallyDragging = false
                
                // Exclude bottom area ONLY on Practice page (has dock)
                let startY = value.startLocation.y
                if currentPage == practicePageIndex {
                    guard startY < pageHeight - bottomExclusionHeight else { return }
                }
                
                // Only respond to horizontal drags
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                guard isHorizontal else { return }
                
                let translation = value.translation.width
                let velocity = value.predictedEndTranslation.width - translation
                
                // Determine if page should change based on drag distance and velocity
                var newPage = currentPage
                
                if translation < -dragThreshold || velocity < -500 {
                    // Swiped left → go to next page
                    newPage = min(currentPage + 1, pageCount - 1)
                } else if translation > dragThreshold || velocity > 500 {
                    // Swiped right → go to previous page
                    newPage = max(currentPage - 1, 0)
                }
                
                if newPage != currentPage {
                    HapticFeedback.selection()
                    currentPage = newPage
                }
            }
    }
}

// MARK: - Preview

#Preview("Horizontal Pager") {
    struct PreviewWrapper: View {
        @State private var currentPage = 1
        @State private var gesturesEnabled = true
        @State private var isDragging = false
        
        var body: some View {
            VStack {
                // Controls
                HStack {
                    Button("Page 0") { currentPage = 0 }
                    Button("Page 1") { currentPage = 1 }
                    Button("Page 2") { currentPage = 2 }
                }
                .padding()
                
                Toggle("Gestures Enabled", isOn: $gesturesEnabled)
                    .padding(.horizontal)
                
                Text("Current Page: \(currentPage)")
                Text("Is Dragging: \(isDragging ? "Yes" : "No")")
                    .padding(.bottom)
                
                // Pager
                HorizontalPager(
                    currentPage: $currentPage,
                    pageCount: 3,
                    isGestureEnabled: gesturesEnabled,
                    bottomExclusionHeight: 120,
                    practicePageIndex: 1,
                    isHorizontallyDragging: $isDragging
                ) {
                    Color.red.opacity(0.3)
                        .overlay(Text("Page 0 (Prompts)").font(.title))
                    
                    Color.green.opacity(0.3)
                        .overlay(Text("Page 1 (Practice)").font(.title))
                    
                    Color.blue.opacity(0.3)
                        .overlay(Text("Page 2 (Profile)").font(.title))
                }
            }
        }
    }
    
    return PreviewWrapper()
}

#Preview("Horizontal Pager - Dark") {
    struct PreviewWrapper: View {
        @State private var currentPage = 1
        @State private var isDragging = false
        
        var body: some View {
            HorizontalPager(
                currentPage: $currentPage,
                pageCount: 3,
                isGestureEnabled: true,
                bottomExclusionHeight: 120,
                practicePageIndex: 1,
                isHorizontallyDragging: $isDragging
            ) {
                ZStack {
                    AppColors.backgroundPrimary
                    Text("Prompts")
                        .font(AppTypography.title2)
                        .foregroundStyle(AppColors.textPrimary)
                }
                
                ZStack {
                    AppColors.backgroundPrimary
                    Text("Practice")
                        .font(AppTypography.title2)
                        .foregroundStyle(AppColors.textPrimary)
                }
                
                ZStack {
                    AppColors.backgroundPrimary
                    Text("Profile")
                        .font(AppTypography.title2)
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
    
    return PreviewWrapper()
}
