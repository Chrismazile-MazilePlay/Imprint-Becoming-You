//
//  VerticalPager.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import SwiftUI

// MARK: - VerticalPager

/// A TikTok-style vertical pager with dual-content display and auto-advance support.
///
/// ## Key Features
/// - Shows BOTH current AND adjacent content during drag
/// - 1:1 finger tracking with rubber-band at boundaries
/// - Supports programmatic auto-advance with animation
/// - High-priority vertical gesture (overrides parent horizontal)
/// - **Graceful transitions**: Content fades and scales as it moves
/// - **Background resilience**: Resets animation state when returning from background
///
/// ## Content Transitions
/// As content moves away from center:
/// - Opacity fades from 1.0 -> 0.3
/// - Scale reduces from 1.0 -> 0.95
/// This creates a polished, depth-aware transition that masks any index swap artifacts.
///
/// ## Auto-Advance Architecture
/// Auto-advance uses a fundamentally different approach than manual dragging:
/// - **Outgoing content**: Animates from center to off-screen
/// - **Incoming content**: Stays FIXED at center position, fades in
///
/// This eliminates "jumping" because the incoming content is already at its
/// final position when the index changes. No position reset is needed.
///
/// ## Visual During Auto-Advance (to next):
/// ```
/// +------------------------+
/// |  Current (moving)      |  offset animates: 0 -> -screenHeight
/// +------------------------+
/// |  Next (FIXED)          |  offset = 0 (always centered!)
/// +------------------------+
/// ```
struct VerticalPager<Content: View, Background: View>: View {
    
    // MARK: - Properties
    
    /// Current item index (bound to source of truth)
    @Binding var currentIndex: Int
    
    /// Total number of items
    let itemCount: Int
    
    /// Whether navigation gestures are allowed at all
    let canNavigate: Bool
    
    /// External control for whether "next" navigation is allowed (session bounds)
    /// When false, prevents swiping to next even if more items exist
    let canNavigateNext: Bool
    
    /// External control for whether "previous" navigation is allowed (session bounds)
    /// When false, prevents swiping to previous even if at index > 0
    let canNavigatePrevious: Bool
    
    /// Set to trigger programmatic advance with animation
    @Binding var pendingAdvance: NavigationDirection?
    
    /// Content builder - receives index
    @ViewBuilder let content: (_ index: Int) -> Content
    
    /// Background builder - receives current index and drag progress (-1 to +1)
    @ViewBuilder let background: (_ currentIndex: Int, _ progress: CGFloat) -> Background
    
    /// Called after user-initiated navigation completes
    var onNavigate: ((_ direction: NavigationDirection) -> Void)?
    
    /// Called after programmatic auto-advance animation completes
    var onAutoAdvanceComplete: (() -> Void)?
    
    // MARK: - Environment
    
    @Environment(\.scenePhase) private var scenePhase
    
    // MARK: - Configuration
    
    private let navigationThreshold: CGFloat = 0.10
    private let velocityThreshold: CGFloat = 300
    private let boundaryResistance: CGFloat = 0.3
    private let animationDuration: Double = 0.35
    
    /// Minimum opacity for content as it moves away (0.0 - 1.0)
    private let minContentOpacity: Double = 0.3
    
    /// Minimum scale for content as it moves away (0.0 - 1.0)
    private let minContentScale: CGFloat = 0.95
    
    // MARK: - Drag State (Manual Navigation)
    
    @State private var dragOffset: CGFloat = 0
    @State private var isVerticalDrag: Bool = false
    @State private var gestureDirectionLocked: Bool = false
    @State private var screenHeight: CGFloat = 0
    
    /// Cancellable task for the delayed index swap after navigation animation.
    /// Replaced on each new navigation; cancelled when a new gesture begins.
    @State private var navigationCompletionTask: Task<Void, Never>?
    
    /// Direction of the in-flight navigation whose completion is pending.
    /// Non-nil only between animation start and the delayed index swap.
    @State private var pendingNavigationDirection: NavigationDirection?
    
    // MARK: - Auto-Advance State
    
    /// Progress of auto-advance animation (0 = start, 1 = complete)
    @State private var autoAdvanceProgress: CGFloat = 0
    
    /// Direction of current auto-advance, or nil if not auto-advancing
    @State private var autoAdvanceDirection: NavigationDirection? = nil
    
    /// Tracks whether app was backgrounded, for state reset on return.
    /// ScenePhase transitions: background -> inactive -> active, so we can't
    /// rely on oldPhase being .background in onChange.
    @State private var wasBackgrounded: Bool = false
    
