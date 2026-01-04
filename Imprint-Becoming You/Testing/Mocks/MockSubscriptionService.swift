//
//  MockSubscriptionService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Mock Subscription Service

/// Mock implementation of subscription service for previews and testing.
///
/// Simulates StoreKit operations without actual purchases.
final class MockSubscriptionService: SubscriptionServiceProtocol, @unchecked Sendable {
    
    // MARK: - Configuration
    
    /// Whether to simulate premium status
    var simulatePremium: Bool = false
    
    /// Simulated subscription status
    var simulatedStatus: SubscriptionStatus = .notSubscribed
    
    // MARK: - SubscriptionServiceProtocol
    
    var isPremium: Bool {
        get async { simulatePremium }
    }
    
    var subscriptionStatus: SubscriptionStatus {
        get async { simulatedStatus }
    }
    
    lazy var statusStream: AsyncStream<SubscriptionStatus> = {
        AsyncStream { _ in
            // Mock doesn't emit status changes
        }
    }()
    
    func getProducts() async throws -> [SubscriptionProduct] {
        [
            SubscriptionProduct(
                id: "com.imprint.monthly",
                displayName: "Monthly",
                description: "Billed monthly",
                displayPrice: "$9.99",
                period: .monthly
            ),
            SubscriptionProduct(
                id: "com.imprint.annual",
                displayName: "Annual",
                description: "Billed annually (save 33%)",
                displayPrice: "$79.99",
                period: .annual
            )
        ]
    }
    
    func purchase(productId: String) async throws {
        // Simulate successful purchase
        simulatePremium = true
        simulatedStatus = .subscribed
    }
    
    func restorePurchases() async throws {
        // No-op for mock
    }
}
