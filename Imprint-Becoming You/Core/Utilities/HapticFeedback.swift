//
//  HapticFeedback.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/21/25.
//

import UIKit

// MARK: - HapticFeedback

/// Centralized haptic feedback utilities.
///
/// Provides easy access to iOS haptic feedback generators
/// for consistent tactile responses throughout the app.
///
/// ## Usage
/// ```swift
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
    
    // MARK: - Selection
    
    /// Light haptic for selection changes (toggles, picks).
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
    
    // MARK: - Impact
    
    /// Impact haptic with configurable intensity.
    /// - Parameter style: The impact style (.light, .medium, .heavy, .soft, .rigid)
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
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
    /// - Parameter type: The notification type (.success, .warning, .error)
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
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
