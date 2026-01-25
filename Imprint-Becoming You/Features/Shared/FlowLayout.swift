//
//  FlowLayout.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/24/26.
//

import SwiftUI

// MARK: - FlowLayout

/// A layout that arranges views in a flowing, wrapping manner.
///
/// Views are placed left-to-right, wrapping to the next line when
/// the available width is exceeded. Useful for tags, chips, and badges.
///
/// ## Usage
/// ```swift
/// FlowLayout(spacing: 8) {
///     ForEach(tags, id: \.self) { tag in
///         TagView(tag)
///     }
/// }
/// ```
struct FlowLayout: Layout {
    
    /// Spacing between items (both horizontal and vertical)
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(
                    x: bounds.minX + result.positions[index].x,
                    y: bounds.minY + result.positions[index].y
                ),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }
    
    // MARK: - Flow Result
    
    /// Computed layout result containing positions and sizes for all subviews
    struct FlowResult {
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var size: CGSize = .zero
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            var maxX: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > maxWidth && currentX > 0 {
                    // Move to next line
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: currentX, y: currentY))
                sizes.append(size)
                
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
                maxX = max(maxX, currentX)
            }
            
            size = CGSize(width: maxX, height: currentY + lineHeight)
        }
    }
}

// MARK: - Preview

#Preview("Flow Layout") {
    FlowLayout(spacing: 8) {
        ForEach(["Short", "Medium Length", "A", "Longer Text Here", "Tag", "Another"], id: \.self) { text in
            Text(text)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.2))
                .clipShape(Capsule())
        }
    }
    .padding()
    .frame(width: 300)
    .background(Color.black)
}
