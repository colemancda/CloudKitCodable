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
    
    public var options = Options()
    
    // MARK: - Initialization
    
    public init() { }
    
    // MARK: - Methods
    
    public func encode <T: CloudKitEncodable> (_ value: T) throws -> CKModifyRecordsOperation {
        
        log?("Will encode \(String(reflecting: T.self))")
        
        //let options = Encoder.Options()
        let operation = CKModifyRecordsOperation()
        let encoder = CKRecordEncoder(
            value,
            operation: operation,
            userInfo: userInfo,
            log: log,
            options: options
        )
        try value.encode(to: encoder)
        return operation
    }
}

public extension CloudKitEncoder {
    
    /// CloudKit Encoder Options
    typealias Options = CloudKitCodingOptions
}

// MARK: - Supporting Types

internal final class CKRecordEncoder: Swift.Encoder {
    
    // MARK: - Properties
    
    /// The path of coding keys taken to get to this point in encoding.
    fileprivate(set) var codingPath: [CodingKey]
    
    /// Any contextual information set by the user for encoding.
    let userInfo: [CodingUserInfoKey : Any]
    
    /// Logger
    let log: ((String) -> ())?
    
    let options: CloudKitEncoder.Options
    
    /// Encodable value
    let value: CloudKitEncodable
    
    /// CloudKit modify records operation.
    let operation: CKModifyRecordsOperation
    
    /// Container stack
    private(set) var stack = Stack()
    
    // MARK: - Initialization
    
    init(_ value: CloudKitEncodable,
         operation: CKModifyRecordsOperation,
         codingPath: [CodingKey] = [],
         userInfo: [CodingUserInfoKey : Any],
         log: ((String) -> ())?,
         options: CloudKitEncoder.Options) {
        
        self.value = value
        self.operation = operation
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.log = log
        self.options = options
    }
    
    // MARK: - Encoder
    
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        
        log?("Requested container keyed by \(type.sanitizedName) for path \"\(codingPath.path)\"")
        
        /// cannot encode
        guard stack.containers.isEmpty else {
            let keyedContainer = CKRecordInvalidKeyedEncodingContainer<Key>(codingPath: codingPath)
            return KeyedEncodingContainer(keyedContainer)
        }
        
        let record = CKRecord(
            recordType: Swift.type(of: value.cloudIdentifier).cloudRecordType,
            recordID: value.cloudIdentifier.cloudRecordID
        )
        operation.save(record)
        self.stack.push(.record(record))
        let keyedContainer = CKRecordKeyedEncodingContainer<Key>(referencing: self, wrapping: record)
        return KeyedEncodingContainer(keyedContainer)
    }
    
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        
        log?("Requested unkeyed container for path \"\(codingPath.path)\"")
        
        let stackContainer = ListContainer()
        self.stack.push(.list(stackContainer))
        return CKRecordUnkeyedEncodingContainer(referencing: self, wrapping: stackContainer)
    }
    
    func singleValueContainer() -> SingleValueEncodingContainer {
        
        log?("Requested single value container for path \"\(codingPath.path)\"")
        
        let stackContainer = ValueContainer()
        self.stack.push(.value(stackContainer))
        return CKRecordSingleValueEncodingContainer(referencing: self, wrapping: stackContainer)
    }
}

// MARK: - Boxing Values

internal extension CKRecordEncoder {
    
    func boxEncodable <T: Encodable> (_ value: T) throws -> CKRecordValueProtocol? {
        
        if let url = value as? URL {
            // attempt to convert to CKAsset
            return options.assets(url) ?? url.absoluteString
        } else if let uuid = value as? UUID {
            return uuid.uuidString
        } else if let locationValue = value as? CloudKitLocation {
            // encode CLLocation
            return locationValue.location
        } else if let identifier = value as? CloudKitIdentifier {
            // store nested reference
            return boxIdentifier(identifier)
        } else if let encodable = value as? CloudKitEncodable {
            // store nested record
            let encoder = CKRecordEncoder(
                encodable,
                operation: operation,
                codingPath: codingPath,
                userInfo: userInfo,
                log: log,
                options: options
            )
            try encodable.encode(to: encoder)
            guard case let .record(record) = encoder.stack.root else {
                throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "\(String(reflecting: Swift.type(of: encodable))) should encode to record"))
            }
            return boxRecord(record)
        } else if let recordValue = value as? CKRecordValueProtocol {
            // return CloudKit native attribute value
            return recordValue
        } else {
            // encode using Encodable, should push new container.
            try value.encode(to: self)
            let container = stack.pop()
            switch container {
            case let .record(record):
                return boxRecord(record)
            case let .value(valueContainer):
                return valueContainer.value
            case let .list(listContainer):
                return listContainer.value
            }
        }
    }
    
    private func boxRecord(_ record: CKRecord) -> CKRecord.Reference {
        let reference = CKRecord.Reference(record: record, action: .none)
        return reference
    }
    
    private func boxIdentifier(_ identifier: CloudKitIdentifier) -> CKRecord.Reference {
        let reference = CKRecord.Reference(recordID: identifier.cloudRecordID, action: .none)
        return reference
    }
}

