//
//  Item.swift
//  ACI Admin
//
//  Created by Timothy Odei Yirenkyi on 8/30/26.
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
