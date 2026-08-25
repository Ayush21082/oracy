//
//  Item.swift
//  OneWord
//
//  Created by Ayush Singh on 25/08/26.
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
