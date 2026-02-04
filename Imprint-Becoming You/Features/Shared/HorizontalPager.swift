//
//  HorizontalPager.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/1/26.
//

import SwiftUI
import UIKit

// MARK: - PagerCoordinating

/// Protocol that decouples `PagerViewController` from `HorizontalPager`'s generic
/// `Content` type. Without this, `PagerViewController` would need to reference
/// `HorizontalPager<AnyView>.Coordinator`, which doesn't match the actual
/// `HorizontalPager<Content>.Coordinator` at the call site.
protocol PagerCoordinating: UIScrollViewDelegate {
    /// The current page index, used by `viewDidLayoutSubviews` to re-sync
    /// the scroll offset after layout changes (rotation, multitasking).
    var currentPageIndex: Int { get }
}

// MARK: - HorizontalPager

/// A horizontal paging container backed by `UIScrollView` for native touch handling.
///
/// ## Why UIScrollView?
///
/// SwiftUI's gesture system (`DragGesture`, `Button`, `onTapGesture`) runs in a
/// parallel pipeline to UIKit's touch delivery. This makes it impossible to cancel
/// SwiftUI button taps from an external gesture recognizer -- `cancelsTouchesInView`,
/// `delaysContentTouches`, and `touchesCancelled` have no effect on SwiftUI's
/// internal `_ButtonGesture`.
///
/// `UIScrollView` solves this natively because:
/// - **`delaysContentTouches = true`** (default): Touch delivery to child views is
///   delayed until the scroll view determines the gesture is not a scroll.
/// - **`canCancelContentTouches = true`** (default): If a scroll begins after touch
///   delivery started, the scroll view sends `touchesCancelled` to the child view.
/// - **`isPagingEnabled = true`**: Provides native paging snap behavior.
/// - **`bounces = false`**: Solid walls at page boundaries -- no rubber banding.
///
/// Child SwiftUI views are hosted in `UIHostingController` instances laid out
/// side-by-side inside the scroll view. All existing SwiftUI views, state
/// management, and architecture remain completely untouched.
///
/// ## Gesture Coexistence with VerticalPager
///
/// The VerticalPager uses `.highPriorityGesture(DragGesture(...))` which translates
/// to a UIKit `UIPanGestureRecognizer` on the hosting controller's internal view.
/// By default, UIKit gives child gesture recognizers exclusive priority, blocking
/// the parent scroll view's pan gesture entirely.
///
/// `PagingScrollView` solves this by conforming to `UIGestureRecognizerDelegate`
/// and returning `true` from `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)`.
/// This allows both gesture recognizers to fire together. Each then filters by axis:
/// - **UIScrollView**: Only scrolls horizontally (no vertical content, `isPagingEnabled`)
/// - **VerticalPager**: Direction-locks to vertical (`vertical > horizontal * 2`)
///
/// ## Disabled State (Destination Views)
///
/// When `isGestureEnabled` is `false` (e.g., Profile has navigation depth > 0),
/// `isScrollEnabled` is set to `false` on the scroll view. This makes the scroll
/// view completely transparent to touches -- no delay, no gesture interference.
/// This ensures `NavigationStack`'s back gesture works unimpeded on all content,
/// including cards with swipe actions. Programmatic scrolling via `setContentOffset`
/// still works when `isScrollEnabled` is `false`.
///
/// ## Exclusion Zones
/// - **Profile right edge (40pt)**: Swipes starting in this zone are blocked via
///   `PagingScrollView.gestureRecognizerShouldBegin(_:)`. This creates
///   a solid edge feel since there is nothing to navigate to past Profile.
///
/// ## Drag State Communication
/// The `isHorizontallyDragging` binding communicates active drag state to child
/// pages, allowing them to disable their `ScrollView`s during horizontal paging.
/// Set via `UIScrollViewDelegate` callbacks (`willBeginDragging` / `didEndDragging`
/// / `didEndDecelerating`). A velocity direction check ensures the flag is only
/// set for genuinely horizontal drags, preventing false positives from diagonal
/// or vertical touches that fire due to simultaneous gesture recognition.
///
/// ## Usage
/// ```swift
/// HorizontalPager(
///     currentPage: $pageIndex,
///     pageCount: 3,
///     isGestureEnabled: isPagerGestureEnabled,
///     isHorizontallyDragging: $isDragging
/// ) {
///     PromptsPageView()
///     PracticePageView()
///     ProfilePageView()
/// }
/// ```
struct HorizontalPager<Content: View>: UIViewControllerRepresentable {
    
