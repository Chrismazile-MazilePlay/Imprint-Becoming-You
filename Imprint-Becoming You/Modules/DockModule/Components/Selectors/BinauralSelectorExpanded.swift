//
//  BinauralSelectorExpanded.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import SwiftUI

// MARK: - BinauralSelectorExpanded

/// An expanded panel showing all binaural presets.
///
/// ## Usage
///
/// ```swift
/// BinauralSelectorExpanded(
///     selectedPreset: adapter.binauralPreset
/// ) { preset in
///     adapter.selectBinaural(preset)
/// }
/// ```
public struct BinauralSelectorExpanded: View {
    
    // MARK: - Environment
    
    @Environment(\.dockDesignTokens) private var tokens
    
    // MARK: - Properties
    
    public let selectedPreset: DockBinauralPreset
    public let onSelect: (DockBinauralPreset) -> Void
    
    // MARK: - Initialization
    
    public init(
        selectedPreset: DockBinauralPreset,
        onSelect: @escaping (DockBinauralPreset) -> Void
    ) {
        self.selectedPreset = selectedPreset
        self.onSelect = onSelect
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(DockBinauralPreset.allCases.enumerated()), id: \.element.id) { index, preset in
                BinauralOptionRow(
                    preset: preset,
                    isSelected: preset == selectedPreset
                ) {
                    onSelect(preset)
                }
                
                if index < DockBinauralPreset.allCases.count - 1 {
                    Divider()
                        .background(tokens.textTertiary.opacity(0.2))
                        .padding(.leading, 48)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: tokens.cornerRadiusLarge)
                .fill(tokens.backgroundSecondary.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: tokens.cornerRadiusLarge)
                .stroke(tokens.textTertiary.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Previews

#Preview("Binaural Selector Expanded") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            BinauralSelectorExpanded(selectedPreset: .focus) { _ in }
                .padding()
        }
    }
}
