//
//  SubscriptionServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Subscription Service Protocol

/// Protocol for StoreKit subscription management.
///
/// Manages in-app subscription purchases, status tracking, and
/// purchase restoration for premium features.
///
/// ## Usage
/// ```swift
/// let subscription: SubscriptionServiceProtocol = SubscriptionService()
///
/// // Check premium status
/// if await subscription.isPremium {
///     // Enable premium features
/// }
///
/// // Purchase a subscription
/// let products = try await subscription.getProducts()
/// try await subscription.purchase(productId: products.first!.id)
///
/// // Listen for status changes
/// for await status in subscription.statusStream {
///     updateUI(for: status)
/// }
/// ```
protocol SubscriptionServiceProtocol: AnyObject, Sendable {
    
    /// Whether the user currently has an active premium subscription
    var isPremium: Bool { get async }
    
    /// Current subscription status
    var subscriptionStatus: SubscriptionStatus { get async }
    
    /// Fetches available subscription products from the App Store
    /// - Returns: Array of available subscription products
    /// - Throws: StoreKit errors or `AppError.notImplemented`
    func getProducts() async throws -> [SubscriptionProduct]
    
    /// Initiates a purchase for the given product
    /// - Parameter productId: The product identifier to purchase
    /// - Throws: Purchase errors or `AppError.notImplemented`
    func purchase(productId: String) async throws
    
    /// Restores previously purchased subscriptions
    /// - Throws: Restore errors or `AppError.notImplemented`
    func restorePurchases() async throws
    
    /// Stream of subscription status changes
    var statusStream: AsyncStream<SubscriptionStatus> { get }
}

// MARK: - Subscription Status

/// Represents the current state of the user's subscription
enum SubscriptionStatus: String, Sendable {
    /// User has never subscribed or subscription has fully lapsed
    case notSubscribed
    
    /// User has an active subscription
    case subscribed
    
    /// Subscription has expired and is no longer active
    case expired
    
    /// Subscription is in grace period (payment failed but still active)
    case inGracePeriod
}

// MARK: - Subscription Product

/// Information about an available subscription product
struct SubscriptionProduct: Identifiable, Sendable {
    /// StoreKit product identifier
    let id: String
    
    /// Localized display name
    let displayName: String
    
    /// Localized description
    let description: String
    
    /// Formatted price string (e.g., "$9.99")
    let displayPrice: String
    
    /// Billing period for this subscription
    let period: SubscriptionPeriod
}

// MARK: - Subscription Period

/// Billing period for subscription products
enum SubscriptionPeriod: String, Sendable {
    /// Billed every month
    case monthly
    
    /// Billed every year
    case annual
}
