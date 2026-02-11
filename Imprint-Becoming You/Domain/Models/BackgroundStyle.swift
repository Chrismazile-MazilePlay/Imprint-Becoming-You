//
//  BackgroundStyle.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/9/26.
//

import SwiftUI

// MARK: - BackgroundStyle

/// User-selectable background style for practice sessions and browse mode.
///
/// Persisted as a raw string on `UserProfile` via `backgroundStyleRawValue`
/// for SwiftData compatibility. The `.morphingGradient` case is the default —
/// a category-driven gradient that blends between affirmation categories
/// during navigation.
///
/// ## Usage
/// ```swift
/// let style: BackgroundStyle = .solidDeepNavy
/// print(style.displayName)       // "Deep Navy"
/// print(style.isMorphingGradient) // false
/// print(style.solidColor)        // Color(red: 0.04, ...)
/// ```
///
/// ## Adding New Styles
/// 1. Add a new case with a stable raw value string
/// 2. Add `displayName`, `solidColor` entries in the respective switches
/// 3. Rebuild — `CaseIterable` and `Identifiable` conformance updates automatically
enum BackgroundStyle: String, Codable, CaseIterable, Identifiable, Sendable {

    // MARK: - Cases

    /// Default: Category-driven gradient that morphs during navigation.
    /// Uses `CategoryGradient` with true RGB interpolation between affirmation categories.
    case morphingGradient = "morphingGradient"

    /// Solid color backgrounds — dark tones that complement the app's aesthetic.
    case solidCharcoal = "solidCharcoal"
    case solidDeepNavy = "solidDeepNavy"
    case solidMidnightTeal = "solidMidnightTeal"
    case solidDeepPlum = "solidDeepPlum"
    case solidWarmBlack = "solidWarmBlack"
    case solidForestDark = "solidForestDark"

    // MARK: - Identifiable

    var id: String { rawValue }

    // MARK: - Display Properties

    /// Human-readable name for the background selection grid.
    var displayName: String {
        switch self {
        case .morphingGradient: return "Morphing Gradient"
        case .solidCharcoal: return "Charcoal"
        case .solidDeepNavy: return "Deep Navy"
        case .solidMidnightTeal: return "Midnight Teal"
        case .solidDeepPlum: return "Deep Plum"
        case .solidWarmBlack: return "Warm Black"
        case .solidForestDark: return "Forest Dark"
        }
    }

    /// Color used for solid backgrounds. Returns `nil` for `.morphingGradient`.
    ///
    /// These colors are intentionally very dark to maintain the app's minimalist
    /// aesthetic while providing subtle differentiation from pure black.
    var solidColor: Color? {
        switch self {
        case .morphingGradient:
            return nil
        case .solidCharcoal:
            return Color(red: 0.11, green: 0.11, blue: 0.12)   // #1C1C1E
        case .solidDeepNavy:
            return Color(red: 0.04, green: 0.09, blue: 0.16)   // #0A1628
        case .solidMidnightTeal:
            return Color(red: 0.05, green: 0.12, blue: 0.12)   // #0C1F1F
        case .solidDeepPlum:
            return Color(red: 0.10, green: 0.04, blue: 0.12)   // #1A0A1F
        case .solidWarmBlack:
            return Color(red: 0.08, green: 0.07, blue: 0.06)   // #141210
        case .solidForestDark:
            return Color(red: 0.04, green: 0.10, blue: 0.04)   // #0A1A0A
        }
    }

    // MARK: - Convenience

    /// Whether this is the default morphing gradient style.
    var isMorphingGradient: Bool {
        self == .morphingGradient
    }
}
