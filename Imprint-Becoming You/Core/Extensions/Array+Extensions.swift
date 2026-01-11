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
