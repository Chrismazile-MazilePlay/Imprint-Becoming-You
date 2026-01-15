//
//  SavedSessionCard.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/12/26.
//

import SwiftUI

// MARK: - SavedSessionCard

/// A card representing a saved session in the list view.
///
/// Supports selection-based interaction model where tapping selects/deselects
/// the card, and a global configuration bar controls playback settings.
///
/// ## States
///
/// | State | This Card Icons | Other Cards | Border |
/// |-------|-----------------|-------------|--------|
/// | Normal | ✏️ ⓘ | ✏️ ⓘ | Standard |
/// | Selected | ✏️ ⓘ | ✏️ ⓘ | Accent |
/// | Editing | ✏️ 🗑️ | (hidden) | Standard |
///
/// ## Layout
/// Icons are aligned with the title row (top of card):
/// ```
/// ┌────────────────────────────────────────────────────────────┐
/// │  Morning Confidence                           ✏️     ⓘ    │
/// │  5 affirmations • Last played today                       │
/// └────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Layout Locking
/// When icons are hidden (during edit mode on other cards), space is reserved
/// using `.opacity(0)` to prevent text reflow.
struct SavedSessionCard: View {
    
    // MARK: - Properties
    
    /// The saved session to display
    let session: SavedSession
    
    /// Whether this card is currently selected
    let isSelected: Bool
    
    /// Whether this card is in edit mode
    let isEditing: Bool
    
    /// Whether ANY card in the list is being edited
    let isAnyCardEditing: Bool
    
    /// Callback when card is tapped (for selection)
    let onTap: () -> Void
    
    /// Callback when edit button is tapped
    let onEdit: () -> Void
    
    /// Callback when info button is tapped
    let onInfo: () -> Void
    
    /// Callback when delete button is tapped (only in edit mode)
    let onDelete: () -> Void
    
    /// Callback when title changes during editing (for tracking current value)
    let onTitleChanged: (String) -> Void
    
    /// Callback when editing is committed (Return key pressed)
    let onTitleCommit: () -> Void
    
    // MARK: - State
    
    /// Local title for editing (two-way sync with parent via callback)
    @State private var editingTitle: String = ""
    
    /// Focus state for the text field
    @FocusState private var isTitleFieldFocused: Bool
    
    // MARK: - Computed Properties
    
    /// Whether to show icons on this card
    private var showIcons: Bool {
        // Show icons if: not editing OR this is the editing card
        !isAnyCardEditing || isEditing
    }
    
    /// Whether info button is enabled
    private var isInfoEnabled: Bool {
        // Disabled when this card is being edited
        !isEditing
    }
    
    // MARK: - Body
    
