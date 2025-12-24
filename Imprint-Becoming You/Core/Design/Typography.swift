//
//  Typography.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import SwiftUI

// MARK: - App Typography

/// Centralized typography definitions for the Imprint design system.
///
/// Uses SF Pro family for native iOS feel with optimal readability:
/// - **SF Pro Rounded**: For affirmations and friendly, positive content
/// - **SF Pro Display**: For headlines and bold statements
/// - **SF Pro Text**: For body copy and UI elements
///
/// All fonts support Dynamic Type for accessibility.
enum AppTypography {
    
    // MARK: - Affirmation Styles
    
    /// Large affirmation text for main display
    /// SF Pro Rounded, 32pt, Medium
    static let affirmationLarge = Font.system(size: 32, weight: .medium, design: .rounded)
    
    /// Standard affirmation text
    /// SF Pro Rounded, 28pt, Medium
    static let affirmation = Font.system(size: 28, weight: .medium, design: .rounded)
    
    /// Smaller affirmation for compact layouts
    /// SF Pro Rounded, 24pt, Medium
    static let affirmationSmall = Font.system(size: 24, weight: .medium, design: .rounded)
    
    // MARK: - Headline Styles
    
    /// Large title - Screen headers
    /// SF Pro Display, 34pt, Bold
    static let largeTitle = Font.system(size: 34, weight: .bold, design: .default)
    
    /// Title 1 - Section headers
    /// SF Pro Display, 28pt, Bold
    static let title1 = Font.system(size: 28, weight: .bold, design: .default)
    
    /// Title 2 - Subsection headers
    /// SF Pro Display, 22pt, Bold
    static let title2 = Font.system(size: 22, weight: .bold, design: .default)
    
    /// Title 3 - Card headers
    /// SF Pro Display, 20pt, Semibold
    static let title3 = Font.system(size: 20, weight: .semibold, design: .default)
    
    // MARK: - Body Styles
    
    /// Headline - Emphasized body text
    /// SF Pro Text, 17pt, Semibold
    static let headline = Font.system(size: 17, weight: .semibold, design: .default)
    
    /// Body - Standard body text
    /// SF Pro Text, 17pt, Regular
    static let body = Font.system(size: 17, weight: .regular, design: .default)
    
    /// Callout - Secondary body text
    /// SF Pro Text, 16pt, Regular
    static let callout = Font.system(size: 16, weight: .regular, design: .default)
    
    /// Subheadline - Tertiary body text
    /// SF Pro Text, 15pt, Regular
    static let subheadline = Font.system(size: 15, weight: .regular, design: .default)
    
    /// Footnote - Small supporting text
    /// SF Pro Text, 13pt, Regular
    static let footnote = Font.system(size: 13, weight: .regular, design: .default)
    
    /// Caption 1 - Labels and metadata
    /// SF Pro Text, 12pt, Regular
    static let caption1 = Font.system(size: 12, weight: .regular, design: .default)
    
    /// Caption 2 - Smallest text
    /// SF Pro Text, 11pt, Regular
    static let caption2 = Font.system(size: 11, weight: .regular, design: .default)
    
    // MARK: - Button Styles
    
    /// Primary button text
    /// SF Pro Text, 17pt, Semibold
    static let buttonPrimary = Font.system(size: 17, weight: .semibold, design: .default)
    
    /// Secondary button text
    /// SF Pro Text, 15pt, Medium
    static let buttonSecondary = Font.system(size: 15, weight: .medium, design: .default)
    
    /// Small button/link text
    /// SF Pro Text, 13pt, Medium
    static let buttonSmall = Font.system(size: 13, weight: .medium, design: .default)
    
    // MARK: - Number Styles
    
    /// Large numbers for stats/scores
    /// SF Pro Rounded, 48pt, Bold, Monospaced
    static let numberLarge = Font.system(size: 48, weight: .bold, design: .rounded).monospacedDigit()
    
    /// Medium numbers
    /// SF Pro Rounded, 32pt, Semibold, Monospaced
    static let numberMedium = Font.system(size: 32, weight: .semibold, design: .rounded).monospacedDigit()
    
    /// Small numbers
    /// SF Pro Rounded, 20pt, Medium, Monospaced
    static let numberSmall = Font.system(size: 20, weight: .medium, design: .rounded).monospacedDigit()
}

// MARK: - Dynamic Type Support

extension Font {
    
