//
//  DockMenuDismissModifier.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/20/26.
//

import SwiftUI

// MARK: - DockMenuDismissModifier

/// ViewModifier that dismisses expanded dock menus on touch.
///
/// Uses `.simultaneousGesture` with `DragGesture(minimumDistance: 0)` to:
/// - Fire immediately on touch (like UIKit's `touchesBegan`)
/// - Allow underlying scroll/swipe gestures to continue
///
/// ## Usage
/// Apply to the main content area in parent views:
/// ```swift
/// ZStack {
///     scrollableContent
/// }
/// .dismissesDockMenuOnTouch(adapter: dockAdapter)
/// .overlay {
///     VStack {
///         Spacer()
///         AdaptiveDockContainer(...)
///     }
///     .ignoresSafeArea(edges: .bottom)
/// }
/// ```
public struct DockMenuDismissModifier: ViewModifier {
    
    // MARK: - Properties
    
    public let adapter: any DockAdapterProtocol
    
    // MARK: - Body
    
    public func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if adapter.isModeSelectorExpanded || adapter.isBinauralSelectorExpanded || adapter.isErrorBarVisible {
                            withAnimation(.easeOut(duration: 0.2)) {
                                adapter.closeAllSelectors()
                            }
                        }
                    }
            )
    }
}

// MARK: - View Extension

public extension View {
    /// Dismisses any expanded dock menus when the user touches this view.
    ///
    /// Apply to the main content area (ScrollView, VerticalPager, etc.) so that
    /// touching outside the dock dismisses expanded menus while still allowing
    /// scroll/swipe gestures to function.
    ///
    /// - Parameter adapter: The dock adapter to monitor and control
    /// - Returns: A view that dismisses dock menus on touch
    func dismissesDockMenuOnTouch(adapter: any DockAdapterProtocol) -> some View {
        modifier(DockMenuDismissModifier(adapter: adapter))
    }
}