    var body: some View {
        Button {
            onTap()
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .disabled(isAnyCardEditing && !isEditing)
        .onChange(of: isEditing) { wasEditing, nowEditing in
            if nowEditing {
                // Entering edit mode - initialize title
                editingTitle = session.name
                isTitleFieldFocused = true
            } else if wasEditing {
                // Exiting edit mode - clear focus
                isTitleFieldFocused = false
            }
        }
    }
    
    // MARK: - Card Content
    
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            // Title row with icons overlaid
            HStack(spacing: AppTheme.Spacing.sm) {
                // Title (text or text field)
                if isEditing {
                    TextField("Session name", text: $editingTitle)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                        .focused($isTitleFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            // Notify parent to save and exit edit mode
                            onTitleChanged(editingTitle)
                            onTitleCommit()
                        }
                        .onChange(of: editingTitle) { _, newValue in
                            // Keep parent informed of changes for Done button
                            onTitleChanged(newValue)
                        }
                } else {
                    Text(session.name)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
                
                // Invisible spacer to reserve width for icons (prevents text reflow)
                Color.clear
                    .frame(width: iconAreaWidth, height: 1)
            }
            .overlay(alignment: .trailing) {
                // Action icons overlaid, vertically centered with title
                actionIcons
                    .opacity(showIcons ? 1 : 0)
            }
            
            // Subtitle row
            Text(subtitleText)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                .fill(AppColors.backgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                .stroke(isSelected ? AppColors.accent : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
    }
    
    // MARK: - Constants
    
    /// Width reserved for the icon area (2 icons with compact spacing)
    private let iconAreaWidth: CGFloat = 72
    
    // MARK: - Subtitle
    
    private var subtitleText: String {
        let count = session.affirmationIds.count
        let countText = "\(count) affirmation\(count == 1 ? "" : "s")"
        
        if let lastPlayed = session.lastPlayedAt {
            let relative = lastPlayed.formatted(.relative(presentation: .named))
            return "\(countText) • Last played \(relative)"
        } else {
            return countText
        }
    }
    
    // MARK: - Action Icons
    
    /// Action icons with 44pt tap targets (Apple HIG minimum).
    /// Overlaid on title row and vertically centered with title text.
    private var actionIcons: some View {
        HStack(spacing: -8) {
            // Edit button (always visible when icons show)
            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Edit session name")
            
            if isEditing {
                // Delete button (only in edit mode)
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(AppColors.destructive)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Delete session")
            } else {
                // Info button (normal mode)
                Button {
                    onInfo()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(isInfoEnabled ? AppColors.textSecondary : AppColors.textTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(!isInfoEnabled)
                .accessibilityLabel("Session info")
            }
        }
    }
}

// MARK: - Previews

#Preview("Saved Session Card - Normal") {
    VStack(spacing: AppTheme.Spacing.md) {
        SavedSessionCard(
            session: SavedSession(
                name: "Morning Confidence",
                affirmationIds: Array(repeating: UUID(), count: 5),
                defaultMode: .readThenSpeak,
                affirmations: []
            ),
            isSelected: false,
            isEditing: false,
            isAnyCardEditing: false,
            onTap: {},
            onEdit: {},
            onInfo: {},
            onDelete: {},
            onTitleChanged: { _ in },
            onTitleCommit: {}
        )
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("Saved Session Card - Selected") {
    VStack(spacing: AppTheme.Spacing.md) {
        SavedSessionCard(
            session: SavedSession(
                name: "Evening Gratitude",
                affirmationIds: Array(repeating: UUID(), count: 3),
                defaultMode: .readAloud,
                affirmations: []
            ),
            isSelected: true,
            isEditing: false,
            isAnyCardEditing: false,
            onTap: {},
            onEdit: {},
            onInfo: {},
            onDelete: {},
            onTitleChanged: { _ in },
            onTitleCommit: {}
        )
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("Saved Session Card - Editing") {
    VStack(spacing: AppTheme.Spacing.md) {
        SavedSessionCard(
            session: SavedSession(
                name: "Focus Session",
                affirmationIds: Array(repeating: UUID(), count: 8),
                defaultMode: .speakOnly,
                affirmations: []
            ),
            isSelected: false,
            isEditing: true,
            isAnyCardEditing: true,
            onTap: {},
            onEdit: {},
            onInfo: {},
            onDelete: {},
            onTitleChanged: { _ in },
            onTitleCommit: {}
        )
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("Saved Session Cards - One Editing") {
    VStack(spacing: AppTheme.Spacing.md) {
        // This card is editing
        SavedSessionCard(
            session: SavedSession(
                name: "Session Being Edited",
                affirmationIds: Array(repeating: UUID(), count: 5),
                defaultMode: .readThenSpeak,
                affirmations: []
            ),
            isSelected: false,
            isEditing: true,
            isAnyCardEditing: true,
            onTap: {},
            onEdit: {},
            onInfo: {},
            onDelete: {},
            onTitleChanged: { _ in },
            onTitleCommit: {}
        )
        
        // This card is NOT editing - icons hidden but layout preserved
        SavedSessionCard(
            session: SavedSession(
                name: "Other Session",
                affirmationIds: Array(repeating: UUID(), count: 3),
                defaultMode: .readAloud,
                affirmations: []
            ),
            isSelected: false,
            isEditing: false,
            isAnyCardEditing: true,
            onTap: {},
            onEdit: {},
            onInfo: {},
            onDelete: {},
            onTitleChanged: { _ in },
            onTitleCommit: {}
        )
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}
