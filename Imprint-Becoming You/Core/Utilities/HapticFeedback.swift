//
//  HapticFeedback.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/21/25.
//

import UIKit

// MARK: - HapticFeedback

/// Centralized haptic feedback utilities with optimized generator lifecycle.
///
/// Provides instant tactile responses by keeping generators prepared with
/// intelligent re-preparation to avoid CoreHaptics warnings.
///
/// ## Optimization Strategy
///
/// Rather than calling `prepare()` after every haptic (which can cause
/// -4805 errors when haptics fire rapidly), this implementation:
/// - Prepares generators lazily on first access
/// - Re-prepares via a debounced timer after haptic bursts settle
/// - Throttles rapid successive calls to prevent engine overload
///
/// ## Thread Safety
///
/// UIKit's feedback generators are internally thread-safe. This enum
/// can be called from any thread; internal state management uses
/// MainActor isolation where necessary.
///
/// ## Why Pre-Warming Matters
/// iOS's Taptic Engine requires ~50-100ms to wake from cold state.
/// By calling `prepare()` in advance, the first haptic is instant.
///
/// ## Usage
/// ```swift
/// // At app launch or view appearance
/// HapticFeedback.warmUp()
///
/// // Selection changed (light tap)
/// HapticFeedback.selection()
///
/// // Button press (medium impact)
/// HapticFeedback.impact(.medium)
///
/// // Success/error notification
/// HapticFeedback.notification(.success)
/// ```
enum HapticFeedback {
    
    // MARK: - Configuration
    
    /// Minimum interval between haptics of the same type (prevents rapid-fire issues).
    private static let minimumInterval: TimeInterval = 0.05
    
    /// Delay before re-preparing generators after a haptic burst.
    private static let preparationDelay: TimeInterval = 0.3
    
    // MARK: - Generators (Lazy Initialized)
    
    /// Using `nonisolated(unsafe)` for static storage.
    /// UIKit feedback generators are internally thread-safe.
    nonisolated(unsafe) private static var selectionGenerator: UISelectionFeedbackGenerator?
    nonisolated(unsafe) private static var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
    nonisolated(unsafe) private static var notificationGenerator: UINotificationFeedbackGenerator?
    
    // MARK: - Throttling State
    
    nonisolated(unsafe) private static var lastHapticTimes: [String: Date] = [:]
    nonisolated(unsafe) private static var preparationTimer: Timer?
    
    // MARK: - Warm Up
    
    /// Prepares all haptic generators for instant feedback.
    ///
    /// Call this early in the app lifecycle (e.g., `onAppear` of root view)
    /// to ensure the Taptic Engine is ready before first user interaction.
    ///
    /// Safe to call multiple times - generators remain prepared.
    static func warmUp() {
        Task { @MainActor in
            // Create and prepare selection generator
            if selectionGenerator == nil {
                selectionGenerator = UISelectionFeedbackGenerator()
            }
            selectionGenerator?.prepare()
            
            // Create and prepare common impact generators
            let commonStyles: [UIImpactFeedbackGenerator.FeedbackStyle] = [.light, .medium, .heavy]
            for style in commonStyles {
                if impactGenerators[style] == nil {
                    impactGenerators[style] = UIImpactFeedbackGenerator(style: style)
                }
                impactGenerators[style]?.prepare()
            }
            
            // Create and prepare notification generator
            if notificationGenerator == nil {
                notificationGenerator = UINotificationFeedbackGenerator()
            }
            notificationGenerator?.prepare()
        }
    }
    
    // MARK: - Selection
    
    /// Light haptic for selection changes (toggles, picks).
    ///
    /// Throttled to prevent rapid-fire issues.
    static func selection() {
        guard shouldAllowHaptic(type: "selection") else { return }
        
        // Ensure generator exists
        if selectionGenerator == nil {
            selectionGenerator = UISelectionFeedbackGenerator()
            selectionGenerator?.prepare()
        }
        
        selectionGenerator?.selectionChanged()
        recordHaptic(type: "selection")
        scheduleDebouncedPreparation()
    }
    
    // MARK: - Impact
    
    /// Impact haptic with configurable intensity.
    ///
    /// Throttled to prevent rapid-fire issues.
    ///
    /// - Parameter style: The impact style (.light, .medium, .heavy, .soft, .rigid)
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let typeKey = "impact_\(style.rawValue)"
        guard shouldAllowHaptic(type: typeKey) else { return }
        
        // Get or create generator for this style
        if impactGenerators[style] == nil {
            impactGenerators[style] = UIImpactFeedbackGenerator(style: style)
            impactGenerators[style]?.prepare()
        }
        
        impactGenerators[style]?.impactOccurred()
        recordHaptic(type: typeKey)
        scheduleDebouncedPreparation()
    }
    
    /// Light impact - subtle tap.
    static func light() {
        impact(.light)
    }
    
    /// Medium impact - standard button press.
    static func medium() {
        impact(.medium)
    }
    
    /// Heavy impact - significant action.
    static func heavy() {
        impact(.heavy)
    }
    
    // MARK: - Notification
    
    /// Notification haptic for success/warning/error feedback.
    ///
    /// Throttled to prevent rapid-fire issues.
    ///
    /// - Parameter type: The notification type (.success, .warning, .error)
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let typeKey = "notification_\(type.rawValue)"
        guard shouldAllowHaptic(type: typeKey) else { return }
        
        // Ensure generator exists
        if notificationGenerator == nil {
            notificationGenerator = UINotificationFeedbackGenerator()
            notificationGenerator?.prepare()
        }
        
        notificationGenerator?.notificationOccurred(type)
        recordHaptic(type: typeKey)
        scheduleDebouncedPreparation()
    }
    
    /// Success notification - task completed.
    static func success() {
        notification(.success)
    }
    
    /// Warning notification - caution needed.
    static func warning() {
        notification(.warning)
    }
    
    /// Error notification - something went wrong.
    static func error() {
        notification(.error)
    }
    
    // MARK: - Throttling Helpers
    
    /// Checks if enough time has passed since the last haptic of this type.
    private static func shouldAllowHaptic(type: String) -> Bool {
        guard let lastTime = lastHapticTimes[type] else {
            return true
        }
        return Date().timeIntervalSince(lastTime) >= minimumInterval
    }
    
    /// Records when a haptic was triggered.
    private static func recordHaptic(type: String) {
        lastHapticTimes[type] = Date()
    }
    
    // MARK: - Debounced Preparation
    
    /// Schedules a delayed re-preparation of all generators.
    ///
    /// This is called after each haptic. If another haptic fires before
    /// the timer completes, the timer resets. This prevents excessive
    /// `prepare()` calls during rapid haptic bursts.
    private static func scheduleDebouncedPreparation() {
        // Must schedule timer on main thread
        DispatchQueue.main.async {
            // Cancel any existing timer
            preparationTimer?.invalidate()
            
            // Schedule new preparation after delay
            preparationTimer = Timer.scheduledTimer(withTimeInterval: preparationDelay, repeats: false) { _ in
                prepareAllGenerators()
            }
        }
    }
    
    /// Re-prepares all existing generators.
    private static func prepareAllGenerators() {
        selectionGenerator?.prepare()
        impactGenerators.values.forEach { $0.prepare() }
        notificationGenerator?.prepare()
    }
}
