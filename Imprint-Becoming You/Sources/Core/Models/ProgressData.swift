//
//  ProgressData.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import Foundation
import SwiftData

// MARK: - ProgressData

/// Daily progress tracking for analytics and achievements.
///
/// One record is created per day that the user practices, tracking
/// various metrics for the progress dashboard.
@Model
final class ProgressData {
    
    // MARK: - Properties
    
    /// Unique identifier for the progress record
    @Attribute(.unique)
    var id: UUID
    
    /// The date this progress represents (day granularity)
    var date: Date
    
    /// Number of affirmations practiced this day
    var affirmationsPracticed: Int
    
    /// Total time spent practicing (seconds)
    var totalSessionTime: TimeInterval
    
    /// Average resonance score for the day
    var averageResonanceScore: Float
    
    /// Number of resonance recordings for averaging
    var resonanceRecordCount: Int
    
    /// Categories practiced this day
    var categoriesPracticed: [String]
    
    /// Number of sessions started this day
    var sessionsCompleted: Int
    
    /// Best resonance score achieved this day
    var bestResonanceScore: Float
    
    /// Whether this day counts toward streak
    var countsTowardStreak: Bool
    
    // MARK: - Initialization
    
    /// Creates a new progress record
    init(
        id: UUID = UUID(),
        date: Date = Date(),
        affirmationsPracticed: Int = 0,
        totalSessionTime: TimeInterval = 0,
        averageResonanceScore: Float = 0,
        resonanceRecordCount: Int = 0,
        categoriesPracticed: [String] = [],
        sessionsCompleted: Int = 0,
        bestResonanceScore: Float = 0,
        countsTowardStreak: Bool = false
    ) {
        self.id = id
        // Normalize to start of day
        self.date = Calendar.current.startOfDay(for: date)
        self.affirmationsPracticed = affirmationsPracticed
        self.totalSessionTime = totalSessionTime
        self.averageResonanceScore = averageResonanceScore
        self.resonanceRecordCount = resonanceRecordCount
        self.categoriesPracticed = categoriesPracticed
        self.sessionsCompleted = sessionsCompleted
        self.bestResonanceScore = bestResonanceScore
        self.countsTowardStreak = countsTowardStreak
    }
}

// MARK: - Computed Properties

extension ProgressData {
    
    /// Formatted date for display
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    /// Short formatted date (e.g., "Mon 15")
    var shortFormattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d"
        return formatter.string(from: date)
    }
    
    /// Formatted session time for display
    var formattedSessionTime: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: totalSessionTime) ?? "0m"
    }
    
    /// Whether this is today's progress
    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    /// Number of unique categories practiced
    var uniqueCategoriesCount: Int {
        Set(categoriesPracticed).count
    }
    
    /// Resonance quality level based on average score
    var resonanceQuality: ResonanceQuality {
        ResonanceQuality(score: averageResonanceScore)
    }
}

// MARK: - Methods

extension ProgressData {
    
    /// Records a practice session
    func recordPractice(
        affirmationCount: Int,
        sessionTime: TimeInterval,
        resonanceScore: Float?,
        categories: [String]
    ) {
        affirmationsPracticed += affirmationCount
        totalSessionTime += sessionTime
        
        // Update resonance average
        if let score = resonanceScore {
            let totalScore = averageResonanceScore * Float(resonanceRecordCount) + score
            resonanceRecordCount += 1
            averageResonanceScore = totalScore / Float(resonanceRecordCount)
            
            if score > bestResonanceScore {
                bestResonanceScore = score
            }
        }
        
        // Add unique categories
        for category in categories {
            if !categoriesPracticed.contains(category) {
                categoriesPracticed.append(category)
            }
        }
        
        sessionsCompleted += 1
        
        // Mark as counting toward streak if at least 1 affirmation practiced
        if affirmationsPracticed > 0 {
            countsTowardStreak = true
        }
    }
    
    /// Adds a resonance score to the average
    func addResonanceScore(_ score: Float) {
        let totalScore = averageResonanceScore * Float(resonanceRecordCount) + score
        resonanceRecordCount += 1
        averageResonanceScore = totalScore / Float(resonanceRecordCount)
        
        if score > bestResonanceScore {
            bestResonanceScore = score
        }
    }
}

// MARK: - Sample Data

extension ProgressData {
    
    /// Sample progress for previews
    static var sample: ProgressData {
        ProgressData(
            affirmationsPracticed: 15,
            totalSessionTime: 420,
            averageResonanceScore: 0.75,
            resonanceRecordCount: 15,
            categoriesPracticed: [
                GoalCategory.confidence.rawValue,
                GoalCategory.focus.rawValue
            ],
            sessionsCompleted: 2,
            bestResonanceScore: 0.92,
            countsTowardStreak: true
        )
    }
    
    /// Sample week of progress for previews
    static var sampleWeek: [ProgressData] {
        let calendar = Calendar.current
        return (0..<7).map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
            return ProgressData(
                date: date,
                affirmationsPracticed: Int.random(in: 5...20),
                totalSessionTime: TimeInterval.random(in: 120...600),
                averageResonanceScore: Float.random(in: 0.5...0.95),
                resonanceRecordCount: Int.random(in: 5...20),
                categoriesPracticed: [GoalCategory.allCases.randomElement()!.rawValue],
                sessionsCompleted: Int.random(in: 1...3),
                bestResonanceScore: Float.random(in: 0.7...0.98),
                countsTowardStreak: true
            )
        }
    }
}
