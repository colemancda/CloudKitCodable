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
    
    static var identifierKey: CodingKey? { get }
    
    var cloudIdentifier: CloudKitIdentifier { get }
}

/// CloudKit Decodable
public protocol CloudKitDecodable: Swift.Decodable {
    
    static var identifierKey: CodingKey? { get }
    
    var cloudIdentifier: CloudKitIdentifier { get }
}

public protocol CloudKitIdentifier {
    
    /// Cloud Record Type
    static var cloudRecordType: CKRecord.RecordType { get }
    
    /// Cloud Record ID
    var cloudRecordID: CKRecord.ID { get }
    
    init(cloudRecordID: CKRecord.ID)
}
