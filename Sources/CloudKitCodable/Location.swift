//
//  Location.swift
//  
//
//  Created by Alsey Coleman Miller on 9/11/19.
//

import Foundation
import CoreLocation

/// CloudKit Location Encodable
public protocol CloudKitLocation: Codable {
    
    init(location: CLLocation)
    
    var location: CLLocation { get }
}
