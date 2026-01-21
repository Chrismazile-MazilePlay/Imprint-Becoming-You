//
//  CardListSheetWithDock.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/14/26.
//

import SwiftUI

// MARK: - CardListSheetWithDock

/// A reusable full-screen sheet layout for card-list views with unified dock handling.
///
/// Provides consistent layout for views that display:
/// - A scrollable list of cards
/// - A fixed bottom dock with configuration controls
/// - Optional header content above the cards
/// - Empty state when no cards are available
///
/// ## Features
/// - Uses `AdaptiveDockContainer` internally for unified dock/menu behavior
/// - NavigationStack with configurable toolbar (parent applies via `.toolbar` modifier)
/// - ScrollView with proper bottom padding for dock
/// - Header slot for custom content (e.g., ResultsSummary checkmark/loop progress)
/// - Empty state slot using Apple's `ContentUnavailableView`
///
/// ## Layout
/// ```
/// ┌─────────────────────────────────────────────────────────────────┐
/// │  [Cancel]         Title         [Done/Save]  ← Toolbar (parent) │
/// ├─────────────────────────────────────────────────────────────────┤
/// │                                                                 │
/// │                    [Header Content]           ← Optional header │
/// │                                                                 │
/// │  ┌─────────────────────────────────────────────────────────┐   │
/// │  │  Card 1                                                 │   │
/// │  └─────────────────────────────────────────────────────────┘   │
/// │  ┌─────────────────────────────────────────────────────────┐   │  ← Scrollable
/// │  │  Card 2                                                 │   │
/// │  └─────────────────────────────────────────────────────────┘   │
/// │                         ...                                     │
/// │                                                                 │
/// ├═════════════════════════════════════════════════════════════════┤
/// │  ░░░░░░░░ (gradient fade) ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │
/// │  [Mode ▼]       [🔁 3] [🔀]         [▶]    ← Dock              │
/// │            "Label text"                    ← Optional label    │
/// └─────────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Usage
/// ```swift
/// CardListSheetWithDock(
///     isModeSelectorExpanded: $expanded,
///     selectedMode: $mode,
///     onModeSelected: { mode in print("Selected: \(mode)") },
///     dockLabel: "Repeat Session",
///     header: {
///         ResultsSummaryHeaderView(...)
///     },
///     cards: {
///         ForEach(results) { result in
///             SessionAffirmationCard(result: result)
///         }
///     },
///     emptyState: {
///         ContentUnavailableView("No Results", systemImage: "doc")
///     },
///     dock: {
///         AdaptiveBottomDock(...)
///     },
///     isEmpty: results.isEmpty
/// )
/// .navigationTitle("Session Complete")
/// .toolbar { ... }
/// ```
struct CardListSheetWithDock<
    Header: View,
    Cards: View,
    EmptyContent: View,
    DockContent: View
