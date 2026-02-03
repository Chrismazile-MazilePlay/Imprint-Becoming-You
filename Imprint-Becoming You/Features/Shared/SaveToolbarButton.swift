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
/// Displays a "Save" label that appears when there are unsaved changes and
/// disappears when there are none. Purely state-driven, zero internal state.
///
/// ## Lifecycle (consistent across all views)
/// - **Hidden** when `hasUnsavedChanges` is false
/// - **Visible + Enabled** when `hasUnsavedChanges` is true
/// - After save: parent updates its saved baseline -> `hasUnsavedChanges` becomes
///   false -> button disappears in the same render pass
///
/// ## Performance
/// No internal state. No animation modifiers. The button is a pure function
/// of `hasUnsavedChanges` -- SwiftUI diffs a single Bool and updates visibility.
///
/// ## Usage
/// ```swift
/// .toolbar {
///     ToolbarItem(placement: .primaryAction) {
///         SaveToolbarButton(
///             hasUnsavedChanges: selectedId != savedId,
///             onSave: { saveSelection() }
///         )
///     }
/// }
/// ```
struct SaveToolbarButton: View {
    
    // MARK: - Properties
    
    /// Whether the parent view has unsaved changes.
    /// When true, the button is visible. When false, hidden.
    let hasUnsavedChanges: Bool
    
    /// Accessibility hint shown when the button is visible.
    let accessibilityHint: String
    
    /// Action to perform when save is tapped.
    /// The parent should update its saved baseline in this closure so that
    /// `hasUnsavedChanges` becomes false on the next render.
    let onSave: () -> Void
    
    // MARK: - Initialization
    
    init(
        hasUnsavedChanges: Bool,
        accessibilityHint: String = "Saves your changes",
        onSave: @escaping () -> Void
    ) {
        self.hasUnsavedChanges = hasUnsavedChanges
        self.accessibilityHint = accessibilityHint
        self.onSave = onSave
    }
    
    // MARK: - Body
    
    var body: some View {
        if hasUnsavedChanges {
            Button("Save") {
                onSave()
            }
            .foregroundStyle(AppColors.accent)
            .fontWeight(.semibold)
            .accessibilityLabel("Save")
            .accessibilityHint(accessibilityHint)
        }
    }
}

// MARK: - Previews

#Preview("Save Button - Visible") {
    NavigationStack {
        Text("Has unsaved changes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    SaveToolbarButton(
                        hasUnsavedChanges: true,
                        onSave: { print("Save tapped") }
                    )
                }
            }
    }
}

#Preview("Save Button - Hidden") {
    NavigationStack {
        Text("No button visible")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    SaveToolbarButton(
                        hasUnsavedChanges: false,
                        onSave: {}
                    )
                }
            }
    }
}