    /// Whether an auto-advance animation is in progress
    private var isAutoAdvancing: Bool {
        autoAdvanceDirection != nil
    }
    
    // MARK: - Computed
    
    /// Whether navigation to next item is allowed
    /// Respects both item count AND external session bounds
    private var canGoNext: Bool {
        currentIndex < itemCount - 1 && canNavigateNext
    }
    
    /// Whether navigation to previous item is allowed
    /// Respects both item count AND external session bounds
    private var canGoPrevious: Bool {
        currentIndex > 0 && canNavigatePrevious
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            
            // Progress for background morphing
            let backgroundProgress: CGFloat = {
                if let direction = autoAdvanceDirection {
                    // During auto-advance, use autoAdvanceProgress
                    return direction == .next ? autoAdvanceProgress : -autoAdvanceProgress
                } else {
                    // During drag, use dragOffset
                    return height > 0 ? -dragOffset / height : 0
                }
            }()
            
            ZStack {
                // Background layer (fixed position, color morphs)
                background(currentIndex, backgroundProgress)
                
                // Content layers
                if isAutoAdvancing {
                    // Auto-advance: special positioning (incoming stays fixed)
                    autoAdvanceContentLayers(screenHeight: height)
                } else {
                    // Manual drag: normal positioning
                    dragContentLayers(screenHeight: height)
                }
            }
            .contentShape(Rectangle())
            .highPriorityGesture(
                canNavigate && !isAutoAdvancing ? verticalDragGesture(screenHeight: height) : nil
            )
            .onAppear {
                screenHeight = height
            }
            .onChange(of: geometry.size.height) { _, newHeight in
                screenHeight = newHeight
            }
        }
        .onChange(of: pendingAdvance) { _, newDirection in
            if let direction = newDirection {
                performAutoAdvance(direction: direction)
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
    }
    
    // MARK: - Scene Phase Handling
    
    /// Handles app lifecycle transitions to prevent stale animation state.
    ///
    /// When the app goes to background mid-animation, SwiftUI's animation state
    /// can get stuck at intermediate values. This causes content to be offset
    /// when returning from background.
    ///
    /// Example: If `autoAdvanceProgress` is stuck at 0.3 when returning,
    /// content would be offset by `screenHeight * 0.3` (~240pt on iPhone).
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            // Mark that we went to background
            wasBackgrounded = true
            
        case .active:
            // Only reset if we're returning FROM background
            // ScenePhase transitions: background -> inactive -> active
            // So we use our own tracking flag
            if wasBackgrounded {
                wasBackgrounded = false
                resetAnimationState()
            }
            
        case .inactive:
            // No action needed for inactive state
            break
            
        @unknown default:
            break
        }
    }
    
    /// Resets all animation state to default values.
    ///
    /// Called when returning from background to ensure content is properly centered.
    /// This clears any stale state from interrupted animations.
    private func resetAnimationState() {
        // Finalize any in-flight navigation before resetting
        commitPendingNavigation()
        
        // Reset auto-advance state
        autoAdvanceDirection = nil
        autoAdvanceProgress = 0
        
        // Clear pending advance to prevent double-animation
        if pendingAdvance != nil {
            pendingAdvance = nil
        }
        
        // Reset drag state
        dragOffset = 0
        isVerticalDrag = false
        gestureDirectionLocked = false
    }
    
    // MARK: - Auto-Advance Content Layers
    
    /// Content positioning during auto-advance.
    ///
    /// Key difference from drag: incoming content stays FIXED at center.
    /// Only outgoing content moves. This eliminates any position discontinuity
    /// when the index changes.
    @ViewBuilder
    private func autoAdvanceContentLayers(screenHeight: CGFloat) -> some View {
        if let direction = autoAdvanceDirection {
            let outgoingIndex = currentIndex
            let incomingIndex = direction == .next ? currentIndex + 1 : currentIndex - 1
            
            if incomingIndex >= 0 && incomingIndex < itemCount {
                let progress = autoAdvanceProgress
                
                ZStack {
                    // INCOMING content - FIXED at center, fades in
                    content(incomingIndex)
                        .offset(y: 0) // Always at center!
                        .modifier(ContentTransitionModifier(
                            progress: progress, // 0 -> 1 (fades in)
                            minOpacity: minContentOpacity,
                            minScale: minContentScale
                        ))
                    
                    // OUTGOING content - moves away from center
                    content(outgoingIndex)
                        .offset(y: direction == .next ? -screenHeight * progress : screenHeight * progress)
                        .modifier(ContentTransitionModifier(
                            progress: 1 - progress, // 1 -> 0 (fades out)
                            minOpacity: minContentOpacity,
                            minScale: minContentScale,
                            isCurrent: true
                        ))
                }
            }
        }
    }
    
    // MARK: - Drag Content Layers (Manual Navigation)
    
    /// Content positioning during manual drag gestures.
    @ViewBuilder
    private func dragContentLayers(screenHeight: CGFloat) -> some View {
        let progress = screenHeight > 0 ? -dragOffset / screenHeight : 0
        
        ZStack {
            // PREVIOUS content - visible when dragging DOWN (dragOffset > 0)
            if canGoPrevious && dragOffset > 0 {
                content(currentIndex - 1)
                    .offset(y: -screenHeight + dragOffset)
                    .modifier(ContentTransitionModifier(
                        progress: -progress,
                        minOpacity: minContentOpacity,
                        minScale: minContentScale
                    ))
            }
            
            // CURRENT content - always visible, moves with drag
            content(currentIndex)
                .offset(y: dragOffset)
                .modifier(ContentTransitionModifier(
                    progress: 1 - abs(progress),
                    minOpacity: minContentOpacity,
                    minScale: minContentScale,
                    isCurrent: true
                ))
            
            // NEXT content - visible when dragging UP (dragOffset < 0)
            if canGoNext && dragOffset < 0 {
                content(currentIndex + 1)
                    .offset(y: screenHeight + dragOffset)
                    .modifier(ContentTransitionModifier(
                        progress: progress,
                        minOpacity: minContentOpacity,
                        minScale: minContentScale
                    ))
            }
        }
    }
    
    // MARK: - User Gesture
    
    private func verticalDragGesture(screenHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                handleDragChanged(value, screenHeight: screenHeight)
            }
            .onEnded { value in
                handleDragEnded(value, screenHeight: screenHeight)
            }
    }
    
    private func handleDragChanged(_ value: DragGesture.Value, screenHeight: CGFloat) {
        // Finalize any in-flight navigation before processing new gesture.
        // This ensures the index is correct before the new drag begins.
        commitPendingNavigation()
        
        // Cancel any pending auto-advance if user starts gesture
        if pendingAdvance != nil {
            pendingAdvance = nil
        }
        
        let horizontal = abs(value.translation.width)
        let vertical = abs(value.translation.height)
        
        // Lock gesture direction on first significant movement
        if !gestureDirectionLocked && (horizontal > 10 || vertical > 10) {
            isVerticalDrag = vertical > horizontal * 1.2
            gestureDirectionLocked = true
        }
        
        guard isVerticalDrag else { return }
        
        let translation = value.translation.height
        
        // Apply rubber-band at boundaries
        if (translation < 0 && !canGoNext) || (translation > 0 && !canGoPrevious) {
            dragOffset = translation * boundaryResistance
        } else {
            dragOffset = translation
        }
    }
    
    private func handleDragEnded(_ value: DragGesture.Value, screenHeight: CGFloat) {
        defer {
            isVerticalDrag = false
            gestureDirectionLocked = false
        }
        
        guard isVerticalDrag else {
            withAnimation(AppTheme.Animation.standard) {
                dragOffset = 0
            }
            return
        }
        
        let translation = value.translation.height
        let velocity = value.predictedEndTranslation.height - translation
        let threshold = screenHeight * navigationThreshold
        
        var shouldNavigate = false
        var direction: NavigationDirection = .next
        
        if translation < -threshold || velocity < -velocityThreshold {
            if canGoNext {
                shouldNavigate = true
                direction = .next
            }
        } else if translation > threshold || velocity > velocityThreshold {
            if canGoPrevious {
                shouldNavigate = true
                direction = .previous
            }
        }
        
        if shouldNavigate {
            completeUserNavigation(direction: direction, screenHeight: screenHeight)
        } else {
            withAnimation(AppTheme.Animation.standard) {
                dragOffset = 0
            }
        }
    }
    
    /// Completes user-initiated navigation with animation.
    ///
    /// ## Animation Strategy
    /// Uses a spring with slight bounce for natural deceleration, then waits
    /// for the **full** animation duration before swapping the index. The index
    /// swap and offset reset are wrapped in `withTransaction` to execute
    /// atomically without triggering an implicit animation.
    ///
    /// ## Rapid Swipe Safety
    /// The delayed index swap uses a cancellable `Task` tracked by
    /// `navigationCompletionTask`. If the user starts a new gesture before
    /// the timer fires, `commitPendingNavigation()` cancels the task and
    /// applies the index change immediately — ensuring every new gesture
    /// starts from a correct, clean state. At most one pending completion
    /// exists at any time.
    private func completeUserNavigation(direction: NavigationDirection, screenHeight: CGFloat) {
        // Commit any prior in-flight navigation before starting a new one.
        // Guarantees at most one pending completion exists at any time.
        commitPendingNavigation()
        
        let targetOffset = direction == .next ? -screenHeight : screenHeight
        
        // Track the pending direction so commitPendingNavigation() knows
        // which index change to apply if it needs to finalize early.
        pendingNavigationDirection = direction
        
        // Animate content off-screen with natural deceleration
        withAnimation(.spring(duration: animationDuration, bounce: 0.12)) {
            dragOffset = targetOffset
        }
        
        // Schedule the delayed index swap as a cancellable Task.
        // If a new gesture arrives before this fires, commitPendingNavigation()
        // cancels this task and applies the change immediately.
        navigationCompletionTask = Task { @MainActor [animationDuration] in
            try? await Task.sleep(for: .seconds(animationDuration + 0.03))
            guard !Task.isCancelled else { return }
            
            // Content is now fully off-screen — swap is invisible
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dragOffset = 0
                currentIndex += (direction == .next ? 1 : -1)
            }
            pendingNavigationDirection = nil
            navigationCompletionTask = nil
            onNavigate?(direction)
        }
    }
    
    /// Immediately finalizes any in-flight navigation whose completion timer
    /// has not yet fired.
    ///
    /// Called at the start of every new gesture and on background return.
    /// Cancels the pending timer and applies the index change now, so the
    /// new interaction starts from a correct state.
    private func commitPendingNavigation() {
        guard let direction = pendingNavigationDirection else { return }
        
        // Cancel the delayed completion — we're applying it now
        navigationCompletionTask?.cancel()
        navigationCompletionTask = nil
        
        // Apply the index change immediately
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragOffset = 0
            currentIndex += (direction == .next ? 1 : -1)
        }
        pendingNavigationDirection = nil
        onNavigate?(direction)
    }
    
    // MARK: - Programmatic Auto-Advance
    
    /// Performs animated transition triggered programmatically.
    ///
    /// Uses a dedicated progress-based animation where:
    /// - Outgoing content animates from center to off-screen
    /// - Incoming content stays FIXED at center, just fades in
    ///
    /// This eliminates visual "jumping" because no position reset is needed.
    private func performAutoAdvance(direction: NavigationDirection) {
        // Don't start new auto-advance while one is in progress
        guard !isAutoAdvancing else {
            pendingAdvance = nil
            return
        }
        
        // Validate we can advance
        switch direction {
        case .next:
            guard canGoNext else {
                pendingAdvance = nil
                return
            }
        case .previous:
            guard canGoPrevious else {
                pendingAdvance = nil
                return
            }
        }
        
        guard screenHeight > 0 else {
            pendingAdvance = nil
            return
        }
        
        // Clear pending and start auto-advance
        pendingAdvance = nil
        autoAdvanceDirection = direction
        autoAdvanceProgress = 0
        
        // Animate progress from 0 to 1
        withAnimation(.spring(duration: animationDuration, bounce: 0.0)) {
            autoAdvanceProgress = 1
        }
        
        // Complete the transition after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration + 0.05) {
            // Update index
            currentIndex += (direction == .next ? 1 : -1)
            
            // Clear auto-advance state (no position reset needed!)
            autoAdvanceDirection = nil
            autoAdvanceProgress = 0
            
            // Call completion handler
            onAutoAdvanceComplete?()
        }
    }
}