>: View {
    
    // MARK: - Properties
    
    /// Whether the mode selector is expanded
    @Binding var isModeSelectorExpanded: Bool
    
    /// Currently selected session mode
    @Binding var selectedMode: SessionMode
    
    /// Optional callback when a mode is selected
    var onModeSelected: ((SessionMode) -> Void)?
    
    /// Label to display below the dock
    var dockLabel: String
    
    /// Whether the content list is empty
    var isEmpty: Bool
    
    /// Header content builder (above cards)
    @ViewBuilder var header: () -> Header
    
    /// Cards content builder (scrollable list)
    @ViewBuilder var cards: () -> Cards
    
    /// Empty state content builder
    @ViewBuilder var emptyState: () -> EmptyContent
    
    /// Dock content builder
    @ViewBuilder var dock: () -> DockContent
    
    // MARK: - Constants
    
    /// Height reserved for the dock area at bottom
    private let dockAreaHeight: CGFloat = 160
    
    // MARK: - Initialization
    
    /// Creates a card list sheet with dock.
    ///
    /// - Parameters:
    ///   - isModeSelectorExpanded: Binding to mode selector expansion state
    ///   - selectedMode: Binding to the selected session mode
    ///   - onModeSelected: Optional callback when a mode is selected
    ///   - dockLabel: Label text below the dock (empty string = no label)
    ///   - header: Header content builder
    ///   - cards: Cards content builder
    ///   - emptyState: Empty state content builder
    ///   - dock: Dock content builder
    ///   - isEmpty: Whether the content list is empty
    init(
        isModeSelectorExpanded: Binding<Bool>,
        selectedMode: Binding<SessionMode>,
        onModeSelected: ((SessionMode) -> Void)? = nil,
        dockLabel: String = "",
        @ViewBuilder header: @escaping () -> Header = { EmptyView() },
        @ViewBuilder cards: @escaping () -> Cards,
        @ViewBuilder emptyState: @escaping () -> EmptyContent,
        @ViewBuilder dock: @escaping () -> DockContent,
        isEmpty: Bool
    ) {
        self._isModeSelectorExpanded = isModeSelectorExpanded
        self._selectedMode = selectedMode
        self.onModeSelected = onModeSelected
        self.dockLabel = dockLabel
        self.header = header
        self.cards = cards
        self.emptyState = emptyState
        self.dock = dock
        self.isEmpty = isEmpty
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Background
            AppColors.backgroundPrimary
                .ignoresSafeArea()
            
            // Content layer
            if isEmpty {
                emptyStateView
            } else {
                scrollableContent
            }
            
            // Fixed dock layer
            AdaptiveDockContainer1(
                isModeSelectorExpanded: $isModeSelectorExpanded,
                selectedMode: $selectedMode,
                onModeSelected: onModeSelected,
                label: dockLabel,
                showGradient: true,
                dock: dock
            )
        }
    }
    
    // MARK: - Scrollable Content
    
    private var scrollableContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header (if provided)
                header()
                
                // Cards
                LazyVStack(spacing: AppTheme.Spacing.md) {
                    cards()
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.md)
                
                // Bottom padding for dock
                Color.clear
                    .frame(height: dockAreaHeight)
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack {
            Spacer()
            
            emptyState()
            
            Spacer()
            
            // Padding for dock
            Spacer()
                .frame(height: dockAreaHeight)
        }
        .padding(AppTheme.Spacing.xl)
    }
}

// MARK: - Convenience Initializers

extension CardListSheetWithDock where Header == EmptyView {
    
    /// Creates a card list sheet without a header.
    init(
        isModeSelectorExpanded: Binding<Bool>,
        selectedMode: Binding<SessionMode>,
        onModeSelected: ((SessionMode) -> Void)? = nil,
        dockLabel: String = "",
        @ViewBuilder cards: @escaping () -> Cards,
        @ViewBuilder emptyState: @escaping () -> EmptyContent,
        @ViewBuilder dock: @escaping () -> DockContent,
        isEmpty: Bool
    ) {
        self.init(
            isModeSelectorExpanded: isModeSelectorExpanded,
            selectedMode: selectedMode,
            onModeSelected: onModeSelected,
            dockLabel: dockLabel,
            header: { EmptyView() },
            cards: cards,
            emptyState: emptyState,
            dock: dock,
            isEmpty: isEmpty
        )
    }
}

// MARK: - Previews

