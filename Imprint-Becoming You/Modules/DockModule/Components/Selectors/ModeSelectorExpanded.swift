//
//  ModeSelectorExpanded.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import SwiftUI

// MARK: - ModeSelectorExpanded

/// An expanded panel showing all available practice modes.
///
/// ## Usage
///
/// ```swift
/// ModeSelectorExpanded(
///     modes: adapter.availableModes,
///     selectedMode: adapter.currentMode
/// ) { mode in
///     adapter.selectMode(mode)
/// }
/// ```
public struct ModeSelectorExpanded: View {
    
    // MARK: - Environment
    
    @Environment(\.dockDesignTokens) private var tokens
    
    // MARK: - Properties
    
    public let modes: [DockMode]
    public let selectedMode: DockMode
    public let onSelect: (DockMode) -> Void
    
    // MARK: - Initialization
    
    public init(
        modes: [DockMode],
        selectedMode: DockMode,
        onSelect: @escaping (DockMode) -> Void
    ) {
        self.modes = modes
        self.selectedMode = selectedMode
        self.onSelect = onSelect
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(modes.enumerated()), id: \.element.id) { index, mode in
                ModeOptionRow(
                    mode: mode,
                    isSelected: mode == selectedMode
                ) {
                    onSelect(mode)
                }
                
                if index < modes.count - 1 {
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

#Preview("Mode Selector Expanded") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            ModeSelectorExpanded(
                modes: DockMode.allCases,
                selectedMode: .readAndSpeak
            ) { _ in }
            .padding()
        }
    }
}
