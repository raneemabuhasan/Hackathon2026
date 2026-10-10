//
//  Item.swift
//  MenstrualCycleWellnessCompanion
//
//  Created by Raneem Abuhasan  on 10/9/26.
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
