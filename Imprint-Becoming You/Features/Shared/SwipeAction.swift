//
//  SwipeAction.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/1/26.
//

import SwiftUI

// MARK: - SwipeAction Model

/// Model representing a single swipe action button.
struct SwipeAction: Identifiable {
    var id = UUID().uuidString
    var symbolImage: String
    var tint: Color
    var background: Color
    var font: Font = .title3
    var size: CGSize = CGSize(width: 45, height: 45)
    var shape: AnyShape = AnyShape(.circle)
    /// Action callback. Set the inout Bool to true to reset swipe position.
    var action: (inout Bool) -> Void
}

// MARK: - SwipeAction Builder

/// Result builder for declarative swipe action syntax.
@resultBuilder
struct SwipeActionBuilder {
    static func buildBlock(_ components: SwipeAction...) -> [SwipeAction] {
        return components
    }
}

// MARK: - SwipeAction Configuration

/// Configuration options for swipe action behavior and layout.
struct SwipeActionConfig {
    var leadingPadding: CGFloat = 0
    var trailingPadding: CGFloat = 10
    var spacing: CGFloat = 10
    var occupiesFullWidth: Bool = true
    /// Threshold multiplier for full-swipe (0.0 - 1.0 of screen width)
    var fullSwipeThreshold: CGFloat = 0.6
    /// Whether full-swipe is enabled
    var fullSwipeEnabled: Bool = true
}

// MARK: - View Extension

extension View {
    /// Adds swipe actions to the view.
    ///
    /// - Parameters:
    ///   - config: Configuration for swipe behavior
    ///   - isEnabled: Whether swipe is enabled (disabled during edit mode)
    ///   - onFullSwipe: Callback when full-swipe threshold is exceeded
    ///   - actions: Builder closure providing swipe actions
    @ViewBuilder
    func swipeActions(
        config: SwipeActionConfig = .init(),
        isEnabled: Bool = true,
        onFullSwipe: (() -> Void)? = nil,
        @SwipeActionBuilder actions: () -> [SwipeAction]
    ) -> some View {
        if isEnabled {
            self.modifier(
                SwipeActionModifier(
                    config: config,
                    actions: actions(),
                    onFullSwipe: onFullSwipe
                )
            )
        } else {
            self
        }
    }
}

// MARK: - Shared State

/// Shared state to coordinate swipe actions across multiple cards.
/// Ensures only one card can be swiped open at a time.
@MainActor
@Observable
final class SwipeActionSharedState {
    static let shared = SwipeActionSharedState()
    private init() {}
    
    var activeSwipeActionId: String?
}

// MARK: - SwipeAction Modifier

/// View modifier that implements the swipe action behavior.
struct SwipeActionModifier: ViewModifier {
    let config: SwipeActionConfig
    let actions: [SwipeAction]
    let onFullSwipe: (() -> Void)?
    
    // MARK: - Initialization
    
    init(config: SwipeActionConfig, actions: [SwipeAction], onFullSwipe: (() -> Void)?) {
        self.config = config
        self.actions = actions
        self.onFullSwipe = onFullSwipe
    }
    
    // MARK: - State
    
    @State private var resetPositionTrigger: Bool = false
    @State private var offsetX: CGFloat = 0
    @State private var lastStoredOffsetX: CGFloat = 0
    @State private var bounceOffset: CGFloat = 0
    @State private var progress: CGFloat = 0
    
    /// Tracks if user has crossed full-swipe threshold (for haptic)
    @State private var hasTriggeredFullSwipeHaptic: Bool = false
    
    // MARK: - Scroll Tracking
    
    @State private var storedScrollOffset: CGFloat?
    
    // MARK: - Shared State
    
    private var sharedState = SwipeActionSharedState.shared
    @State private var currentId: String = UUID().uuidString
    
    // MARK: - iOS 17 Gesture State
    
    @GestureState private var isDragging: Bool = false
    
    /// Tracks if the initial gesture direction was determined to be horizontal
    @State private var isHorizontalGesture: Bool?
    
    // MARK: - Computed Properties
    
    /// Maximum offset width based on action sizes
    private var maxOffsetWidth: CGFloat {
        let totalActionSize = actions.reduce(CGFloat.zero) { result, action in
            result + action.size.width
        }
        let spacing = config.spacing * CGFloat(actions.count - 1)
        return totalActionSize + spacing + config.leadingPadding + config.trailingPadding
    }
    
    /// Full swipe threshold in points
    private var fullSwipeThresholdPoints: CGFloat {
        UIScreen.main.bounds.width * config.fullSwipeThreshold
    }
    
    // MARK: - Body
    
