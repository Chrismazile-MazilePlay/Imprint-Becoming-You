//
//  SaveToolbarButton.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/2/26.
//

import SwiftUI

// MARK: - Save Toolbar Button

/// Reusable save button for navigation bar toolbar.
///
/// Shows "Save" initially, transitions to "Saved" on success, and maintains
/// stable disabled state to prevent visual glitches during view dismissal.
///
/// ## Features
/// - Displays "Save" when there are unsaved changes
/// - Transitions to "Saved" after successful save
/// - Maintains stable disabled state (once disabled, stays disabled)
/// - Prevents visual glitches during view dismissal
///
/// ## Usage
/// ```swift
/// .toolbar {
///     ToolbarItem(placement: .primaryAction) {
///         SaveToolbarButton(
///             isSaved: viewModel.isSaved,
///             isDisabled: viewModel.cannotSave,
///             onSave: { viewModel.save() }
///         )
///     }
/// }
/// ```
struct SaveToolbarButton: View {
    
    // MARK: - Properties
    
    /// Whether the content has been saved
    let isSaved: Bool
    
    /// Whether the save action is disabled
    let isDisabled: Bool
    
    /// Action to perform when save is tapped
    let onSave: () -> Void
    
    // MARK: - State
    
    /// Captured saved state - true once content has been saved.
    /// Prevents label from changing during dismissal.
    @State private var capturedIsSaved: Bool = false
    
    /// Captured disabled state - true once disabled.
    /// Prevents button from flashing enabled during dismissal.
    @State private var capturedIsDisabled: Bool = false
    
    // MARK: - Computed Properties
    
    /// Stable disabled state that never transitions from disabled to enabled.
    /// Once the button becomes disabled (initially or after saving), it stays disabled.
    private var stableIsDisabled: Bool {
        capturedIsDisabled || isDisabled
    }
    
    /// Display text based on saved state
    private var buttonText: String {
        capturedIsSaved ? "Saved" : "Save"
    }
    
    /// Accessibility label based on current state
    private var accessibilityLabel: String {
        if capturedIsSaved {
            return "Saved"
        } else if stableIsDisabled {
            return "Save unavailable"
        } else {
            return "Save"
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        Button(buttonText) {
            onSave()
        }
        .foregroundStyle(stableIsDisabled ? AppColors.textTertiary : AppColors.accent)
        .fontWeight(capturedIsSaved ? .regular : .semibold)
        .disabled(stableIsDisabled)
        .accessibilityLabel(accessibilityLabel)
        .onAppear {
            // Capture initial state
            capturedIsSaved = isSaved
            capturedIsDisabled = isDisabled
        }
        .onChange(of: isDisabled) { _, newValue in
            // Once disabled, stay disabled
            if newValue {
                capturedIsDisabled = true
            }
        }
        .onChange(of: isSaved) { _, newValue in
            // Once saved, stay saved
            if newValue {
                capturedIsSaved = true
            }
        }
    }
}

// MARK: - Previews

#Preview("Save Button - Active") {
    NavigationStack {
        Text("Content")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    SaveToolbarButton(
                        isSaved: false,
                        isDisabled: false,
                        onSave: { print("Save tapped") }
                    )
                }
            }
    }
}

#Preview("Save Button - Saved") {
    NavigationStack {
        Text("Content")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    SaveToolbarButton(
                        isSaved: true,
                        isDisabled: true,
                        onSave: { }
                    )
                }
            }
    }
}

#Preview("Save Button - Disabled") {
    NavigationStack {
        Text("Content")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    SaveToolbarButton(
                        isSaved: false,
                        isDisabled: true,
                        onSave: { }
                    )
                }
            }
    }
}
