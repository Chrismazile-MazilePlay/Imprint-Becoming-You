//
//  HapticFeedback.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/21/25.
//

import UIKit

// MARK: - HapticFeedback

/// Centralized haptic feedback utilities with pre-warmed generators.
///
/// Provides instant tactile responses by keeping generators prepared.
/// Call `warmUp()` early (e.g., at app launch or view appearance) for
/// zero-latency feedback on first interaction.
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
    
    // MARK: - Pre-Warmed Generators
    
    /// Pre-warmed selection generator for instant feedback.
    /// Using `nonisolated(unsafe)` because UIKit haptic generators
    /// are internally thread-safe and we only mutate during warmUp.
    nonisolated(unsafe) private static var selectionGenerator: UISelectionFeedbackGenerator = {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        return generator
    }()
    
    /// Pre-warmed impact generators by style.
    nonisolated(unsafe) private static var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = {
        var generators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
        for style in [UIImpactFeedbackGenerator.FeedbackStyle.light, .medium, .heavy, .soft, .rigid] {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generators[style] = generator
        }
        return generators
    }()
    
    /// Pre-warmed notification generator.
    nonisolated(unsafe) private static var notificationGenerator: UINotificationFeedbackGenerator = {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        return generator
    }()
    
    // MARK: - Warm Up
    
    /// Prepares all haptic generators for instant feedback.
    ///
    /// Call this early in the app lifecycle (e.g., `onAppear` of root view)
    /// to ensure the Taptic Engine is ready before first user interaction.
    ///
    /// Safe to call multiple times - generators remain prepared.
    @MainActor
    static func warmUp() {
        // Access lazy-initialized generators to trigger creation
        _ = selectionGenerator
        _ = impactGenerators
        _ = notificationGenerator
        
        // Re-prepare in case they went cold
        selectionGenerator.prepare()
        impactGenerators.values.forEach { $0.prepare() }
        notificationGenerator.prepare()
    }
    
    // MARK: - Selection
    
    /// Light haptic for selection changes (toggles, picks).
    ///
    /// Uses pre-warmed generator for instant feedback.
    static func selection() {
        selectionGenerator.selectionChanged()
        // Re-prepare for next use
        selectionGenerator.prepare()
    }
    
    // MARK: - Impact
    
    /// Impact haptic with configurable intensity.
    ///
    /// Uses pre-warmed generators for instant feedback.
    ///
    /// - Parameter style: The impact style (.light, .medium, .heavy, .soft, .rigid)
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard let generator = impactGenerators[style] else {
            // Fallback for unexpected style
            let fallback = UIImpactFeedbackGenerator(style: style)
            fallback.impactOccurred()
            return
        }
        generator.impactOccurred()
        // Re-prepare for next use
        generator.prepare()
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
    /// Uses pre-warmed generator for instant feedback.
    ///
    /// - Parameter type: The notification type (.success, .warning, .error)
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationGenerator.notificationOccurred(type)
        // Re-prepare for next use
        notificationGenerator.prepare()
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
}
