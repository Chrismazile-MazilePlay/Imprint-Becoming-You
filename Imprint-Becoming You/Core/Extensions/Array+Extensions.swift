//
//  Array+Extensions.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/9/26.
//

// MARK: - Array Safe Subscript

public extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Array Unique By ID

extension Array where Element: Identifiable {

    /// Returns elements deduplicated by their `id`, preserving first-occurrence order.
    ///
    /// Used as a fallback when collapsing a spaced-repetition-expanded array
    /// back to unique base affirmations. Prefer fetching from the repository
    /// via `originalSessionAffirmationIds` when available.
    func uniqueByID() -> [Element] {
        var seen = Set<Element.ID>()
        return filter { seen.insert($0.id).inserted }
    }
}
