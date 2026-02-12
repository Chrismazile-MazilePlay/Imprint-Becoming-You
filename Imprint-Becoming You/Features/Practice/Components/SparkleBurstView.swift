//
//  SparkleBurstView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/11/26.
//

import SwiftUI

// MARK: - SparkleBurstView

/// Sparkle burst celebration animation that fires when all affirmation words are matched.
///
/// Renders ~60 particles using `Canvas` + `TimelineView(.animation)` for 60FPS
/// performance. Particles rise from behind the dock, burst radially outward, and
/// fade with gentle gravity.
///
/// ## Animation Phases
/// - **Phase 1 (0–0.4s)**: Particles rise upward from dock with slight horizontal spread
/// - **Phase 2 (0.4–1.2s)**: Particles burst radially outward from center
/// - **Phase 3 (1.2–2.0s)**: Particles fade out with gravity pull
///
/// ## Visual Style
/// Clean white and gold sparkle points radiating outward — minimal, elegant, premium.
/// Colors: white (70%) and `AppColors.accent` gold (30%), varying opacity.
/// Sizes: 2–6pt circles.
///
/// ## Integration
/// Placed as an `.allowsHitTesting(false)` overlay in the practice ZStack,
/// above affirmation content but below the floating HUD. Triggers haptic
/// feedback on activation.
///
/// ## Usage
/// ```swift
/// SparkleBurstView(isActive: store.flow.isCelebrating)
///     .allowsHitTesting(false)
/// ```
struct SparkleBurstView: View {

    // MARK: - Properties

    /// Whether the burst animation is active
    let isActive: Bool

    /// Y offset from bottom of screen where particles originate (dock height area)
    var originYOffset: CGFloat = AppTheme.Layout.activeDockOffset

    // MARK: - State

    /// The time the animation started (nil when inactive)
    @State private var startTime: Date?

    /// Generated particles for the current burst
    @State private var particles: [Particle] = []

    // MARK: - Constants

    /// Total animation duration
    private let totalDuration: TimeInterval = 2.0

