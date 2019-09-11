//
//  Encoder.swift
//  
//
//  Created by Alsey Coleman Miller on 9/10/19.
//

import Foundation
import CloudKit

/// CloudKit Record Recorder
public struct CloudKitEncoder {
    
    // MARK: - Properties
    
    /// Any contextual information set by the user for encoding.
    public var userInfo = [CodingUserInfoKey : Any]()
    
    /// Logger handler
    public var log: ((String) -> ())?
    
    // MARK: - Initialization
    
    public init() { }
    
    // MARK: - Methods
    
    public func encode <T: CloudKitEncodable> (_ value: T) throws {
        
        log?("Will encode \(String(reflecting: T.self))")
        
        //let options = Encoder.Options()
        let encoder = CKRecordEncoder(value, userInfo: userInfo, log: log)
        try value.encode(to: encoder)
    }
}

internal final class CKRecordEncoder <T: CloudKitEncodable> : Swift.Encoder {
    
    // MARK: - Properties
    
    /// The path of coding keys taken to get to this point in encoding.
    fileprivate(set) var codingPath: [CodingKey]
    
    /// Any contextual information set by the user for encoding.
    let userInfo: [CodingUserInfoKey : Any]
    
    /// Logger
    let log: ((String) -> ())?
    
    /// Encodable value
    let value: T
    
    /// Container stack
    private(set) var stack = Stack()
    
    // MARK: - Initialization
    
    init(_ value: T,
         codingPath: [CodingKey] = [],
         userInfo: [CodingUserInfoKey : Any],
         log: ((String) -> ())?) {
        
        self.value = value
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.log = log
    }
    
    // MARK: - Encoder
    
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        
        log?("Requested container keyed by \(type.sanitizedName) for path \"\(codingPath.path)\"")
        
        let record = CKRecord(recordType: T.cloudRecordType, recordID: value.cloudRecordID)
        self.stack.push(record)
        let keyedContainer = CKRecordKeyedEncodingContainer<T, Key>(referencing: self, wrapping: record)
        return KeyedEncodingContainer(keyedContainer)
    }
    
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        
        log?("Requested unkeyed container for path \"\(codingPath.path)\"")
        
        let stackContainer = ItemsContainer()
        self.stack.push(.items(stackContainer))
        return CloudKitUnkeyedEncodingContainer(referencing: self, wrapping: stackContainer)
    }
    
    func singleValueContainer() -> SingleValueEncodingContainer {
        
        log?("Requested single value container for path \"\(codingPath.path)\"")
        
        let stackContainer = ItemContainer()
        self.stack.push(.item(stackContainer))
        return CloudKitSingleValueEncodingContainer(referencing: self, wrapping: stackContainer)
    }
}

internal extension CKRecordEncoder {
    
    func boxEncodable <T: Encodable> (_ value: T) throws -> CKRecordValueProtocol {
        
        if let recordValue = value as? CKRecordValueProtocol {
            // return CloudKit native attribute value
            return recordValue
        } else {
            // encode using Encodable, should push new container.
            try value.encode(to: self)
            let record = stack.pop()
            let reference = CKRecord.Reference(record: record, action: .none)
            return reference
        }
    }
}

// MARK: - Stack

internal extension CKRecordEncoder {
    
    typealias Container = CKRecord
    
    struct Stack {
        
        private(set) var containers = [Container]()
        
        fileprivate init() { }
        
        var top: Container {
            guard let container = containers.last
                else { fatalError("Empty container stack.") }
            return container
        }
        
        var root: Container {
            guard let container = containers.first
                else { fatalError("Empty container stack.") }
            return container
        }
        
        mutating func push(_ container: Container) {
            containers.append(container)
        }
        
        @discardableResult
        mutating func pop() -> Container {
            guard let container = containers.popLast()
                else { fatalError("Empty container stack.") }
            return container
        }
    }
}

// MARK: - KeyedEncodingContainerProtocol

internal final class CKRecordKeyedEncodingContainer <T: CloudKitEncodable, K : CodingKey> : KeyedEncodingContainerProtocol {
    
    typealias Key = K
    
    // MARK: - Properties
    
    /// A reference to the encoder we're writing to.
    let encoder: CKRecordEncoder<T>
    
    /// The path of coding keys taken to get to this point in encoding.
    let codingPath: [CodingKey]
    
    /// A reference to the container we're writing to.
    let container: CKRecord
    
    // MARK: - Initialization
    
    init(referencing encoder: CKRecordEncoder<T>,
         wrapping container: CKRecord) {
        
        self.encoder = encoder
        self.codingPath = encoder.codingPath
        self.container = container
    }
    
    // MARK: - Methods
    
    func encodeNil(forKey key: K) throws {
        setValue(nil, forKey: key)
    }
    
    func encode(_ value: Bool, forKey key: K) throws {
        setValue(value as NSNumber, forKey: key)
    }
    
    func encode(_ value: Int, forKey key: K) throws {
        setValue(value as NSNumber, forKey: key)
    }
    
    func encode(_ value: Int8, forKey key: K) throws {
        setValue(value as NSNumber, forKey: key)
    }
    
    func encode(_ value: Int16, forKey key: K) throws {
        setValue(value as NSNumber, forKey: key)
    }
    
    func encode(_ value: Int32, forKey key: K) throws {
        setValue(value as NSNumber, forKey: key)
    }
    
    func encode(_ value: Int64, forKey key: K) throws {
        setValue(value as NSNumber, forKey: key)
    }
    
    func encode(_ value: UInt, forKey key: K) throws {
        setValue(value as NSNumber, forKey: key)
    }
    
    func encode(_ value: UInt8, forKey key: K) throws {
        setValue(value as NSNumber, forKey: key)
    }
    
    func encode(_ value: UInt16, forKey key: K) throws {
        setValue(value as NSNumber, forKey: key)
    }
    
    func encode(_ value: UInt32, forKey key: K) throws {
        setValue(value as NSNumber, forKey: key)
    }
    
    func encode(_ value: UInt64, forKey key: K) throws {
        setValue(value as NSNumber, forKey: key)
    }
    
    func encode(_ value: Float, forKey key: K) throws {
        setValue(value as NSNumber, forKey: key)
    }
    
    func encode(_ value: Double, forKey key: K) throws {
        setValue(value as NSNumber, forKey: key)
    }
    
    func encode(_ value: String, forKey key: K) throws {
        setValue(value, forKey: key)
    }
    
    func encode <T: Encodable> (_ value: T, forKey key: K) throws {
        try setValue(try encoder.boxEncodable(value), forKey: key)
    }
    
    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: K) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        fatalError()
    }
    
    func nestedUnkeyedContainer(forKey key: K) -> UnkeyedEncodingContainer {
        fatalError()
    }
    
    func superEncoder() -> Encoder {
        fatalError()
    }
    
    func superEncoder(forKey key: K) -> Encoder {
        fatalError()
    }
    
    // MARK: - Private Methods
    
    private func setValue(_ value: @autoclosure () throws -> (CKRecordValueProtocol?), forKey key: K) rethrows {
        self.encoder.codingPath.append(key)
        defer { self.encoder.codingPath.removeLast() }
        encoder.log?("Will encode value for key \(key.stringValue) at path \"\(encoder.codingPath.path)\"")
        let recordValue = try value()
        if #available(macOS 10.11, *) {
            self.container[key.stringValue] = recordValue
        } else {
            self.container.setObject(recordValue as? __CKRecordObjCValue, forKey: key.stringValue)
        }
    }
}
