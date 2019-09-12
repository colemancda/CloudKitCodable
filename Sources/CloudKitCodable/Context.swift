//
//  File.swift
//  
//
//  Created by Alsey Coleman Miller on 9/12/19.
//

import Foundation
import CloudKit

/// CloudKit Decoder context.
public protocol CloudKitContext {
    
    /// Fetch record with identifier.
    func fetch(record: CKRecord.ID) throws -> CKRecord?
}