// MARK: - Content Transition Modifier

/// Applies opacity and scale transitions to content based on progress.
///
/// This creates a polished "depth" effect as content moves in/out of view,
/// and masks any visual artifacts from index swapping.
private struct ContentTransitionModifier: ViewModifier {
    
    /// Progress from 0 (fully away) to 1 (fully visible/centered)
    let progress: CGFloat
    
    /// Minimum opacity when content is fully away
    let minOpacity: Double
    
    /// Minimum scale when content is fully away
    let minScale: CGFloat
    
    /// Whether this is the current (center) content
    var isCurrent: Bool = false
    
    func body(content: Content) -> some View {
        let clampedProgress = min(max(progress, 0), 1)
        
        let opacity = minOpacity + (1.0 - minOpacity) * clampedProgress
        let scale = minScale + (1.0 - minScale) * clampedProgress
        
        content
            .opacity(opacity)
            .scaleEffect(scale)
    }
}

// MARK: - Convenience Initializers

extension VerticalPager {
    
    /// Full initializer with auto-advance support and session bounds
    init(
        currentIndex: Binding<Int>,
        itemCount: Int,
        canNavigate: Bool = true,
        canNavigateNext: Bool = true,
        canNavigatePrevious: Bool = true,
        pendingAdvance: Binding<NavigationDirection?>,
        onNavigate: @escaping (_ direction: NavigationDirection) -> Void,
        onAutoAdvanceComplete: @escaping () -> Void,
        @ViewBuilder content: @escaping (_ index: Int) -> Content,
        @ViewBuilder background: @escaping (_ currentIndex: Int, _ progress: CGFloat) -> Background
    ) {
        self._currentIndex = currentIndex
        self.itemCount = itemCount
        self.canNavigate = canNavigate
        self.canNavigateNext = canNavigateNext
        self.canNavigatePrevious = canNavigatePrevious
        self._pendingAdvance = pendingAdvance
        self.onNavigate = onNavigate
        self.onAutoAdvanceComplete = onAutoAdvanceComplete
        self.content = content
        self.background = background
    }
    
