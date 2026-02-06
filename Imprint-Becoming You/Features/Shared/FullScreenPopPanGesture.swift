//
//  FullScreenPopPanGesture.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/3/26.
//

import SwiftUI
import UIKit

// MARK: - View Extension

extension View {
    /// Enables full-screen interactive pop gesture on the parent `NavigationStack`.
    ///
    /// By default, `NavigationStack`'s back gesture only works from the left
    /// screen edge (~20pt). This modifier installs a full-screen pan gesture
    /// that triggers the same native interactive pop transition, allowing users
    /// to swipe back from anywhere on the screen.
    ///
    /// Apply this modifier to a view **inside** a `NavigationStack`:
    /// ```swift
    /// NavigationStack(path: $path) {
    ///     rootContent
    ///         .fullScreenPopGesture()
    ///         .navigationDestination(for: Destination.self) { ... }
    /// }
    /// ```
    ///
    /// ## Gesture Priority
    /// The pop gesture only fires for rightward horizontal swipes when the
    /// navigation stack has views to pop (`viewControllers.count > 1`). All
    /// other pan gestures (vertical `ScrollView`s, `SwipeAction`s) defer until
    /// the pop gesture resolves direction, then proceed normally if the pop
    /// gesture doesn't fire.
    ///
    /// ## Implementation Note
    /// This reuses `UINavigationController.interactivePopGestureRecognizer`'s
    /// internal target-action pair to drive the native interactive transition.
    /// This is a widely adopted pattern across production iOS apps (WeChat,
    /// Instagram, etc.) and has been stable across all iOS versions. However,
    /// it relies on an internal UIKit detail (`value(forKey: "targets")`) that
    /// could theoretically change in a future iOS release.
    func fullScreenPopGesture() -> some View {
        background(FullScreenPopGestureFinder())
    }
}

// MARK: - Gesture Recognizer Subclass

/// Identifiable `UIPanGestureRecognizer` subclass for idempotent installation.
///
/// Used to detect whether the full-screen pop gesture has already been installed
/// on a given `UINavigationController`, preventing duplicate gestures from
/// SwiftUI view update cycles.
private class FullScreenPopPanGesture: UIPanGestureRecognizer {}

// MARK: - UIViewRepresentable

/// Hidden `UIViewRepresentable` that locates the parent `UINavigationController`
/// and installs a full-screen pop gesture recognizer on it.
///
/// Placed as a `.background()` inside a `NavigationStack`'s content so that
/// the responder chain from this view passes through the navigation controller.
private struct FullScreenPopGestureFinder: UIViewRepresentable {
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isHidden = true
        view.isUserInteractionEnabled = false
        
