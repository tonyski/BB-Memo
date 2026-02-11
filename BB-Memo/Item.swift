//
//  Item.swift
//  BB-Memo
//
//  Created by Tonyski on 2026/2/11.
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