    // MARK: - Properties
    
    /// Current page index (0-based). Bidirectional: SwiftUI can set it (programmatic
    /// navigation), and the scroll view updates it on swipe completion.
    @Binding var currentPage: Int
    
    /// Total number of pages
    let pageCount: Int
    
    /// Whether horizontal swipe gestures are enabled.
    /// When false, the scroll view's `isScrollEnabled` is set to `false`,
    /// making it completely transparent to touches. This allows
    /// `NavigationStack`'s back gesture to work unimpeded.
    let isGestureEnabled: Bool
    
    /// Binding to communicate horizontal drag state to child pages.
    /// Child pages can use this to disable their `ScrollView`s during horizontal paging.
    @Binding var isHorizontallyDragging: Bool
    
    /// The pages to display
    @ViewBuilder let content: () -> Content
    
    // MARK: - UIViewControllerRepresentable
    
    func makeUIViewController(context: Context) -> PagerViewController {
        let controller = PagerViewController()
        controller.coordinator = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ controller: PagerViewController, context: Context) {
        let coordinator = context.coordinator
        
        // Keep coordinator's parent reference current for binding access
        coordinator.parent = self
        
        // Update scroll enabled state.
        // When false: scroll view becomes completely transparent to touches,
        // ensuring NavigationStack's back gesture works on all content.
        // When true: full paging behavior with touch delay and gesture handling.
        // Programmatic scrolling via setContentOffset still works either way.
        controller.scrollView.isScrollEnabled = isGestureEnabled
        
        // Sync page count for exclusion zone logic in PagingScrollView
        controller.scrollView.pageCount = pageCount
        
        // Sync programmatic page changes (e.g., navigateToPage, background reset).
        // Only scroll if this is NOT a scroll-driven update (prevents feedback loop).
        let pageWidth = controller.scrollView.bounds.width
        if pageWidth > 0 {
            let targetOffset = CGFloat(currentPage) * pageWidth
            if abs(controller.scrollView.contentOffset.x - targetOffset) > 1,
               !coordinator.isScrollDriven {
                controller.scrollView.setContentOffset(
                    CGPoint(x: targetOffset, y: 0),
                    animated: true
                )
            }
        }
        coordinator.isScrollDriven = false
        
        // Update hosting controllers with new SwiftUI content
        coordinator.updateContent(content(), in: controller, pageCount: pageCount)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    // MARK: - Coordinator
    
    /// Bridges `UIScrollViewDelegate` callbacks to SwiftUI bindings.
    ///
    /// Also manages `UIHostingController` lifecycle for each page. The profile
    /// right-edge exclusion zone and simultaneous gesture recognition are handled
    /// by the `PagingScrollView` subclass.
    final class Coordinator: NSObject, PagerCoordinating {
        
        /// Reference to the parent SwiftUI view for binding access.
        /// Updated on every `updateUIViewController` call.
        var parent: HorizontalPager
        
        /// Flag to prevent `updateUIViewController` from re-animating scroll-driven
        /// page changes. Set to `true` in delegate callbacks before updating the binding.
        var isScrollDriven = false
        
        /// Hosting controllers for each page, created once and reused.
        var hostingControllers: [UIHostingController<AnyView>] = []
        
        // MARK: - PagerCoordinating
        
        var currentPageIndex: Int { parent.currentPage }
        
        init(parent: HorizontalPager) {
            self.parent = parent
        }
        
        // MARK: - Content Management
        
        /// Creates or updates hosting controllers from the SwiftUI content ViewBuilder.
        ///
        /// Extracts individual pages from the `@ViewBuilder`'s `TupleView` using
        /// `Mirror`. Each page is wrapped in `AnyView` and hosted in its own
        /// `UIHostingController`, laid out side-by-side via Auto Layout.
        func updateContent<V: View>(_ content: V, in controller: PagerViewController, pageCount: Int) {
            let pages = extractPages(from: content, expectedCount: pageCount)
            
            if hostingControllers.isEmpty {
                // First call: create hosting controllers and install in the container
                createHostingControllers(pages: pages, in: controller, pageCount: pageCount)
            } else {
                // Subsequent calls: update existing hosting controllers with new content
                for (index, page) in pages.prefix(pageCount).enumerated() {
                    if index < hostingControllers.count {
                        hostingControllers[index].rootView = page
                    }
                }
            }
        }
        
        /// Extracts individual child views from a `@ViewBuilder` `TupleView`.
        private func extractPages<V: View>(from content: V, expectedCount: Int) -> [AnyView] {
            let mirror = Mirror(reflecting: content)
            var pages: [AnyView] = []
            
            // @ViewBuilder with multiple children produces a TupleView.
            // Mirror its "value" property to get each child.
            if let tupleValue = mirror.children.first(where: { $0.label == "value" }) {
                let valueMirror = Mirror(reflecting: tupleValue.value)
                for child in valueMirror.children {
                    pages.append(AnyView(_fromValue: child.value) ?? AnyView(EmptyView()))
                }
            }
            
            // Fallback: single child or non-tuple — wrap whole content as one page
            if pages.isEmpty {
                pages = [AnyView(content)]
            }
            
            // Pad to expected count if ViewBuilder provided fewer pages
            while pages.count < expectedCount {
                pages.append(AnyView(EmptyView()))
            }
            
            return pages
        }
        
        /// Creates `UIHostingController`s for each page and lays them out in the
        /// scroll view's content view using Auto Layout.
        private func createHostingControllers(
            pages: [AnyView],
            in controller: PagerViewController,
            pageCount: Int
        ) {
            for (index, page) in pages.prefix(pageCount).enumerated() {
                let hc = UIHostingController(rootView: page)
                hc.view.backgroundColor = .clear
                hc.safeAreaRegions = []
                hostingControllers.append(hc)
                
                controller.addChild(hc)
                controller.contentView.addSubview(hc.view)
                hc.view.translatesAutoresizingMaskIntoConstraints = false
                hc.didMove(toParent: controller)
                
                // Each page: full height of scroll view, full width of scroll view
                NSLayoutConstraint.activate([
                    hc.view.topAnchor.constraint(equalTo: controller.contentView.topAnchor),
                    hc.view.bottomAnchor.constraint(equalTo: controller.contentView.bottomAnchor),
                    hc.view.widthAnchor.constraint(equalTo: controller.scrollView.widthAnchor),
                    hc.view.heightAnchor.constraint(equalTo: controller.scrollView.heightAnchor)
                ])
                
                // Horizontal chaining: leading edge of each page connects to trailing of previous
                if index == 0 {
                    hc.view.leadingAnchor.constraint(
                        equalTo: controller.contentView.leadingAnchor
                    ).isActive = true
                } else {
                    hc.view.leadingAnchor.constraint(
                        equalTo: hostingControllers[index - 1].view.trailingAnchor
                    ).isActive = true
                }
                
                // Last page pins trailing to content view (defines total content width)
                if index == pageCount - 1 {
                    hc.view.trailingAnchor.constraint(
                        equalTo: controller.contentView.trailingAnchor
                    ).isActive = true
                }
            }
        }
        
        // MARK: - UIScrollViewDelegate
        
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            // With simultaneous gesture recognition enabled, this callback can fire
            // even during predominantly vertical drags. Only flag as horizontal drag
            // when the user's velocity is actually horizontal, so child pages
            // (Profile) don't have their ScrollViews falsely disabled via
            // .scrollDisabled(isHorizontallyDragging).
            let velocity = scrollView.panGestureRecognizer.velocity(in: scrollView)
            let isHorizontal = abs(velocity.x) > abs(velocity.y)
            
            if isHorizontal {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.isHorizontallyDragging = true
                }
            }
        }
        
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                finishScrolling(scrollView)
            }
        }
        
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            finishScrolling(scrollView)
        }
        
        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            // Programmatic scrolling completed (setContentOffset animated:true).
            // Update binding in case the target page differs from current binding.
            updatePageFromOffset(scrollView)
        }
        
        /// Called when user-driven scrolling finishes (drag end without deceleration,
        /// or deceleration complete). Updates dragging state and page binding.
        private func finishScrolling(_ scrollView: UIScrollView) {
            let newPage = pageIndex(from: scrollView)
            let pageChanged = newPage != parent.currentPage
            
            // Haptic on page change (fires before binding update)
            if pageChanged {
                HapticFeedback.selection()
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.parent.isHorizontallyDragging = false
            }
            
            updatePageFromOffset(scrollView)
        }
        
        /// Derives page index from scroll offset and syncs to the SwiftUI binding.
        private func updatePageFromOffset(_ scrollView: UIScrollView) {
            let newPage = pageIndex(from: scrollView)
            if newPage != parent.currentPage {
                isScrollDriven = true
                DispatchQueue.main.async { [weak self] in
                    self?.parent.currentPage = newPage
                }
            }
        }
        
        /// Calculates the current page index from the scroll view's content offset.
        private func pageIndex(from scrollView: UIScrollView) -> Int {
            let pageWidth = scrollView.bounds.width
            guard pageWidth > 0 else { return 0 }
            let page = Int(round(scrollView.contentOffset.x / pageWidth))
            return max(0, min(page, parent.pageCount - 1))
        }
        
    }
}

