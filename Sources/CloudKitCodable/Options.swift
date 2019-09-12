//
//  File.swift
//  
//
//  Created by Alsey Coleman Miller on 9/11/19.
//

import Foundation
import CloudKit

/// CloudKit Encoder Options
public struct CloudKitCodingOptions {
    
    /// Which coding key to use as the CloudKit record name.
    public var identifierKey: IdentifierKeyStrategy = { $0.stringValue == "id" }
    
    /// Which URLs to use as CloudKit assets.
    public var assets: AssetStrategy = { return $0.isFileURL }
}

public extension CloudKitCodingOptions {
    
    /// Which coding key to use as the CloudKit record name.
    typealias IdentifierKeyStrategy = (CodingKey) -> (Bool)
    
    /// Which URLs to use as CloudKit assets.
    typealias AssetStrategy = (URL) -> Bool
}
