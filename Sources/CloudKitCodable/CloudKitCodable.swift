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
        
    var cloudIdentifier: CloudKitIdentifier { get }
}

/// CloudKit Decodable
public protocol CloudKitDecodable: Swift.Decodable {
        
    var cloudIdentifier: CloudKitIdentifier { get }
}

public protocol CloudKitCodingKey: CodingKey {
    
    static var cloudIdentifierKey: Self { get }
}

public protocol CloudKitIdentifier {
    
    /// Cloud Record Type
    static var cloudRecordType: CKRecord.RecordType { get }
    
    /// Cloud Record ID
    var cloudRecordID: CKRecord.ID { get }
    
    init?(cloudRecordID: CKRecord.ID)
}