// MARK: - PagerViewController

/// Lightweight `UIViewController` that hosts a `UIScrollView` with paging behavior.
///
/// The scroll view is configured once in `viewDidLoad`:
/// - `isPagingEnabled = true` for snap-to-page behavior
/// - `bounces = false` for solid walls at boundaries
/// - `showsHorizontalScrollIndicator = false` for clean UI
/// - `delaysContentTouches = true` (default) for native touch cancellation
/// - `canCancelContentTouches = true` (default) for scroll-during-touch
///
/// Child pages are added as subviews of `contentView`, which is the scroll view's
/// only direct child and defines the scrollable content area via Auto Layout.
final class PagerViewController: UIViewController {
    
    // MARK: - Views
    
    /// The paging scroll view (subclassed for exclusion zone and simultaneous gestures)
    let scrollView = PagingScrollView()
    
    /// Container view inside the scroll view that holds all page hosting controllers
    let contentView = UIView()
    
    // MARK: - Properties
    
    /// Reference to coordinator for delegate setup and layout sync.
    /// Uses `PagerCoordinating` protocol to avoid coupling to the generic `Content` type.
    /// Set by the representable before `viewDidLoad`.
    weak var coordinator: (any PagerCoordinating)?
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .clear
        
        // Configure scroll view for horizontal paging
        scrollView.isPagingEnabled = true
        scrollView.bounces = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = coordinator
        