    /// Number of particles to generate
    private let particleCount = 60

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            if isActive && !particles.isEmpty && startTime != nil {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        guard let start = startTime else { return }
                        let elapsed = timeline.date.timeIntervalSince(start)
                        guard elapsed < totalDuration else { return }

                        let normalizedTime = elapsed / totalDuration

                        for particle in particles {
                            drawParticle(
                                particle: particle,
                                time: normalizedTime,
                                in: context,
                                size: size
                            )
                        }
                    }
                }
                .ignoresSafeArea()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: isActive) { _, newValue in
            if newValue {
                startBurst()
            } else {
                reset()
            }
        }
    }

    // MARK: - Particle Rendering

    /// Draws a single particle at its current position based on elapsed time.
    private func drawParticle(
        particle: Particle,
        time: Double,
        in context: GraphicsContext,
        size: CGSize
    ) {
        let position = particlePosition(particle: particle, time: time, size: size)
        let opacity = particleOpacity(particle: particle, time: time)
        let scale = particleScale(particle: particle, time: time)

        guard opacity > 0.01 else { return }

        let radius = particle.size * scale
        let rect = CGRect(
            x: position.x - radius,
            y: position.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        var particleContext = context
        particleContext.opacity = opacity
        particleContext.fill(
            Circle().path(in: rect),
            with: .color(particle.color)
        )
    }

    /// Computes particle position based on animation phase.
    ///
    /// - Phase 1 (0–0.2): Rise upward from origin with slight horizontal spread
    /// - Phase 2 (0.2–0.6): Burst radially outward from burst center
    /// - Phase 3 (0.6–1.0): Continue outward with gravity pull
    private func particlePosition(particle: Particle, time: Double, size: CGSize) -> CGPoint {
        let originX = size.width / 2 + particle.horizontalOffset
        let originY = size.height - originYOffset

        // Phase 1: Rise (0 → 0.2)
        let riseEnd: Double = 0.2
        let burstCenter = CGPoint(x: size.width / 2, y: size.height * 0.45)

        if time <= riseEnd {
            let riseProgress = time / riseEnd
            let easedProgress = easeOutCubic(riseProgress)
            let x = lerp(originX, burstCenter.x + particle.horizontalOffset * 0.5, easedProgress)
            let y = lerp(originY, burstCenter.y, easedProgress)
            return CGPoint(x: x, y: y)
        }

        // Phase 2 & 3: Burst outward (0.2 → 1.0)
        let burstProgress = (time - riseEnd) / (1.0 - riseEnd)
        let easedBurst = easeOutQuad(min(burstProgress, 1.0))

        let burstDistance = particle.burstSpeed * easedBurst * 200
        let x = burstCenter.x + cos(particle.burstAngle) * burstDistance
        let y = burstCenter.y + sin(particle.burstAngle) * burstDistance + gravity(time: burstProgress)

        return CGPoint(x: x, y: y)
    }

    /// Computes particle opacity based on animation phase.
    private func particleOpacity(particle: Particle, time: Double) -> Double {
        // Fade in during rise
        if time < 0.1 {
            return time / 0.1 * particle.maxOpacity
        }

        // Full opacity during burst
        if time < 0.5 {
            return particle.maxOpacity
        }

        // Fade out during decay
        let fadeProgress = (time - 0.5) / 0.5
        return particle.maxOpacity * (1.0 - easeInCubic(fadeProgress))
    }

    /// Computes particle scale based on animation phase.
    private func particleScale(particle: Particle, time: Double) -> Double {
        // Scale up during rise
        if time < 0.2 {
            return lerp(0.3, 1.0, time / 0.2)
        }

        // Slight shrink during decay
        if time > 0.6 {
            let shrinkProgress = (time - 0.6) / 0.4
            return lerp(1.0, 0.3, easeInCubic(shrinkProgress))
        }

        return 1.0
    }

    /// Gravity pull during burst phase (pixels downward)
    private func gravity(time: Double) -> Double {
        30 * time * time
    }

    // MARK: - Burst Lifecycle

    /// Generates particles and starts the animation
    private func startBurst() {
        particles = (0..<particleCount).map { index in
            Particle.generate(index: index, total: particleCount)
        }
        startTime = Date()

        // Haptic feedback
        AppTheme.Haptics.success()
    }

    /// Clears particles and resets state
    private func reset() {
        particles = []
        startTime = nil
    }

    // MARK: - Easing Functions

    private func easeOutCubic(_ t: Double) -> Double {
        1.0 - pow(1.0 - t, 3)
    }

    private func easeOutQuad(_ t: Double) -> Double {
        1.0 - (1.0 - t) * (1.0 - t)
    }

    private func easeInCubic(_ t: Double) -> Double {
        t * t * t
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}

// MARK: - Particle

/// A single sparkle particle with deterministic properties.
///
/// All properties are computed from a seed index at creation time,
/// ensuring consistent animation without per-frame random state.
private struct Particle: Identifiable {
    let id: Int

    /// Particle circle radius (2–6pt)
    let size: Double

    /// Color (white or accent gold)
    let color: Color

    /// Maximum opacity (0.6–1.0)
    let maxOpacity: Double

    /// Horizontal offset from center for the rise phase
    let horizontalOffset: Double

    /// Angle of outward burst (radians)
    let burstAngle: Double

    /// Speed multiplier for burst distance (0.5–1.5)
    let burstSpeed: Double

    /// Generates a particle with deterministic properties based on its index.
    static func generate(index: Int, total: Int) -> Particle {
        // Use golden ratio-based distribution for natural spread
        let phi = Double(index) * 0.618033988749895
        let normalizedIndex = Double(index) / Double(total)

        // Size: 2–6pt, biased toward smaller
        let size = 2.0 + (phi.truncatingRemainder(dividingBy: 1.0)) * 4.0

        // Color: 70% white, 30% accent gold
        let isGold = normalizedIndex < 0.3
        let color: Color = isGold ? AppColors.accent : .white

        // Opacity: 0.6–1.0
        let maxOpacity = 0.6 + (phi * 2.3).truncatingRemainder(dividingBy: 1.0) * 0.4

        // Horizontal offset: -40 to +40pt spread during rise
        let horizontalOffset = (phi * 3.7).truncatingRemainder(dividingBy: 1.0) * 80.0 - 40.0

        // Burst angle: full 360° distribution with slight upward bias
        let baseAngle = (Double(index) / Double(total)) * 2.0 * .pi
        let jitter = (phi * 5.1).truncatingRemainder(dividingBy: 1.0) * 0.5 - 0.25
        let burstAngle = baseAngle + jitter

        // Burst speed: 0.5–1.5, varied for organic look
        let burstSpeed = 0.5 + (phi * 7.3).truncatingRemainder(dividingBy: 1.0)

        return Particle(
            id: index,
            size: size,
            color: color,
            maxOpacity: maxOpacity,
            horizontalOffset: horizontalOffset,
            burstAngle: burstAngle,
            burstSpeed: burstSpeed
        )
    }
}

// MARK: - Preview

#Preview("Sparkle Burst") {
    ZStack {
        AppColors.backgroundPrimary
            .ignoresSafeArea()

        SparkleBurstView(isActive: true)
    }
}
