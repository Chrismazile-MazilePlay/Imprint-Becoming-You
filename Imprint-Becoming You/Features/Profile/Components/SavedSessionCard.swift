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
/// the card, and swipe actions reveal edit/delete/info options.
///
/// ## Swipe Actions (left-to-right when revealed)
/// - **Info** (blue) - View session affirmations; full-swipe navigates directly
/// - **Edit** (accent) - Enter edit mode for renaming
/// - **Delete** (red) - Show delete confirmation
///
/// ## States
///
/// | State | Border | Swipe Enabled |
/// |-------|--------|---------------|
/// | Normal | Standard | Yes |
/// | Selected | Accent | Yes |
/// | Editing | Standard | No |
///
/// ## Layout
/// ```
/// ┌────────────────────────────────────────────────────────────┐
/// │  Morning Confidence                                        │
/// │  5 affirmations • Last played today                        │
/// └────────────────────────────────────────────────────────────┘
/// ```
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
    
    /// Callback when edit action is triggered (via swipe)
    let onEdit: () -> Void
    
    /// Callback when info action is triggered (via swipe or full-swipe)
    let onInfo: () -> Void
    
    /// Callback when delete action is triggered (via swipe)
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
    
    // MARK: - Body
    
    var body: some View {
        cardContent
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isAnyCardEditing else { return }
                // Dismiss any open swipe actions when tapping a card
                SwipeActionSharedState.shared.dismissAll()
                onTap()
            }
            .swipeActions(
                isEnabled: !isAnyCardEditing,
                onFullSwipe: {
                    // Full-swipe navigates to affirmation list
                    onInfo()
                }
            ) {
                SwipeAction(
                    symbolImage: "info.circle",
                    tint: .white,
                    background: .blue
                ) { reset in
                    reset.toggle()
                    onInfo()
                }
                
                SwipeAction(
                    symbolImage: "pencil",
                    tint: .white,
                    background: AppColors.accent
                ) { reset in
                    reset.toggle()
                    onEdit()
                }
                
                SwipeAction(
                    symbolImage: "trash.fill",
                    tint: .white,
                    background: AppColors.error
                ) { reset in
                    reset.toggle()
                    onDelete()
                }
            }
            .onChange(of: isEditing) { wasEditing, nowEditing in
                if nowEditing {
                    // Entering edit mode - initialize title and focus immediately
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
            // Title row
            if isEditing {
                TextField("Session name", text: $editingTitle)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                    .focused($isTitleFieldFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        onTitleChanged(editingTitle)
                        onTitleCommit()
                    }
                    .onChange(of: editingTitle) { _, newValue in
                        onTitleChanged(newValue)
                    }
            } else {
                Text(session.name)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
            }
            
            // Subtitle row
            Text(subtitleText)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                .fill(AppColors.backgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                .stroke(isSelected ? AppColors.accent : Color.clear, lineWidth: 2)
        )
    }
    
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

#Preview("Swipe Actions Demo") {
    ScrollView {
        VStack(spacing: AppTheme.Spacing.md) {
            ForEach(0..<3) { index in
                SavedSessionCard(
                    session: SavedSession(
                        name: "Session \(index + 1)",
                        affirmationIds: Array(repeating: UUID(), count: index + 2),
                        defaultMode: .readThenSpeak,
                        affirmations: []
                    ),
                    isSelected: index == 0,
                    isEditing: false,
                    isAnyCardEditing: false,
                    onTap: { print("Tapped \(index + 1)") },
                    onEdit: { print("Edit \(index + 1)") },
                    onInfo: { print("Info \(index + 1)") },
                    onDelete: { print("Delete \(index + 1)") },
                    onTitleChanged: { _ in },
                    onTitleCommit: {}
                )
            }
        }
        .padding()
    }
    .background(AppColors.backgroundPrimary)
}