    func body(content: Content) -> some View {
        Group {
            if #available(iOS 18, *) {
                iOS18Content(content: content)
            } else {
                iOS17Content(content: content)
            }
        }
        .onChange(of: resetPositionTrigger) { _, _ in
            reset()
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.frame(in: .scrollView).minY
        } action: { newValue in
            if let storedScrollOffset, storedScrollOffset != newValue {
                reset()
            }
        }
        .onChange(of: sharedState.activeSwipeActionId) { _, newValue in
            if newValue != currentId && offsetX != 0 {
                reset()
            }
        }
    }
    
    // MARK: - iOS 18+ Content
    
    @available(iOS 18, *)
    @ViewBuilder
    private func iOS18Content(content: Content) -> some View {
        content
            .overlay {
                Rectangle()
                    .foregroundStyle(.clear)
                    .containerRelativeFrame(config.occupiesFullWidth ? .horizontal : .init())
                    .overlay(alignment: .trailing) {
                        actionsView
                    }
            }
            .compositingGroup()
            .offset(x: offsetX)
            .offset(x: bounceOffset)
            .mask {
                Rectangle()
                    .containerRelativeFrame(config.occupiesFullWidth ? .horizontal : .init())
            }
            .gesture(
                PanGesture(
                    onBegan: { gestureDidBegin() },
                    onChange: { value in gestureDidChange(translation: value.translation) },
                    onEnded: { value in gestureDidEnd(translation: value.translation, velocity: value.velocity) }
                )
            )
    }
    
    // MARK: - iOS 17 Content
    
    @ViewBuilder
    private func iOS17Content(content: Content) -> some View {
        content
            .overlay {
                Rectangle()
                    .foregroundStyle(.clear)
                    .containerRelativeFrame(config.occupiesFullWidth ? .horizontal : .init())
                    .overlay(alignment: .trailing) {
                        actionsView
                    }
            }
            .compositingGroup()
            .offset(x: offsetX)
            .offset(x: bounceOffset)
            .mask {
                Rectangle()
                    .containerRelativeFrame(config.occupiesFullWidth ? .horizontal : .init())
            }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .updating($isDragging) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        // Determine gesture direction on first significant movement
                        if isHorizontalGesture == nil {
                            let horizontal = abs(value.translation.width)
                            let vertical = abs(value.translation.height)
                            isHorizontalGesture = horizontal > vertical
                        }
                        
                        // Only process horizontal swipes
                        if isHorizontalGesture == true {
                            gestureDidChange(translation: value.translation)
                        }
                    }
                    .onEnded { value in
                        if isHorizontalGesture == true {
                            gestureDidEnd(translation: value.translation, velocity: value.velocity)
                        } else {
                            // Reset if it was a vertical gesture
                            reset()
                        }
                        isHorizontalGesture = nil
                    }
            )
            .onChange(of: isDragging) { _, newValue in
                if newValue {
                    gestureDidBegin()
                }
            }
    }
    
    // MARK: - Actions View
    
    @ViewBuilder
    private var actionsView: some View {
        ZStack {
            ForEach(actions.indices, id: \.self) { index in
                let action = actions[index]
                
                GeometryReader { proxy in
                    let size = proxy.size
                    let spacing = config.spacing * CGFloat(index)
                    let offset = (CGFloat(index) * size.width) + spacing
                    
                    Button {
                        action.action(&resetPositionTrigger)
                    } label: {
                        Image(systemName: action.symbolImage)
                            .font(action.font)
                            .foregroundStyle(action.tint)
                            .frame(width: size.width, height: size.height)
                            .background(action.background, in: action.shape)
                    }
                    .offset(x: offset * progress)
                }
                .frame(width: action.size.width, height: action.size.height)
            }
        }
        .visualEffect { content, proxy in
            content.offset(x: proxy.size.width)
        }
        .offset(x: config.leadingPadding)
    }
    
    // MARK: - Gesture Handlers
    
    private func gestureDidBegin() {
        storedScrollOffset = lastStoredOffsetX
        sharedState.activeSwipeActionId = currentId
        hasTriggeredFullSwipeHaptic = false
    }
    
    private func gestureDidChange(translation: CGSize) {
        // Allow swiping left (negative) only, clamp to reasonable max
        let maxSwipe = fullSwipeThresholdPoints + 50
        offsetX = min(max(translation.width + lastStoredOffsetX, -maxSwipe), 0)
        progress = min(-offsetX / maxOffsetWidth, 1.5)
        
        // Bounce effect when pulling beyond the action buttons
        bounceOffset = min(translation.width - (offsetX - lastStoredOffsetX), 0) / 10
        
        // Full-swipe haptic feedback
        if config.fullSwipeEnabled && onFullSwipe != nil {
            let isPastThreshold = -offsetX >= fullSwipeThresholdPoints
            
            if isPastThreshold && !hasTriggeredFullSwipeHaptic {
                HapticFeedback.impact(.medium)
                hasTriggeredFullSwipeHaptic = true
            } else if !isPastThreshold && hasTriggeredFullSwipeHaptic {
                // User dragged back before threshold - clear haptic flag
                hasTriggeredFullSwipeHaptic = false
            }
        }
    }
    
    private func gestureDidEnd(translation: CGSize, velocity: CGSize) {
        let endTarget = velocity.width + offsetX
        
        // Check for full-swipe navigation
        if config.fullSwipeEnabled,
           let onFullSwipe,
           -offsetX >= fullSwipeThresholdPoints {
            // Full swipe triggered - reset position and navigate
            reset()
            onFullSwipe()
            return
        }
        
        withAnimation(.snappy(duration: 0.3, extraBounce: 0)) {
            if -endTarget > (maxOffsetWidth * 0.6) {
                // Snap to show actions
                offsetX = -maxOffsetWidth
                bounceOffset = 0
                progress = 1
            } else {
                // Reset to initial position
                reset()
            }
        }
        
        lastStoredOffsetX = offsetX
        hasTriggeredFullSwipeHaptic = false
    }
    
    private func reset() {
        withAnimation(.snappy(duration: 0.3, extraBounce: 0)) {
            offsetX = 0
            lastStoredOffsetX = 0
            progress = 0
            bounceOffset = 0
        }
        storedScrollOffset = nil
        hasTriggeredFullSwipeHaptic = false
    }
}

// MARK: - AnyShape Helper

/// Type-erased shape for SwipeAction background.
struct AnyShape: Shape, @unchecked Sendable {
    private let _path: @Sendable (CGRect) -> Path
    
    init<S: Shape>(_ shape: S) {
        _path = { rect in
            shape.path(in: rect)
        }
    }
    
    func path(in rect: CGRect) -> Path {
        _path(rect)
    }
}
