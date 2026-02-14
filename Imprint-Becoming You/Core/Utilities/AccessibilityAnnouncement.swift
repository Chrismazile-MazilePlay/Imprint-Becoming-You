//
//  AccessibilityAnnouncement.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/31/26.
//

import UIKit

// MARK: - AccessibilityAnnouncement

/// Utility for VoiceOver announcements during dynamic state changes.
///
/// Use this utility to announce state changes that aren't automatically
/// detected by VoiceOver, such as score calculations, session completions,
/// and mode transitions.
///
/// ## Usage
///
/// ```swift
/// // Announce a score
/// AccessibilityAnnouncement.announce("Score: 85 percent. Great job!")
///
/// // Announce with delay
/// AccessibilityAnnouncement.announce("Processing complete", delay: 0.3)
///
/// // Notify screen layout changed
/// AccessibilityAnnouncement.screenChanged()
///
/// // Notify layout changed
/// AccessibilityAnnouncement.layoutChanged()
/// ```
///
/// ## Thread Safety
///
/// All methods dispatch to the main thread if needed, making them safe
/// to call from any context.
public enum AccessibilityAnnouncement {
    
    // MARK: - Announcements
    
    /// Announces a message to VoiceOver users.
    ///
    /// The announcement is queued and will be spoken after any current speech
    /// completes. Use sparingly to avoid overwhelming users with audio.
    ///
    /// - Parameter message: The message to announce
    public static func announce(_ message: String) {
        Task { @MainActor in
            UIAccessibility.post(
                notification: .announcement,
                argument: message
            )
        }
    }
    
    /// Announces a message to VoiceOver users after a delay.
    ///
    /// Use when you need to wait for other VoiceOver speech to complete
    /// before making an announcement, such as after a screen transition.
    ///
    /// - Parameters:
    ///   - message: The message to announce
    ///   - delay: Time interval to wait before announcing (default: 0.1)
    public static func announce(_ message: String, delay: TimeInterval) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            UIAccessibility.post(
                notification: .announcement,
                argument: message
            )
        }
    }
    
    /// Notifies VoiceOver that the screen content has changed significantly.
    ///
    /// Use when navigating to a new "screen" or when the entire content
    /// has been replaced. VoiceOver will read the new content from the
    /// first accessible element.
    ///
    /// - Parameter focusElement: Optional element to focus after the change
    public static func screenChanged(focusElement: Any? = nil) {
        Task { @MainActor in
            UIAccessibility.post(
                notification: .screenChanged,
                argument: focusElement
            )
        }
    }
    
    /// Notifies VoiceOver that part of the screen layout has changed.
    ///
    /// Use when content is added, removed, or repositioned without
    /// changing the overall screen context.
    ///
    /// - Parameter focusElement: Optional element to focus after the change
    public static func layoutChanged(focusElement: Any? = nil) {
        Task { @MainActor in
            UIAccessibility.post(
                notification: .layoutChanged,
                argument: focusElement
            )
        }
    }
}

// MARK: - Practice Session Announcements

public extension AccessibilityAnnouncement {
    
    /// Announces the start of a practice session.
    ///
    /// - Parameter mode: The session mode name (e.g., "Read Aloud")
    static func announceSessionStarted(mode: String) {
        announce("Starting \(mode) session")
    }
    
    /// Announces navigation to a new affirmation.
    ///
    /// - Parameters:
    ///   - current: Current affirmation index (1-based)
    ///   - total: Total number of affirmations
    static func announceAffirmationChanged(current: Int, total: Int) {
        announce("Affirmation \(current) of \(total)")
    }
    
    /// Announces navigation within a session using 0-based index.
    ///
    /// - Parameters:
    ///   - currentIndex: Current affirmation index (0-based)
    ///   - totalCount: Total affirmations in session
    static func announceNavigation(currentIndex: Int, totalCount: Int) {
        announce("Affirmation \(currentIndex + 1) of \(totalCount)")
    }
    
    /// Announces a resonance score with descriptive feedback.
    ///
    /// - Parameter score: The score percentage (0-100)
    static func announceScore(_ score: Int) {
        let description: String
        switch score {
        case 90...100:
            description = "Excellent! \(score) percent resonance"
        case 70..<90:
            description = "Good job! \(score) percent resonance"
        case 50..<70:
            description = "\(score) percent. Keep practicing!"
        default:
            description = "\(score) percent. Try speaking with more conviction"
        }
        announce(description)
    }
    
    /// Announces session completion.
    static func announceSessionComplete() {
        announce("Session complete. Showing results.")
        screenChanged()
    }
    
    /// Announces session completion with summary.
    ///
    /// - Parameter affirmationCount: Number of affirmations practiced
    static func announceSessionComplete(
        affirmationCount: Int
    ) {
        var message = "Session complete. You practiced \(affirmationCount) affirmation"
        if affirmationCount != 1 {
            message += "s"
        }
        message += "."

        announce(message, delay: 0.3)

        // Post screen change after announcement
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            screenChanged()
        }
    }
    
    /// Announces that listening has started.
    static func announceListeningStarted() {
        announce("Listening. Speak now.")
    }
    
    /// Announces that TTS playback has started.
    ///
    /// - Parameter text: Optional short description of what's playing
    static func announcePlaybackStarted(text: String? = nil) {
        if let text = text {
            announce("Playing: \(text)")
        } else {
            announce("Playing affirmation")
        }
    }
    
    /// Announces a mode change.
    ///
    /// - Parameter mode: The new mode name
    static func announceModeChanged(to mode: String) {
        announce("Mode changed to \(mode)")
    }
    
    /// Announces a loop configuration change.
    ///
    /// - Parameter count: The new loop count
    static func announceLoopCountChanged(to count: Int) {
        let message = count == 1 ? "Single play" : "Looping \(count) times"
        announce(message)
    }
    
    /// Announces shuffle toggle.
    ///
    /// - Parameter enabled: Whether shuffle is now enabled
    static func announceShuffleToggled(enabled: Bool) {
        announce(enabled ? "Shuffle enabled" : "Shuffle disabled")
    }
    
    /// Announces background music category change.
    ///
    /// - Parameter preset: The new preset name
    static func announceMusicChanged(to preset: String) {
        announce("Background music: \(preset)")
    }
    
    /// Announces an error condition.
    ///
    /// - Parameter message: The error message to announce
    static func announceError(_ message: String) {
        announce("Error: \(message)")
    }
}
