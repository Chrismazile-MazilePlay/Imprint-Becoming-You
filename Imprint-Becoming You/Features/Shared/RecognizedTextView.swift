//
//  RecognizedTextView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/4/26.
//

import SwiftUI

// MARK: - RecognizedTextView

/// Displays the real-time recognized speech text during listening phases.
///
/// Shows a semi-transparent card with the text the speech recognition
/// service has captured so far. Animates in from the bottom.
///
/// ## Usage
/// ```swift
/// if phase == .listening && !recognizedText.isEmpty {
///     RecognizedTextView(text: recognizedText)
/// }
/// ```
struct RecognizedTextView: View {
    
    // MARK: - Properties
    
    let text: String
    
    // MARK: - Body
    
    var body: some View {
        Text(text)
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppTheme.Spacing.xl)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(AppColors.backgroundSecondary.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
            .padding(.horizontal, AppTheme.Spacing.lg)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

// MARK: - Previews

#Preview("Recognized Text - Short") {
    ZStack {
        AppColors.backgroundPrimary
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            RecognizedTextView(text: "I am confident...")
            Spacer().frame(height: 200)
        }
    }
}

#Preview("Recognized Text - Long") {
    ZStack {
        AppColors.backgroundPrimary
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            RecognizedTextView(text: "I am confident and capable of achieving my goals every single day")
            Spacer().frame(height: 200)
        }
    }
}
