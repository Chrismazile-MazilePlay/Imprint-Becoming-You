//
//  ResonanceRecord.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Resonance Record

/// Records the result of a resonance scoring session.
///
/// Captures all metrics from a user's spoken affirmation, including
/// the composite score and individual components.
///
/// ## Scoring Components
/// - **Text Accuracy**: How closely the user's words matched the affirmation (10%)
/// - **Vocal Energy**: RMS energy level indicating confidence/projection (60%)
/// - **Pitch Stability**: Consistency of vocal pitch throughout (30%)
///
/// ## Usage
/// ```swift
/// let record = ResonanceRecord(
///     finalScore: 0.78,
///     textAccuracy: 0.95,
///     vocalEnergy: 0.72,
///     pitchStability: 0.80,
///     sessionMode: .readThenSpeak,
///     duration: 3.5
/// )
///
/// print(record.rating)        // .good
/// print(record.percentScore)  // 78
/// ```
struct ResonanceRecord: Sendable, Codable, Equatable, Identifiable {
    
    // MARK: - Properties
    
    /// Unique identifier for this record
    let id: UUID
    
    /// Final composite score (0.0 - 1.0)
    let finalScore: Float
    
    /// Text accuracy component (0.0 - 1.0)
    /// Measures how closely spoken words matched the expected affirmation
    let textAccuracy: Float
    
    /// Vocal energy component (0.0 - 1.0)
    /// Measures RMS energy level relative to user's calibrated baseline
    let vocalEnergy: Float
    
    /// Pitch stability component (0.0 - 1.0)
    /// Measures consistency of vocal pitch throughout the affirmation
    let pitchStability: Float
    
    /// Session mode used during this recording
    let sessionMode: SessionMode
    
    /// Timestamp when this record was created
    let timestamp: Date
    
    /// Duration of the analysis in seconds
    let duration: TimeInterval
    
    // MARK: - Initialization
    
    /// Creates a new resonance record
    /// - Parameters:
    ///   - id: Unique identifier (defaults to new UUID)
    ///   - finalScore: Composite score (0.0 - 1.0)
    ///   - textAccuracy: Text matching score (0.0 - 1.0)
    ///   - vocalEnergy: Energy level score (0.0 - 1.0)
    ///   - pitchStability: Pitch consistency score (0.0 - 1.0)
    ///   - sessionMode: The mode used during recording
    ///   - timestamp: When recorded (defaults to now)
    ///   - duration: Length of the recording in seconds
    init(
        id: UUID = UUID(),
        finalScore: Float,
        textAccuracy: Float,
        vocalEnergy: Float,
        pitchStability: Float,
        sessionMode: SessionMode,
        timestamp: Date = Date(),
        duration: TimeInterval
    ) {
        self.id = id
        self.finalScore = finalScore
        self.textAccuracy = textAccuracy
        self.vocalEnergy = vocalEnergy
        self.pitchStability = pitchStability
        self.sessionMode = sessionMode
        self.timestamp = timestamp
        self.duration = duration
    }
    
    // MARK: - Legacy Initializer (for backward compatibility)
    
    /// Creates a resonance record using the legacy parameter name
    /// - Note: Use the primary initializer for new code
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        overallScore: Float,
        textAccuracy: Float,
        vocalEnergy: Float,
        pitchStability: Float,
        duration: TimeInterval,
        sessionMode: SessionMode
    ) {
        self.init(
            id: id,
            finalScore: overallScore,
            textAccuracy: textAccuracy,
            vocalEnergy: vocalEnergy,
            pitchStability: pitchStability,
            sessionMode: sessionMode,
            timestamp: timestamp,
            duration: duration
        )
    }
    
    // MARK: - Computed Properties
    
    /// Alias for finalScore for backward compatibility
    /// - Note: Prefer using `finalScore` in new code
    var overallScore: Float {
        finalScore
    }
    
    /// Qualitative rating based on the final score
    var rating: ResonanceRating {
        switch finalScore {
        case 0.8...: return .excellent
        case 0.6..<0.8: return .good
        case 0.4..<0.6: return .fair
        default: return .needsWork
        }
    }
    
    /// Quality level based on overall score (alias for rating)
    /// - Note: Prefer using `rating` in new code
    var qualityLevel: ResonanceRating {
        rating
    }
    
    /// Final score as a percentage (0 - 100)
    var percentScore: Int {
        Int(finalScore * 100)
    }
    
    /// Whether this score meets the "good" threshold
    var isGoodScore: Bool {
        finalScore >= Constants.ResonanceScoring.goodThreshold
    }
    
    /// Whether this score meets the "excellent" threshold
    var isExcellentScore: Bool {
        finalScore >= Constants.ResonanceScoring.excellentThreshold
    }
}

// MARK: - Resonance Rating

/// Qualitative resonance ratings based on score thresholds.
enum ResonanceRating: String, Sendable, Codable {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case needsWork = "Needs Work"
    
    /// Initialize from a score value
    init(score: Float) {
        switch score {
        case 0.8...: self = .excellent
        case 0.6..<0.8: self = .good
        case 0.4..<0.6: self = .fair
        default: self = .needsWork
        }
    }
    
    /// Color name from the app's color palette
    var colorName: String {
        switch self {
        case .excellent: return "resonanceExcellent"
        case .good: return "resonanceGood"
        case .fair: return "textSecondary"
        case .needsWork: return "resonanceNeedsWork"
        }
    }
    
    /// Encouraging message for this rating
    var encouragement: String {
        switch self {
        case .excellent: return "Outstanding! Your conviction shines through."
        case .good: return "Great job! Keep building that resonance."
        case .fair: return "Good start. Try speaking with more confidence."
        case .needsWork: return "Take a breath and try again with intention."
        }
    }
    
    /// SF Symbol icon for this rating
    var iconName: String {
        switch self {
        case .excellent: return "star.fill"
        case .good: return "checkmark.circle.fill"
        case .fair: return "circle.fill"
        case .needsWork: return "arrow.up.circle"
        }
    }
}

// MARK: - Type Alias for Backward Compatibility

/// Type alias for backward compatibility with code using the old name
typealias ResonanceQuality = ResonanceRating

// MARK: - Sample Data

extension ResonanceRecord {
    /// Sample record for previews and testing
    static var sample: ResonanceRecord {
        ResonanceRecord(
            finalScore: 0.78,
            textAccuracy: 0.92,
            vocalEnergy: 0.75,
            pitchStability: 0.82,
            sessionMode: .readThenSpeak,
            duration: 3.5
        )
    }
    
    /// Sample excellent score for previews
    static var excellent: ResonanceRecord {
        ResonanceRecord(
            finalScore: 0.92,
            textAccuracy: 0.98,
            vocalEnergy: 0.90,
            pitchStability: 0.88,
            sessionMode: .speakOnly,
            duration: 2.8
        )
    }
    
    /// Sample low score for previews
    static var needsWork: ResonanceRecord {
        ResonanceRecord(
            finalScore: 0.35,
            textAccuracy: 0.45,
            vocalEnergy: 0.30,
            pitchStability: 0.40,
            sessionMode: .readThenSpeak,
            duration: 4.2
        )
    }
}