// MARK: - Stack

internal extension CKRecordEncoder {
        
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

internal extension CKRecordEncoder {
    
    enum Container {
        case record(CKRecord)
        case value(ValueContainer)
        case list(ListContainer)
    }
    
    final class ValueContainer {
        var value: CKRecordValueProtocol?
    }
    
    final class ListContainer {
        // should be homegenous array
        var value = NSMutableArray()
    }
}

// MARK: - KeyedEncodingContainerProtocol

internal struct CKRecordInvalidKeyedEncodingContainer <K : CodingKey> : KeyedEncodingContainerProtocol {
    
    let codingPath: [CodingKey]
    
    typealias Key = K
    
    func encodeNil(forKey key: K) throws { try error() }
    func encode(_ value: Bool, forKey key: K) throws { try error() }
    func encode(_ value: Int, forKey key: K) throws { try error() }
    func encode(_ value: Int8, forKey key: K) throws { try error() }
    func encode(_ value: Int16, forKey key: K) throws { try error() }
    func encode(_ value: Int32, forKey key: K) throws { try error() }
    func encode(_ value: Int64, forKey key: K) throws { try error() }
    func encode(_ value: UInt, forKey key: K) throws { try error() }
    func encode(_ value: UInt8, forKey key: K) throws { try error() }
    func encode(_ value: UInt16, forKey key: K) throws { try error() }
    func encode(_ value: UInt32, forKey key: K) throws { try error() }
    func encode(_ value: UInt64, forKey key: K) throws { try error() }
    func encode(_ value: Float, forKey key: K) throws { try error() }
    func encode(_ value: Double, forKey key: K) throws { try error() }
    func encode(_ value: String, forKey key: K) throws { try error() }
    func encode <T: Encodable> (_ value: T, forKey key: K) throws { try error() }
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
    private func error() throws {
        throw EncodingError.invalidValue(CloudKitEncodable.self, EncodingError.Context(codingPath: codingPath, debugDescription: "Nested value should conform to \(CloudKitEncodable.self)"))
    }
}

internal final class CKRecordKeyedEncodingContainer <K : CodingKey> : KeyedEncodingContainerProtocol {
    
    typealias Key = K
    
    // MARK: - Properties
    
    /// A reference to the encoder we're writing to.
    let encoder: CKRecordEncoder
    
    /// The path of coding keys taken to get to this point in encoding.
    let codingPath: [CodingKey]
    
    /// A reference to the container we're writing to.
    let container: CKRecord
    
    // MARK: - Initialization
    
    init(referencing encoder: CKRecordEncoder,
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
        setValue(value, forKey: key)
    }
    
    func encode(_ value: Int, forKey key: K) throws {
        setValue(value, forKey: key)
    }
    
    func encode(_ value: Int8, forKey key: K) throws {
        setValue(value, forKey: key)
    }
    
    func encode(_ value: Int16, forKey key: K) throws {
        setValue(value, forKey: key)
    }
    
    func encode(_ value: Int32, forKey key: K) throws {
        setValue(value, forKey: key)
    }
    
    func encode(_ value: Int64, forKey key: K) throws {
        setValue(value, forKey: key)
    }
    
    func encode(_ value: UInt, forKey key: K) throws {
        setValue(value, forKey: key)
    }
    
    func encode(_ value: UInt8, forKey key: K) throws {
        setValue(value, forKey: key)
    }
    
    func encode(_ value: UInt16, forKey key: K) throws {
        setValue(value, forKey: key)
    }
    
    func encode(_ value: UInt32, forKey key: K) throws {
        setValue(value, forKey: key)
    }
    
    func encode(_ value: UInt64, forKey key: K) throws {
        setValue(value, forKey: key)
    }
    
    func encode(_ value: Float, forKey key: K) throws {
        setValue(value, forKey: key)
    }
    
    func encode(_ value: Double, forKey key: K) throws {
        setValue(value, forKey: key)
    }
    
    func encode(_ value: String, forKey key: K) throws {
        setValue(value, forKey: key)
    }
    
    func encode <T: Encodable> (_ value: T, forKey key: K) throws {
         // don't encode identifier
        guard encoder.options.identifierKey(key) == false else {
            self.encoder.codingPath.append(key)
            defer { self.encoder.codingPath.removeLast() }
            let recordID = encoder.value.cloudIdentifier.cloudRecordID
            encoder.log?("Will encode record ID \"\(recordID.recordName)\" for key \"\(key.stringValue)\" at path \"\(encoder.codingPath.path)\"")
            // do nothing
            
            return
        }
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
        encoder.log?("Will encode value for key \"\(key.stringValue)\" at path \"\(encoder.codingPath.path)\"")
        let recordValue = try value()
        if #available(macOS 10.11, iOS 9.0, watchOS 3.0, *) {
            self.container[key.stringValue] = recordValue
        } else {
            guard let objcValue = (recordValue as Any?) as? __CKRecordObjCValue? else {
                fatalError("Cannot convert \(String(reflecting: type(of: recordValue))) to ObjC value")
            }
            self.container.setObject(objcValue, forKey: key.stringValue)
        }
    }
}