    /// Creates an affirmation font that scales with Dynamic Type
    /// - Parameter size: Base size at default text size
    /// - Returns: Scaled font
    static func affirmation(size: CGFloat = 28) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }
    
    /// Creates a headline font that scales with Dynamic Type
    /// - Parameter size: Base size at default text size
    /// - Returns: Scaled font
    static func appHeadline(size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }
    
    /// Creates a body font that scales with Dynamic Type
    /// - Parameter size: Base size at default text size
    /// - Returns: Scaled font
    static func appBody(size: CGFloat = 17) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }
}

// MARK: - Text Style Modifiers

/// View modifier for applying consistent text styling
struct AppTextStyle: ViewModifier {
    let font: Font
    let color: Color
    let lineSpacing: CGFloat
    
    init(
        font: Font,
        color: Color = AppColors.textPrimary,
        lineSpacing: CGFloat = 4
    ) {
        self.font = font
        self.color = color
        self.lineSpacing = lineSpacing
    }
    
    func body(content: Content) -> some View {
        content
            .font(font)
            .foregroundStyle(color)
            .lineSpacing(lineSpacing)
    }
}

// MARK: - View Extensions

extension View {
    
    /// Applies affirmation text styling
    func affirmationStyle(size: AffirmationSize = .standard) -> some View {
        self.modifier(AppTextStyle(
            font: size.font,
            color: AppColors.textPrimary,
            lineSpacing: 8
        ))
    }
    
    /// Applies title text styling
    func titleStyle(_ level: TitleLevel = .title1) -> some View {
        self.modifier(AppTextStyle(
            font: level.font,
            color: AppColors.textPrimary
        ))
    }
    
    /// Applies body text styling
    func bodyStyle(secondary: Bool = false) -> some View {
        self.modifier(AppTextStyle(
            font: AppTypography.body,
            color: secondary ? AppColors.textSecondary : AppColors.textPrimary
        ))
    }
    
    /// Applies caption text styling
    func captionStyle() -> some View {
        self.modifier(AppTextStyle(
            font: AppTypography.caption1,
            color: AppColors.textTertiary
        ))
    }
}

// MARK: - Affirmation Size

/// Size variants for affirmation text
enum AffirmationSize {
    case large
    case standard
    case small
    
    var font: Font {
        switch self {
        case .large:
            return AppTypography.affirmationLarge
        case .standard:
            return AppTypography.affirmation
        case .small:
            return AppTypography.affirmationSmall
        }
    }
}

// MARK: - Title Level

/// Level variants for title text
enum TitleLevel {
    case largeTitle
    case title1
    case title2
    case title3
    
    var font: Font {
        switch self {
        case .largeTitle:
            return AppTypography.largeTitle
        case .title1:
            return AppTypography.title1
        case .title2:
            return AppTypography.title2
        case .title3:
            return AppTypography.title3
        }
    }
}

// MARK: - Preview

#Preview("Typography") {
    ScrollView {
        VStack(alignment: .leading, spacing: 32) {
            // Affirmation Styles
            typographySection(title: "Affirmations") {
                Text("I am confident")
                    .font(AppTypography.affirmationLarge)
                Text("I am capable")
                    .font(AppTypography.affirmation)
                Text("I am worthy")
                    .font(AppTypography.affirmationSmall)
            }
            
            // Headline Styles
            typographySection(title: "Headlines") {
                Text("Large Title")
                    .font(AppTypography.largeTitle)
                Text("Title 1")
                    .font(AppTypography.title1)
                Text("Title 2")
                    .font(AppTypography.title2)
                Text("Title 3")
                    .font(AppTypography.title3)
            }
            
            // Body Styles
            typographySection(title: "Body") {
                Text("Headline Text")
                    .font(AppTypography.headline)
                Text("Body Text")
                    .font(AppTypography.body)
                Text("Callout Text")
                    .font(AppTypography.callout)
                Text("Subheadline Text")
                    .font(AppTypography.subheadline)
                Text("Footnote Text")
                    .font(AppTypography.footnote)
                Text("Caption 1 Text")
                    .font(AppTypography.caption1)
                Text("Caption 2 Text")
                    .font(AppTypography.caption2)
            }
            
            // Number Styles
            typographySection(title: "Numbers") {
                Text("85%")
                    .font(AppTypography.numberLarge)
                Text("1,234")
                    .font(AppTypography.numberMedium)
                Text("42")
                    .font(AppTypography.numberSmall)
            }
        }
        .padding()
        .foregroundStyle(AppColors.textPrimary)
    }
    .background(AppColors.backgroundPrimary)
}

@ViewBuilder
private func typographySection(
    title: String,
    @ViewBuilder content: () -> some View
) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        Text(title)
            .font(AppTypography.caption1)
            .foregroundStyle(AppColors.textTertiary)
            .textCase(.uppercase)
            .tracking(1.5)
        
        content()
    }
}
