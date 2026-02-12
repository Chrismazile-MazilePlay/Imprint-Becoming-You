//
//  CenterAlignedFlowLayout.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/11/26.
//

import SwiftUI

// MARK: - CenterAlignedFlowLayout

/// A layout that arranges views in a flowing, wrapping manner with center-aligned rows.
///
/// Similar to `FlowLayout` but centers each row horizontally within the available
/// width, matching the center-aligned text appearance of `AutoScrollingAffirmationText`.
///
/// Used by `WordHighlightAffirmationText` to render individual words that can be
/// independently styled and animated while maintaining center-aligned paragraph appearance.
///
/// ## Usage
/// ```swift
/// CenterAlignedFlowLayout(horizontalSpacing: 8, verticalSpacing: 4) {
///     ForEach(words.indices, id: \.self) { index in
///         Text(words[index])
///             .font(AppTypography.affirmation)
///     }
/// }
/// ```
struct CenterAlignedFlowLayout: Layout {

    // MARK: - Properties

    /// Horizontal spacing between words on the same line
    var horizontalSpacing: CGFloat = 8

    /// Vertical spacing between lines
    var verticalSpacing: CGFloat = 4

    // MARK: - Layout Protocol

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews
        )
        return result.totalSize
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(in: bounds.width, subviews: subviews)

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

    // MARK: - Layout Computation

    /// Computed layout result with positions, sizes, and per-row data.
    private struct LayoutResult {
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var totalSize: CGSize = .zero
    }

    /// Computes positions for all subviews with center alignment per row.
    ///
    /// Two-pass algorithm:
    /// 1. Assign subviews to rows based on available width
    /// 2. Center each row horizontally
    private func computeLayout(in maxWidth: CGFloat, subviews: Subviews) -> LayoutResult {
        guard !subviews.isEmpty else {
            return LayoutResult()
        }

        // Pass 1: Measure all subviews and assign to rows
        var rows: [[Int]] = [[]]          // Indices per row
        var subviewSizes: [CGSize] = []   // Measured sizes
        var currentRowWidth: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            subviewSizes.append(size)

            let widthWithSpacing = currentRowWidth > 0 ? size.width + horizontalSpacing : size.width

            if currentRowWidth + widthWithSpacing > maxWidth && currentRowWidth > 0 {
                // Start new row
                rows.append([index])
                currentRowWidth = size.width
            } else {
                rows[rows.count - 1].append(index)
                currentRowWidth += widthWithSpacing
            }
        }

        // Pass 2: Compute centered positions
        var positions = [CGPoint](repeating: .zero, count: subviews.count)
        var currentY: CGFloat = 0
        var totalWidth: CGFloat = 0

        for row in rows {
            // Calculate row width and height
            var rowWidth: CGFloat = 0
            var rowHeight: CGFloat = 0

            for (i, index) in row.enumerated() {
                let size = subviewSizes[index]
                rowWidth += size.width
                if i > 0 { rowWidth += horizontalSpacing }
                rowHeight = max(rowHeight, size.height)
            }

            // Center offset for this row
            let centerOffset = max(0, (maxWidth - rowWidth) / 2)

            // Place each subview in the row
            var currentX = centerOffset
            for index in row {
                let size = subviewSizes[index]
                positions[index] = CGPoint(x: currentX, y: currentY)
                currentX += size.width + horizontalSpacing
            }

            totalWidth = max(totalWidth, rowWidth)
            currentY += rowHeight + verticalSpacing
        }

        // Remove trailing vertical spacing
        if !rows.isEmpty {
            currentY -= verticalSpacing
        }

        var result = LayoutResult()
        result.positions = positions
        result.sizes = subviewSizes
        result.totalSize = CGSize(width: totalWidth, height: currentY)
        return result
    }
}

// MARK: - Preview

#Preview("CenterAlignedFlowLayout") {
    CenterAlignedFlowLayout(horizontalSpacing: 8, verticalSpacing: 4) {
        ForEach(
            "I am confident and I embrace the power within me to create positive change".split(separator: " ").indices,
            id: \.self
        ) { index in
            let word = "I am confident and I embrace the power within me to create positive change".split(separator: " ")[index]
            Text(String(word))
                .font(AppTypography.affirmation)
                .foregroundStyle(index < 5 ? AppColors.accent : AppColors.textSecondary.opacity(0.4))
        }
    }
    .padding(.horizontal, AppTheme.Spacing.xl)
    .frame(maxWidth: .infinity)
    .background(AppColors.backgroundPrimary)
}
