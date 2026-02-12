//
//  AccessibilityModifiers.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/31/26.
//

import SwiftUI

// MARK: - Accessibility Announcement Modifiers

/// Declarative view modifiers for VoiceOver accessibility announcements.
///
/// These modifiers provide a SwiftUI-native way to handle accessibility
/// announcements, keeping accessibility logic within the view layer
/// rather than scattered throughout business logic.
///
/// ## Usage
///
/// ```swift
/// // Announce when a value changes
/// Text("Score: \(score)")
///     .announceOnChange(of: score) { newScore in
///         "Your score is \(newScore) percent"
///     }
///
/// // Announce practice flow state changes
/// PracticeContentView()
///     .announcePracticeFlow(store.flow)
///
/// // Announce screen navigation
/// ResultsSummaryView()
///     .announceScreenChange("Showing your results")
/// ```

extension View {
    
    // MARK: - Value Change Announcements
    
    /// Announces a message when a value changes.
    ///
    /// The announcement is made after a short delay to allow VoiceOver
    /// to complete any current speech.
    ///
    /// - Parameters:
    ///   - value: The value to observe for changes
    ///   - message: Closure that returns the announcement message, or nil to skip
    ///
    /// ## Example
    /// ```swift
    /// Text("Score: \(score)")
    ///     .announceOnChange(of: score) { newScore in
    ///         "Your score is \(newScore) percent"
    ///     }
    /// ```
    func announceOnChange<T: Equatable>(
        of value: T,
        message: @escaping (T) -> String?
    ) -> some View {
        modifier(AnnounceOnChangeModifier(value: value, message: message))
    }
    
    /// Announces a static message when a value changes.
    ///
    /// - Parameters:
    ///   - value: The value to observe for changes
    ///   - announcement: Static message to announce
    ///
    /// ## Example
    /// ```swift
    /// Button("Submit") { ... }
    ///     .announceOnChange(of: isSubmitting, announcement: "Submitting your response")
    /// ```
    func announceOnChange<T: Equatable>(
        of value: T,
        announcement: String
    ) -> some View {
        modifier(AnnounceOnChangeModifier(value: value) { _ in announcement })
    }
    
    /// Announces when a boolean becomes true.
    ///
    /// - Parameters:
    ///   - condition: Boolean to observe
    ///   - announcement: Message to announce when true
    ///
    /// ## Example
    /// ```swift
    /// ProgressView()
    ///     .announceWhenTrue(isLoading, announcement: "Loading content")
    /// ```
    func announceWhenTrue(
        _ condition: Bool,
        announcement: String
    ) -> some View {
        modifier(AnnounceOnChangeModifier(value: condition) { isTrue in
            isTrue ? announcement : nil
        })
    }
    
    /// Announces when a boolean becomes false.
    ///
    /// - Parameters:
    ///   - condition: Boolean to observe
    ///   - announcement: Message to announce when false
    func announceWhenFalse(
        _ condition: Bool,
        announcement: String
    ) -> some View {
        modifier(AnnounceOnChangeModifier(value: condition) { isTrue in
            isTrue ? nil : announcement
        })
    }
    
    // MARK: - Screen Change Announcements
    
    /// Posts a screen changed notification on appear.
    ///
    /// Use when navigating to a new screen to reset VoiceOver focus.
    ///
    /// ## Example
    /// ```swift
    /// ResultsSummaryView()
    ///     .announceScreenChange()
    /// ```
    func announceScreenChange() -> some View {
        modifier(ScreenChangeModifier())
    }
    
    /// Announces a message and posts screen changed on appear.
    ///
    /// - Parameter message: Message to announce after screen change
    ///
    /// ## Example
    /// ```swift
    /// OnboardingView()
    ///     .announceScreenChange("Welcome to Imprint")
    /// ```
    func announceScreenChange(_ message: String) -> some View {
        modifier(ScreenChangeWithMessageModifier(message: message))
    }
    
    // MARK: - Practice Flow Announcements
    
