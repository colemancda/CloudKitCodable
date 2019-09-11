//
//  CloudKitCodable.swift
//
//
//  Created by Alsey Coleman Miller on 9/10/19.
//

import Foundation
import CloudKit

/// CloudKit Codable
public typealias CloudKitCodable = CloudKitEncodable & CloudKitDecodable

/// CloudKit Encodable
public protocol CloudKitEncodable: Swift.Encodable {
    
    /// Cloud Record Type
    static var cloudRecordType: CKRecord.RecordType { get }
    
    /// Cloud Record ID
    var cloudRecordID: CKRecord.ID { get }
}

/// CloudKit Decodable
public protocol CloudKitDecodable: Swift.Decodable {
    
    /// Cloud Record Type
    static var cloudRecordType: CKRecord.RecordType { get }
    
    /// Cloud Record ID
    var cloudRecordID: CKRecord.ID { get }
}

public protocol CloudKitIdentifier {
    
    /// Cloud Record ID
    var cloudRecordID: CKRecord.ID { get }
}