        // Layout: scrollView fills the entire view
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Layout: contentView defines the scrollable area inside the scroll view
        scrollView.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Re-sync content offset after layout changes (rotation, multitasking).
        // Without this, a rotation could leave the scroll view between pages.
        guard let coordinator = coordinator else { return }
        let pageWidth = scrollView.bounds.width
        guard pageWidth > 0 else { return }
        let targetOffset = CGFloat(coordinator.currentPageIndex) * pageWidth
        if abs(scrollView.contentOffset.x - targetOffset) > 1 {
            scrollView.setContentOffset(CGPoint(x: targetOffset, y: 0), animated: false)
        }
    }
}

// MARK: - PagingScrollView

/// `UIScrollView` subclass that handles exclusion zones and simultaneous gesture
/// recognition with child SwiftUI gesture recognizers.
///
/// ## Why Subclass?
///
/// UIKit requires `UIScrollView`'s built-in pan gesture recognizer to have the
/// scroll view itself as its delegate. Assigning a custom delegate crashes:
/// > "UIScrollView's built-in pan gesture recognizer must have its scroll view
/// > as its delegate."
///
/// Instead, we subclass and override gesture recognizer methods directly.
///
/// ## UIGestureRecognizerDelegate Conformance
///
/// The explicit conformance is critical. UIScrollView acts as its own pan gesture's
/// delegate through an internal private mechanism, but does NOT publicly conform to
/// `UIGestureRecognizerDelegate`. Without explicit conformance on our subclass,
/// Swift does not generate the `@objc` selector for
/// `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)`, making it invisible
/// to ObjC message dispatch. UIKit would never call it, and the default behavior
/// (no simultaneous recognition) would apply -- blocking horizontal swiping entirely
/// wherever a child gesture recognizer exists (e.g., VerticalPager's DragGesture).
///
/// ## Exclusion Zone
/// On the last page (Profile), the rightmost 40pt is a non-reactive solid edge
/// since there is nothing to navigate to past Profile. Swipes starting in this
/// zone are blocked, creating a "solid wall" feel matching `NavigationStack`.
final class PagingScrollView: UIScrollView, UIGestureRecognizerDelegate {
    
