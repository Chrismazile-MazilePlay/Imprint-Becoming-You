//
//  SubscriptionTier.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/24/26.
//

import Foundation

// MARK: - Subscription Tier

/// User subscription access level for gating premium features.
///
/// ## Tier Hierarchy
/// ```
/// premium > trial > free
/// ```
///
/// ## Access Rules
/// - **Free**: 6 curated Kokoro voices, basic features
/// - **Trial**: Full premium access for limited time (1-2 weeks)
/// - **Premium**: All voices, voice cloning, unlimited sessions
///
/// - Note: Computed from `UserProfile` stored properties, not stored directly.
enum SubscriptionTier: String, Codable, Sendable, CaseIterable, Comparable {
    case free
    case trial
    case premium
    
    // MARK: - Access Level
    
    /// Numeric access level for comparison (higher = more access).
    var accessLevel: Int {
        switch self {
        case .free: return 0
        case .trial: return 1
        case .premium: return 2
        }
    }
    
    /// Whether this tier has premium-equivalent access.
    var hasPremiumAccess: Bool {
        self == .trial || self == .premium
    }
    
    /// Checks if this tier grants access to a required tier level.
    func hasAccess(to requiredTier: SubscriptionTier) -> Bool {
        accessLevel >= requiredTier.accessLevel
    }
    
    // MARK: - Display
    
    var displayName: String {
        switch self {
        case .free: return String(localized: "Free")
        case .trial: return String(localized: "Trial")
        case .premium: return String(localized: "Premium")
        }
    }
    
    var iconName: String {
        switch self {
        case .free: return "person.fill"
        case .trial: return "clock.fill"
        case .premium: return "star.fill"
        }
    }
    
    // MARK: - Comparable
    
    static func < (lhs: SubscriptionTier, rhs: SubscriptionTier) -> Bool {
        lhs.accessLevel < rhs.accessLevel
    }
}
