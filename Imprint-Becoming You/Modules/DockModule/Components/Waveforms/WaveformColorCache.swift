//
//  WaveformColorCache.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/8/26.
//

import SwiftUI

// MARK: - Pre-computed Color Values

/// Pre-computed RGBA values for efficient color interpolation.
///
/// Caches the RGBA components of accent and listening colors to avoid
/// repeated `UIColor` bridge creation during animation frames.
///
/// ## Performance Benefits
/// - Extracts RGBA values once at initialization (not per frame)
/// - Caches common blend values (0, 0.5, 1.0) for fast lookup
/// - Eliminates 180+ UIColor allocations/second per waveform (60fps × layers)
///
/// ## Usage
/// ```swift
/// let cache = WaveformColorCache(accent: tokens.accent, listening: tokens.success)
/// let blendedColor = cache.lerp(t: 0.5)
/// ```
struct WaveformColorCache: Equatable {

    // MARK: - Pre-computed RGBA Components

    private let accentRGBA: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
    private let listeningRGBA: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)

    // MARK: - Cached Colors for Common Blend Values

    /// Original accent color (colorBlend = 0)
    let accentColor: Color

    /// Original listening color (colorBlend = 1)
    let listeningColor: Color

    /// Pre-computed 50% blend for quick lookup
    let midBlendColor: Color

    // MARK: - Initialization

    /// Creates a color cache with pre-computed RGBA values.
    ///
    /// - Parameters:
    ///   - accent: The accent color (used when colorBlend = 0)
    ///   - listening: The listening color (used when colorBlend = 1)
    init(accent: Color, listening: Color) {
        // Extract RGBA once at initialization
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0

        #if canImport(UIKit)
        UIColor(accent).getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        UIColor(listening).getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        #endif

        self.accentRGBA = (ar, ag, ab, aa)
        self.listeningRGBA = (lr, lg, lb, la)

        // Cache original colors
        self.accentColor = accent
        self.listeningColor = listening

        // Pre-compute 50% blend
        self.midBlendColor = Color(
            red: (ar + lr) / 2,
            green: (ag + lg) / 2,
            blue: (ab + lb) / 2,
            opacity: (aa + la) / 2
        )
    }

    // MARK: - Fast Interpolation

    /// Fast color interpolation using pre-computed RGBA values.
    ///
    /// - Parameter t: Blend factor (0 = accent, 1 = listening)
    /// - Returns: Interpolated color
    func lerp(t: CGFloat) -> Color {
        // Fast paths for common values
        if t <= 0 { return accentColor }
        if t >= 1 { return listeningColor }
        if abs(t - 0.5) < 0.01 { return midBlendColor }

        // General interpolation using pre-computed RGBA
        let clampedT = max(0, min(1, t))
        return Color(
            red: accentRGBA.r + (listeningRGBA.r - accentRGBA.r) * clampedT,
            green: accentRGBA.g + (listeningRGBA.g - accentRGBA.g) * clampedT,
            blue: accentRGBA.b + (listeningRGBA.b - accentRGBA.b) * clampedT,
            opacity: accentRGBA.a + (listeningRGBA.a - accentRGBA.a) * clampedT
        )
    }

    // MARK: - Equatable

    static func == (lhs: WaveformColorCache, rhs: WaveformColorCache) -> Bool {
        // Compare by RGBA values (more reliable than Color equality)
        lhs.accentRGBA.r == rhs.accentRGBA.r &&
        lhs.accentRGBA.g == rhs.accentRGBA.g &&
        lhs.accentRGBA.b == rhs.accentRGBA.b &&
        lhs.accentRGBA.a == rhs.accentRGBA.a &&
        lhs.listeningRGBA.r == rhs.listeningRGBA.r &&
        lhs.listeningRGBA.g == rhs.listeningRGBA.g &&
        lhs.listeningRGBA.b == rhs.listeningRGBA.b &&
        lhs.listeningRGBA.a == rhs.listeningRGBA.a
    }
}