    /// Announces practice flow state changes with appropriate messages.
    ///
    /// Automatically generates VoiceOver-friendly descriptions for each flow state.
    /// Filters out redundant announcements (e.g., progress updates within the same phase).
    ///
    /// - Parameter flow: The current PracticeFlow state
    ///
    /// ## Example
    /// ```swift
    /// PracticeContentView()
    ///     .announcePracticeFlow(store.flow)
    /// ```
    func announcePracticeFlow(_ flow: PracticeFlow) -> some View {
        modifier(PracticeFlowAnnouncementModifier(flow: flow))
    }
    
    // MARK: - Score Announcements
    
    /// Announces a resonance score with contextual feedback.
    ///
    /// Provides encouraging feedback based on score range:
    /// - 90-100: "Excellent!"
    /// - 70-89: "Good job!"
    /// - 50-69: "Keep practicing!"
    /// - Below 50: "Try speaking with more conviction"
    ///
    /// - Parameter score: Optional score (0-100), announces when set
    ///
    /// ## Example
    /// ```swift
    /// ScoreView(score: displayScore)
    ///     .announceScore(displayScore)
    /// ```
    func announceScore(_ score: Int?) -> some View {
        modifier(ScoreAnnouncementModifier(score: score))
    }
}

// MARK: - Modifier Implementations

/// Modifier that announces a message when a value changes.
private struct AnnounceOnChangeModifier<T: Equatable>: ViewModifier {
    
    /// The value to observe for changes
    let value: T
    
    /// Closure that generates the announcement message
    let message: (T) -> String?
    
    /// Tracks whether the view has appeared to skip initial announcement
    @State private var hasAppeared = false
    
    func body(content: Content) -> some View {
        content
            .onAppear { hasAppeared = true }
            .onChange(of: value) { _, newValue in
                // Skip initial appearance to avoid duplicate announcements
                guard hasAppeared else { return }
                
                if let announcement = message(newValue) {
                    AccessibilityAnnouncement.announce(announcement)
                }
            }
    }
}

/// Modifier that posts a screen changed notification on appear.
private struct ScreenChangeModifier: ViewModifier {
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                AccessibilityAnnouncement.screenChanged()
            }
    }
}

/// Modifier that announces a message and posts screen changed on appear.
private struct ScreenChangeWithMessageModifier: ViewModifier {
    
    /// The message to announce
    let message: String
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                AccessibilityAnnouncement.screenChanged()
                AccessibilityAnnouncement.announce(message, delay: 0.3)
            }
    }
}

/// Modifier that announces practice flow state changes.
private struct PracticeFlowAnnouncementModifier: ViewModifier {
    
    /// The current practice flow state
    let flow: PracticeFlow
    
    /// Tracks the previous flow state to detect changes
    @State private var previousFlow: PracticeFlow?
    
    func body(content: Content) -> some View {
        content
            .onChange(of: flow) { oldFlow, newFlow in
                // Avoid redundant announcements for minor updates
                guard shouldAnnounce(from: oldFlow, to: newFlow) else { return }
                
                if let announcement = announcement(for: newFlow) {
                    AccessibilityAnnouncement.announce(announcement)
                }
                
                previousFlow = newFlow
            }
    }
    
    /// Determines whether a state change should trigger an announcement.
    ///
    /// Filters out progress updates within the same phase (e.g., playing progress).
    private func shouldAnnounce(from oldFlow: PracticeFlow, to newFlow: PracticeFlow) -> Bool {
        // Don't announce minor progress updates
        switch (oldFlow, newFlow) {
        case (.readAloud(.playing), .readAloud(.playing)):
            return false
        case (.readAndSpeak(.ttsPlaying), .readAndSpeak(.ttsPlaying)):
            return false
        case (.readAndSpeak(.listening), .readAndSpeak(.listening)):
            return false
        case (.speakOnly(.listening), .speakOnly(.listening)):
            return false
        default:
            return true
        }
    }
    
