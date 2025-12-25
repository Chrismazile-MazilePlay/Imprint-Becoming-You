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
///
/// ## Auto-Advance
/// Set `pendingAdvance` to trigger an animated transition. After the animation
/// completes, `onAutoAdvanceComplete` is called to continue any flow logic.
///
/// ## Visual During Drag UP (to next):
/// ```
/// ┌─────────────────────┐
/// │  Current (moves up) │ offset = dragOffset
/// ├─────────────────────┤
/// │  Next (slides in)   │ offset = screenHeight + dragOffset
/// └─────────────────────┘
/// ```
struct VerticalPager<Content: View, Background: View>: View {
    
    // MARK: - Properties
    
    /// Current item index (bound to source of truth)
    @Binding var currentIndex: Int
    
    /// Total number of items
    let itemCount: Int
    
    /// Whether navigation gestures are allowed
    let canNavigate: Bool
    
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
    
    // MARK: - Configuration
    
    private let navigationThreshold: CGFloat = 0.15
    private let velocityThreshold: CGFloat = 400
    private let boundaryResistance: CGFloat = 0.3
    private let animationDuration: Double = 0.35
    
    // MARK: - State
    
    @State private var dragOffset: CGFloat = 0
    @State private var isVerticalDrag: Bool = false
    @State private var gestureDirectionLocked: Bool = false
    @State private var screenHeight: CGFloat = 0
    @State private var isAutoAdvancing: Bool = false
    
    // MARK: - Computed
    
    private var canGoNext: Bool {
        currentIndex < itemCount - 1
    }
    
    private var canGoPrevious: Bool {
        currentIndex > 0
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let progress = height > 0 ? -dragOffset / height : 0
            
            ZStack {
                // Background layer (fixed position, color morphs)
                background(currentIndex, progress)
                
                // Content layers (both visible during drag/animation)
                contentLayers(screenHeight: height)
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
    }
    
    // MARK: - Content Layers
    
    @ViewBuilder
    private func contentLayers(screenHeight: CGFloat) -> some View {
        ZStack {
            // PREVIOUS content - visible when dragging DOWN (dragOffset > 0)
            if canGoPrevious && dragOffset > 0 {
                content(currentIndex - 1)
                    .offset(y: -screenHeight + dragOffset)
            }
            
            // CURRENT content - always visible, moves with drag
            content(currentIndex)
                .offset(y: dragOffset)
            
            // NEXT content - visible when dragging UP (dragOffset < 0)
            if canGoNext && dragOffset < 0 {
                content(currentIndex + 1)
                    .offset(y: screenHeight + dragOffset)
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
        // Cancel any pending auto-advance if user starts gesture
        if pendingAdvance != nil {
            pendingAdvance = nil
        }
        
        let horizontal = abs(value.translation.width)
        let vertical = abs(value.translation.height)
        
        // Lock gesture direction on first significant movement
        if !gestureDirectionLocked && (horizontal > 15 || vertical > 15) {
            isVerticalDrag = vertical > horizontal * 2
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
    
    /// Completes user-initiated navigation with animation
    private func completeUserNavigation(direction: NavigationDirection, screenHeight: CGFloat) {
        let targetOffset = direction == .next ? -screenHeight : screenHeight
        
        withAnimation(.spring(duration: animationDuration, bounce: 0.0)) {
            dragOffset = targetOffset
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration * 0.6) {
            dragOffset = 0
            currentIndex += (direction == .next ? 1 : -1)
            onNavigate?(direction)
        }
        
        HapticFeedback.selection()
    }
    
    // MARK: - Programmatic Auto-Advance
    
    /// Performs animated transition triggered programmatically
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
        
        // Clear pending and mark as auto-advancing
        pendingAdvance = nil
        isAutoAdvancing = true
        
        let targetOffset = direction == .next ? -screenHeight : screenHeight
        
        // Animate to target position
        withAnimation(.spring(duration: animationDuration, bounce: 0.0)) {
            dragOffset = targetOffset
        }
        
        // Update index and trigger continuation after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration * 0.6) {
            dragOffset = 0
            currentIndex += (direction == .next ? 1 : -1)
            isAutoAdvancing = false
            
            // Call completion handler to continue flow
            onAutoAdvanceComplete?()
        }
    }
}

// MARK: - Navigation Direction

/// Direction of pager navigation
enum NavigationDirection: Sendable, Equatable {
    case next
    case previous
}

// MARK: - Convenience Initializers

extension VerticalPager {
    
    /// Full initializer with auto-advance support
    init(
        currentIndex: Binding<Int>,
        itemCount: Int,
        canNavigate: Bool = true,
        pendingAdvance: Binding<NavigationDirection?>,
        onNavigate: @escaping (_ direction: NavigationDirection) -> Void,
        onAutoAdvanceComplete: @escaping () -> Void,
        @ViewBuilder content: @escaping (_ index: Int) -> Content,
        @ViewBuilder background: @escaping (_ currentIndex: Int, _ progress: CGFloat) -> Background
    ) {
        self._currentIndex = currentIndex
        self.itemCount = itemCount
        self.canNavigate = canNavigate
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
        onNavigate: @escaping (_ direction: NavigationDirection) -> Void,
        @ViewBuilder content: @escaping (_ index: Int) -> Content,
        @ViewBuilder background: @escaping (_ currentIndex: Int, _ progress: CGFloat) -> Background
    ) {
        self._currentIndex = currentIndex
        self.itemCount = itemCount
        self.canNavigate = canNavigate
        self._pendingAdvance = .constant(nil)
        self.onNavigate = onNavigate
        self.onAutoAdvanceComplete = nil
        self.content = content
        self.background = background
    }
}

// MARK: - Previews

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