    /// Simplified initializer without auto-advance (for standalone use)
    init(
        currentIndex: Binding<Int>,
        itemCount: Int,
        canNavigate: Bool = true,
        canNavigateNext: Bool = true,
        canNavigatePrevious: Bool = true,
        onNavigate: @escaping (_ direction: NavigationDirection) -> Void,
        @ViewBuilder content: @escaping (_ index: Int) -> Content,
        @ViewBuilder background: @escaping (_ currentIndex: Int, _ progress: CGFloat) -> Background
    ) {
        self._currentIndex = currentIndex
        self.itemCount = itemCount
        self.canNavigate = canNavigate
        self.canNavigateNext = canNavigateNext
        self.canNavigatePrevious = canNavigatePrevious
        self._pendingAdvance = .constant(nil)
        self.onNavigate = onNavigate
        self.onAutoAdvanceComplete = nil
        self.content = content
        self.background = background
    }
}

// MARK: - Previews

#Preview("Vertical Pager - Transition Demo") {
    struct TransitionDemo: View {
        @State private var index = 0
        @State private var pendingAdvance: NavigationDirection? = nil
        
        private let colors: [Color] = [.blue, .purple, .orange, .green, .pink]
        private let items = ["First", "Second", "Third", "Fourth", "Fifth"]
        
        var body: some View {
            ZStack {
                VerticalPager(
                    currentIndex: $index,
                    itemCount: items.count,
                    canNavigate: true,
                    pendingAdvance: $pendingAdvance,
                    onNavigate: { _ in },
                    onAutoAdvanceComplete: {}
                ) { itemIndex in
                    VStack(spacing: 20) {
                        Text(items[itemIndex])
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(.white)
                        
                        Text("Page \(itemIndex + 1) of \(items.count)")
                            .foregroundStyle(.white.opacity(0.7))
                        
                        Text("Swipe up/down")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } background: { currentIndex, progress in
                    let currentColor = colors[currentIndex]
                    let nextIndex = min(currentIndex + 1, colors.count - 1)
                    let prevIndex = max(currentIndex - 1, 0)
                    let targetColor = progress > 0 ? colors[nextIndex] : colors[prevIndex]
                    let t = min(abs(progress), 1.0)
                    
                    ZStack {
                        currentColor
                        targetColor.opacity(Double(t))
                    }
                    .ignoresSafeArea()
                }
            }
        }
    }
    
    return TransitionDemo()
}

#Preview("Vertical Pager - Auto Advance Demo") {
    struct AutoAdvanceDemo: View {
        @State private var index = 0
        @State private var pendingAdvance: NavigationDirection? = nil
        private let items = ["First", "Second", "Third", "Fourth", "Fifth"]
        
        var body: some View {
            ZStack {
                VerticalPager(
                    currentIndex: $index,
                    itemCount: items.count,
                    canNavigate: true,
                    pendingAdvance: $pendingAdvance,
                    onNavigate: { _ in },
                    onAutoAdvanceComplete: {
                        // Auto-continue after 1 second
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            if index < items.count - 1 {
                                pendingAdvance = .next
                            }
                        }
                    }
                ) { itemIndex in
                    VStack(spacing: 20) {
                        Text(items[itemIndex])
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(.white)
                        
                        Text("Page \(itemIndex + 1) of \(items.count)")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } background: { _, _ in
                    Color.blue.ignoresSafeArea()
                }
                
                VStack {
                    Spacer()
                    Button("Start Auto-Advance") {
                        pendingAdvance = .next
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 50)
                }
            }
        }
    }
    
    return AutoAdvanceDemo()
}