    /// Generates an announcement message for a given practice flow state.
    private func announcement(for flow: PracticeFlow) -> String? {
        switch flow {
        case .home:
            return nil // No announcement for home
            
        case .readAloud(let phase):
            switch phase {
            case .idle:
                return "Read aloud mode. Swipe to navigate affirmations."
            case .playing:
                return "Playing affirmation"
            case .complete:
                return "Playback complete"
            }
            
        case .readAndSpeak(let phase):
            switch phase {
            case .idle:
                return "Read and speak mode"
            case .ttsPlaying:
                return "Listen carefully"
            case .preparingToListen:
                return "Get ready to speak"
            case .listening:
                return "Speak now"
            case .celebrating:
                return "Great job! All words matched"
            }

        case .speakOnly(let phase):
            switch phase {
            case .idle:
                return "Speak only mode"
            case .preparingToListen:
                return "Get ready to speak"
            case .listening:
                return "Speak now"
            case .celebrating:
                return "Great job! All words matched"
            }
        }
    }
}

/// Modifier that announces resonance scores with contextual feedback.
private struct ScoreAnnouncementModifier: ViewModifier {
    
    /// The current score to announce (0-100)
    let score: Int?
    
    /// Tracks the last announced score to prevent duplicate announcements
    @State private var lastAnnouncedScore: Int?
    
    func body(content: Content) -> some View {
        content
            .onChange(of: score) { _, newScore in
                guard let score = newScore,
                      score != lastAnnouncedScore else { return }
                
                lastAnnouncedScore = score
                
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
                
                AccessibilityAnnouncement.announce(description, delay: 0.2)
            }
    }
}

// MARK: - Navigation Announcement Modifier

extension View {
    
    /// Announces navigation within a session when the index changes.
    ///
    /// - Parameters:
    ///   - currentIndex: Current affirmation index (0-based)
    ///   - totalCount: Total affirmations in session
    ///
    /// ## Example
    /// ```swift
    /// AffirmationCard(affirmation: current)
    ///     .announceNavigation(currentIndex: index, totalCount: total)
    /// ```
    func announceNavigation(currentIndex: Int, totalCount: Int) -> some View {
        modifier(NavigationAnnouncementModifier(
            currentIndex: currentIndex,
            totalCount: totalCount
        ))
    }
}

/// Modifier that announces navigation changes within a session.
private struct NavigationAnnouncementModifier: ViewModifier {
    
    /// Current affirmation index (0-based)
    let currentIndex: Int
    
    /// Total affirmations in session
    let totalCount: Int
    
    /// Tracks the last announced index to prevent duplicate announcements
    @State private var lastAnnouncedIndex: Int?
    
    func body(content: Content) -> some View {
        content
            .onChange(of: currentIndex) { _, newIndex in
                guard newIndex != lastAnnouncedIndex else { return }
                lastAnnouncedIndex = newIndex
                
                AccessibilityAnnouncement.announceNavigation(
                    currentIndex: newIndex,
                    totalCount: totalCount
                )
            }
    }
}

// MARK: - Mode Change Announcement Modifier

extension View {
    
    /// Announces when the session mode changes.
    ///
    /// - Parameter mode: The current session mode
    ///
    /// ## Example
    /// ```swift
    /// DockModeButton(mode: currentMode)
    ///     .announceModeChange(mode)
    /// ```
    func announceModeChange(_ mode: SessionMode) -> some View {
        modifier(ModeChangeAnnouncementModifier(mode: mode))
    }
}

/// Modifier that announces session mode changes.
private struct ModeChangeAnnouncementModifier: ViewModifier {
    
    /// The current session mode
    let mode: SessionMode
    
    /// Tracks the last announced mode to prevent duplicate announcements
    @State private var lastAnnouncedMode: SessionMode?
    
    func body(content: Content) -> some View {
        content
            .onChange(of: mode) { _, newMode in
                guard newMode != lastAnnouncedMode else { return }
                lastAnnouncedMode = newMode
                
                AccessibilityAnnouncement.announceModeChanged(to: newMode.displayName)
            }
    }
}
