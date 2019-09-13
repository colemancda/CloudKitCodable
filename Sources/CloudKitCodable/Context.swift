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

extension CKDatabase: CloudKitContext {
    
    public func fetch(record: CKRecord.ID) throws -> CKRecord? {
        
        // TODO: Use CKFetchRecordsOperation
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<CKRecord?, Error>!
        fetch(withRecordID: record) { (record, error) in
            defer { semaphore.signal() }
            if let error = error {
                result = .failure(error)
            } else {
                result = .success(record)
            }
        }
        semaphore.wait()
        guard let fetchResult = result
            else { fatalError() }
        switch fetchResult {
        case let .success(record):
            return record
        case let .failure(error):
            if let cloudKitError = error as? CKError,
                cloudKitError.code == .unknownItem {
                return nil
            } else {
                throw error
            }
        }
    }
}