#Preview("Card List Sheet - With Content") {
    struct PreviewWrapper: View {
        @State private var expanded = false
        @State private var mode: SessionMode = .readThenSpeak
        
        var body: some View {
            NavigationStack {
                CardListSheetWithDock(
                    isModeSelectorExpanded: $expanded,
                    selectedMode: $mode,
                    dockLabel: "Repeat Session",
                    header: {
                        // Sample header
                        VStack(spacing: AppTheme.Spacing.md) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(AppColors.success)
                            
                            Text("Session Complete")
                                .font(AppTypography.headline)
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        .padding(.top, AppTheme.Spacing.lg)
                        .padding(.bottom, AppTheme.Spacing.md)
                    },
                    cards: {
                        ForEach(0..<5, id: \.self) { i in
                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                                .fill(AppColors.backgroundSecondary)
                                .frame(height: 100)
                                .overlay(
                                    Text("Card \(i + 1)")
                                        .foregroundStyle(AppColors.textSecondary)
                                )
                        }
                    },
                    emptyState: {
                        ContentUnavailableView(
                            "No Results",
                            systemImage: "doc",
                            description: Text("Complete a session to see results")
                        )
                    },
                    dock: {
                        HStack {
                            Button("Mode ▼") {
                                withAnimation(AppTheme.Animation.standard) {
                                    expanded.toggle()
                                }
                            }
                            .padding()
                            .background(AppColors.backgroundSecondary)
                            .clipShape(Capsule())
                            
                            Spacer()
                            
                            Circle()
                                .fill(AppColors.accent)
                                .frame(width: 48, height: 48)
                        }
                    },
                    isEmpty: false
                )
                .navigationTitle("Session Complete")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { }
                            .foregroundStyle(AppColors.accent)
                    }
                }
            }
        }
    }
    
    return PreviewWrapper()
}

#Preview("Card List Sheet - Empty State") {
    struct PreviewWrapper: View {
        @State private var expanded = false
        @State private var mode: SessionMode = .readThenSpeak
        
        var body: some View {
            NavigationStack {
                CardListSheetWithDock(
                    isModeSelectorExpanded: $expanded,
                    selectedMode: $mode,
                    dockLabel: "",
                    cards: {
                        EmptyView()
                    },
                    emptyState: {
                        ContentUnavailableView(
                            "No Saved Sessions",
                            systemImage: "folder",
                            description: Text("Complete a session and save it to see it here")
                        )
                    },
                    dock: {
                        HStack {
                            Button("Mode ▼") { }
                                .padding()
                                .background(AppColors.backgroundSecondary)
                                .clipShape(Capsule())
                                .opacity(0.5)
                            
                            Spacer()
                            
                            Circle()
                                .fill(AppColors.disabled)
                                .frame(width: 48, height: 48)
                        }
                    },
                    isEmpty: true
                )
                .navigationTitle("Saved Sessions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { }
                            .foregroundStyle(AppColors.accent)
                    }
                }
            }
        }
    }
    
    return PreviewWrapper()
}

#Preview("Card List Sheet - Favorites") {
    struct PreviewWrapper: View {
        @State private var expanded = false
        @State private var mode: SessionMode = .readAloud
        
        var body: some View {
            NavigationStack {
                CardListSheetWithDock(
                    isModeSelectorExpanded: $expanded,
                    selectedMode: $mode,
                    dockLabel: "Practice 9 affirmations",
                    cards: {
                        ForEach(0..<9, id: \.self) { i in
                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                                .fill(AppColors.backgroundSecondary)
                                .frame(height: 80)
                                .overlay(
                                    HStack {
                                        Text("Affirmation \(i + 1)")
                                            .foregroundStyle(AppColors.textSecondary)
                                        Spacer()
                                        Image(systemName: "heart.fill")
                                            .foregroundStyle(AppColors.accent)
                                    }
                                    .padding()
                                )
                        }
                    },
                    emptyState: {
                        ContentUnavailableView(
                            "No Favorites Yet",
                            systemImage: "heart.slash",
                            description: Text("Tap the heart on any affirmation to save it here")
                        )
                    },
                    dock: {
                        RoundedRectangle(cornerRadius: AppTheme.CornerRadius.extraLarge)
                            .fill(AppColors.backgroundSecondary)
                            .frame(height: 60)
                    },
                    isEmpty: false
                )
                .navigationTitle("Favorites")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { }
                            .foregroundStyle(AppColors.accent)
                    }
                }
            }
        }
    }
    
    return PreviewWrapper()
}