// MARK: - SingleValueEncodingContainer

internal final class CKRecordSingleValueEncodingContainer: SingleValueEncodingContainer {
    
    // MARK: - Properties
    
    /// A reference to the encoder we're writing to.
    let encoder: CKRecordEncoder
    
    /// The path of coding keys taken to get to this point in encoding.
    let codingPath: [CodingKey]
    
    /// A reference to the container we're writing to.
    let container: CKRecordEncoder.ValueContainer
    
    /// Whether the data has been written
    private(set) var didWrite = false
    
    // MARK: - Initialization
    
    init(referencing encoder: CKRecordEncoder,
         wrapping container: CKRecordEncoder.ValueContainer) {
        
        self.encoder = encoder
        self.codingPath = encoder.codingPath
        self.container = container
    }
    
    // MARK: - Methods
    
    func encodeNil() throws { write(nil) }
    
    func encode(_ value: Bool) throws { write(value) }
    
    func encode(_ value: String) throws { write(value) }
    
    func encode(_ value: Double) throws { write(value) }
    
    func encode(_ value: Float) throws { write(value) }
    
    func encode(_ value: Int) throws { write(value) }
    
    func encode(_ value: Int8) throws { write(value) }
    
    func encode(_ value: Int16) throws { write(value) }
    
    func encode(_ value: Int32) throws { write(value) }
    
    func encode(_ value: Int64) throws { write(value) }
    
    func encode(_ value: UInt) throws { write(value) }
    
    func encode(_ value: UInt8) throws { write(value) }
    
    func encode(_ value: UInt16) throws { write(value) }
    
    func encode(_ value: UInt32) throws { write(value) }
    
    func encode(_ value: UInt64) throws { write(value) }
    
    func encode <T: Encodable> (_ value: T) throws { write(try encoder.boxEncodable(value)) }
    
    // MARK: - Private Methods
    
    private func write(_ value: CKRecordValueProtocol?) {
        precondition(didWrite == false, "Data already written")
        self.container.value = value
        self.didWrite = true
    }
}

// MARK: - UnkeyedEncodingContainer

internal final class CKRecordUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    
    // MARK: - Properties
    
    /// A reference to the encoder we're writing to.
    let encoder: CKRecordEncoder
    
    /// The path of coding keys taken to get to this point in encoding.
    let codingPath: [CodingKey]
    
    /// A reference to the container we're writing to.
    let container: CKRecordEncoder.ListContainer
    
    // MARK: - Initialization
    
    init(referencing encoder: CKRecordEncoder,
         wrapping container: CKRecordEncoder.ListContainer) {
        
        self.encoder = encoder
        self.codingPath = encoder.codingPath
        self.container = container
    }
    
    // MARK: - Methods
    
    /// The number of elements encoded into the container.
    var count: Int {
        return container.value.count
    }
    
    func encodeNil() throws { append(nil) }
    
    func encode(_ value: Bool) throws { append(value) }
    
    func encode(_ value: String) throws { append(value) }
    
    func encode(_ value: Double) throws { append(value) }
    
    func encode(_ value: Float) throws { append(value) }
    
    func encode(_ value: Int) throws { append(value) }
    
    func encode(_ value: Int8) throws { append(value) }
    
    func encode(_ value: Int16) throws { append(value) }
    
    func encode(_ value: Int32) throws { append(value) }
    
    func encode(_ value: Int64) throws { append(value) }
    
    func encode(_ value: UInt) throws { append(value) }
    
    func encode(_ value: UInt8) throws { append(value) }
    
    func encode(_ value: UInt16) throws { append(value) }
    
    func encode(_ value: UInt32) throws { append(value) }
    
    func encode(_ value: UInt64) throws { append(value) }
    
    func encode <T: Encodable> (_ value: T) throws { append(try encoder.boxEncodable(value)) }
    
    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        fatalError()
    }
    
    func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        fatalError()
    }
    
    func superEncoder() -> Encoder {
        fatalError()
    }
    
    // MARK: - Private Methods
    
    private func append(_ value: CKRecordValueProtocol?) {
        if let value = value {
            self.container.value.add(value)
        }
    }
}

// MARK: - Extensions

internal extension CKModifyRecordsOperation {
    
    func save(_ record: CKRecord) {
        var recordsToSave = self.recordsToSave ?? []
        recordsToSave.removeAll(where: { $0 === record })
        recordsToSave.append(record)
        self.recordsToSave = recordsToSave
    }
}
