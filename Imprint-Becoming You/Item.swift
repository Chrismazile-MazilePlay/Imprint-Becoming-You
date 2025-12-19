//
//  Item.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/19/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