    /// Total number of pages. Set by `PagerViewController` during setup.
    var pageCount: Int = 0
    
    /// Width of the non-reactive solid edge on the last page (Profile).
    private let profileSolidEdgeWidth: CGFloat = 40
    
    // MARK: - Exclusion Zone
    
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Only intercept the built-in pan gesture
        guard gestureRecognizer === panGestureRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        
        let pageWidth = bounds.width
        guard pageWidth > 0, pageCount > 0 else { return true }
        
        let currentPage = Int(round(contentOffset.x / pageWidth))
        let isLastPage = currentPage == pageCount - 1
        
        guard isLastPage else { return true }
        
        // Check if touch started in the right-edge exclusion zone
        let touchLocation = gestureRecognizer.location(in: self)
        let localX = touchLocation.x - contentOffset.x
        let isRightEdge = localX > pageWidth - profileSolidEdgeWidth
        
        if isRightEdge {
            return false // Block gesture -- solid edge
        }
        
        return true
    }
    
    // MARK: - Simultaneous Gesture Recognition
    
    /// Allows the scroll view's pan gesture to recognize simultaneously with child
    /// pan gestures that are NOT on a `UIScrollView`.
    ///
    /// ## Why selective?
    ///
    /// **Allow simultaneous with VerticalPager's `DragGesture`** (Practice page):
    /// SwiftUI's `DragGesture` translates to a `UIPanGestureRecognizer` on the
    /// hosting controller's view (NOT a `UIScrollView`). Both gestures fire and
    /// each filters by direction: our pager handles horizontal, VerticalPager
    /// handles vertical.
    ///
    /// **Block simultaneous with child `UIScrollView` pans** (Profile/Prompts):
    /// These pages contain vertical `ScrollView`s whose internal pan gesture
    /// lives on a `UIScrollView`. When blocked, `delaysContentTouches` (default
    /// `true`) naturally routes touches by direction — horizontal touches go to
    /// our pager, vertical touches go to the child `ScrollView`. This is standard
    /// nested `UIScrollView` behavior and prevents the user from scrolling
    /// vertically and paging horizontally at the same time.
    ///
    /// This method is called via ObjC message dispatch because `PagingScrollView`
    /// explicitly conforms to `UIGestureRecognizerDelegate`. UIScrollView internally
    /// sets itself as the delegate of its own `panGestureRecognizer`, so our subclass
    /// receives the delegate callbacks automatically.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Allow our pan gesture to coexist with non-UIScrollView pan gestures
        // (e.g., VerticalPager's DragGesture on the Practice page). Both
        // gestures fire and each filters by direction independently.
        //
        // Block simultaneous recognition with other UIScrollView pan gestures
        // (e.g., Profile's/Prompts' vertical ScrollViews). When blocked,
        // delaysContentTouches naturally routes horizontal touches to our pager
        // and vertical touches to the child ScrollView — standard nested
        // UIScrollView behavior.
        if gestureRecognizer === panGestureRecognizer,
           otherGestureRecognizer is UIPanGestureRecognizer,
           !(otherGestureRecognizer.view is UIScrollView) {
            return true
        }
        return false
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