        // Defer to next run loop -- NavigationStack's UINavigationController
        // may not be fully installed in the view hierarchy yet.
        DispatchQueue.main.async {
            context.coordinator.install(from: view)
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // MARK: - Coordinator
    
    /// Manages the full-screen pop gesture lifecycle and delegates direction filtering.
    ///
    /// ## Gesture Resolution Flow
    ///
    /// When a pan gesture begins anywhere in the navigation controller's view:
    ///
    /// 1. All child pan gestures (ScrollViews, SwipeActions) defer to ours
    ///    via `shouldBeRequiredToFailBy` returning `true`.
    /// 2. Our `gestureRecognizerShouldBegin` evaluates the swipe direction.
    /// 3a. **Rightward horizontal**: Our gesture succeeds -> deferred gestures
    ///     fail -> clean pop transition with no competing scroll/swipe.
    /// 3b. **Not rightward / vertical / at root**: Our gesture fails -> deferred
    ///     gestures proceed -> normal scrolling and SwipeAction behavior.
    ///
    /// The direction evaluation happens within the first few pixels of movement,
    /// so the deferral is imperceptible.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        
        /// Weak reference to the navigation controller for depth checking.
        private weak var navigationController: UINavigationController?
        
        // MARK: - Installation
        
        /// Finds the parent `UINavigationController` from the given view and
        /// installs a full-screen pop gesture recognizer.
        func install(from view: UIView) {
            guard let navigationController = view.findNavigationController() else {
                #if DEBUG
                AppLogger.warning("UINavigationController not found in responder chain", category: .ui)
                #endif
                return
            }
            
            self.navigationController = navigationController
            
            // Idempotency: check if already installed (SwiftUI view updates
            // can trigger makeUIView/updateUIView multiple times)
            let alreadyInstalled = navigationController.view.gestureRecognizers?
                .contains(where: { $0 is FullScreenPopPanGesture }) ?? false
            guard !alreadyInstalled else { return }
            
            // Match the navigation controller's background to the app's
            // background color. During the interactive pop transition, UIKit
            // constructs a UITransitionView with the navigation controller's
            // view.backgroundColor as the canvas behind both view controllers.
            // If this doesn't match the app's true-black background (#000000),
            // a visible color fringe appears at the edge of the sliding view
            // where the default systemBackground (#1C1C1E) peeks through.
            navigationController.view.backgroundColor = UIColor(named: "backgroundPrimary")
            
            // Copy targets from the built-in interactivePopGestureRecognizer.
            // These targets drive the native interactive pop transition animation
            // (parallax slide with underlying view peek).
            guard let interactivePopGesture = navigationController.interactivePopGestureRecognizer,
                  let targets = interactivePopGesture.value(forKey: "targets") else {
                #if DEBUG
                AppLogger.warning("Cannot access interactivePopGestureRecognizer targets", category: .ui)
                #endif
                return
            }
            
            let fullScreenGesture = FullScreenPopPanGesture()
            fullScreenGesture.setValue(targets, forKey: "targets")
            fullScreenGesture.delegate = self
            navigationController.view.addGestureRecognizer(fullScreenGesture)
            
            // Disable the edge-only gesture to prevent duplicate pop inputs.
            // Our full-screen gesture covers the entire screen including the edge.
            interactivePopGesture.isEnabled = false
        }
        
        // MARK: - UIGestureRecognizerDelegate
        
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // Nothing to pop at root level -- let the pager handle swipes
            guard let navigationController = navigationController,
                  navigationController.viewControllers.count > 1 else {
                return false
            }
            
            // Don't begin during an active transition (prevents double-pop)
            guard navigationController.transitionCoordinator == nil else {
                return false
            }
            
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else {
                return false
            }
            
            let velocity = pan.velocity(in: pan.view)
            
            // Only allow rightward swipes (back direction in LTR).
            // Horizontal component must dominate vertical to avoid triggering
            // on diagonal scrolls or vertical swipe-ups/downs.
            return velocity.x > 0 && abs(velocity.x) > abs(velocity.y)
        }
        
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Make other pan gestures defer to our gesture.
            //
            // This is called dynamically by UIKit for EVERY gesture recognizer
            // in the navigation controller's view hierarchy, including ones in
            // lazily-loaded destination views. No manual view walking needed.
            //
            // - Rightward horizontal -> our gesture succeeds, deferred pans fail
            //   -> clean pop with no competing scroll/swipe
            // - Not rightward -> our gesture fails, deferred pans proceed
            //   -> normal ScrollView and SwipeAction behavior
            //
            // Only defer UIPanGestureRecognizer subclasses. Tap gestures, long
            // press gestures, etc. should fire independently and immediately.
            otherGestureRecognizer is UIPanGestureRecognizer
        }
        
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Exclusive recognition -- when we fire, nothing else should.
            // The failure requirement from shouldBeRequiredToFailBy ensures
            // other gestures are already in a waiting/failed state.
            false
        }
    }
}

// MARK: - UIView Navigation Controller Finder

private extension UIView {
    /// Walks the responder chain to find the nearest `UINavigationController`.
    ///
    /// The responder chain for views inside a `NavigationStack` passes through:
    /// `UIView -> ... -> UIViewController -> UINavigationController`
    func findNavigationController() -> UINavigationController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let navController = next as? UINavigationController {
                return navController
            }
            responder = next
        }
        return nil
    }
}
