//
//  File.swift
//  
//
//  Created by Alsey Coleman Miller on 9/10/19.
//

import Foundation
import CloudKit

/// CloudKit Record Decoder
public struct CloudKitDecoder {
    
    // MARK: - Properties
    
    /// CloudKit Decoder context.
    public let context: CloudKitDecoderContext
    
    /// Any contextual information set by the user for encoding.
    public var userInfo = [CodingUserInfoKey : Any]()
    
    /// Logger handler
    public var log: ((String) -> ())?
    
    /// CloudKit Decoding Options
    public var options = Options()
    
    // MARK: - Initialization
    
    public init(context: CloudKitDecoderContext) {
        self.context = context
    }
    
    // MARK: - Methods
    
    public func decode <T: CloudKitDecodable> (_ type: T.Type, from record: CKRecord) throws -> T {
        
        log?("Will decode \(String(reflecting: T.self))")
        
        let decoder = CKRecordDecoder(
            referencing: .record(record),
            userInfo: userInfo,
            log: log,
            context: context,
            options: options
        )
        
        return try T.init(from: decoder)
    }
}

// MARK: - Supporting Types

public extension CloudKitDecoder {
    
    /// CloudKit Decoder Options
    struct Options {
        
        /// Which coding key to use as the CloudKit record name.
        public var identifierKey: IdentifierKeyStrategy = { (key) in key.stringValue == "id" }
    }
}

public extension CloudKitDecoder.Options {
    
    typealias IdentifierKeyStrategy = (CodingKey) -> (Bool)
}

/// CloudKit Decoder context.
public protocol CloudKitDecoderContext {
    
    func fetch(record: CKRecord.ID) throws -> CKRecord
}

extension CKDatabase: CloudKitDecoderContext {
    
    public func fetch(record: CKRecord.ID) throws -> CKRecord {
        
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<CKRecord, Error>!
        fetch(withRecordID: record) { (record, error) in
            defer { semaphore.signal() }
            if let error = error {
                result = .failure(error)
            } else if let record = record {
                result = .success(record)
            } else {
                assertionFailure()
            }
        }
        semaphore.wait()
        guard let fetchResult = result
            else { fatalError() }
        switch fetchResult {
        case let .success(record):
            return record
        case let .failure(error):
            throw error
        }
    }
}

// MARK: - Decoder

internal final class CKRecordDecoder: Swift.Decoder {
    
    // MARK: - Properties
    
    /// CloudKit Decoder context.
    public let context: CloudKitDecoderContext
    
    /// The path of coding keys taken to get to this point in decoding.
    fileprivate(set) var codingPath: [CodingKey]
    
    /// Any contextual information set by the user for decoding.
    let userInfo: [CodingUserInfoKey : Any]
        
    /// Logger
    let log: ((String) -> ())?
    
    let options: CloudKitDecoder.Options
    
    private(set) var stack: Stack
    
    // MARK: - Initialization
    
    fileprivate init(referencing container: Container,
                     at codingPath: [CodingKey] = [],
                     userInfo: [CodingUserInfoKey : Any],
                     log: ((String) -> ())?,
                     context: CloudKitDecoderContext,
                     options: CloudKitDecoder.Options) {
        
        self.stack = Stack(container)
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.log = log
        self.context = context
        self.options = options
    }
    
    // MARK: - Methods
        
    func container <Key: CodingKey> (keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        
        log?("Requested container keyed by \(type.sanitizedName) for path \"\(codingPath.path)\"")
        
        let container = self.stack.top
        guard case let .record(record) = container else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Cannot get keyed decoding container, invalid top container \(container)."))
        }
        let keyedContainer = CKRecordKeyedDecodingContainer<Key>(referencing: self, wrapping: record)
        return KeyedDecodingContainer(keyedContainer)
    }
    
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        
        log?("Requested unkeyed container for path \"\(codingPath.path)\"")
        
        let container = self.stack.top
        guard case let .value(value) = container else {
            throw DecodingError.typeMismatch(UnkeyedDecodingContainer.self, DecodingError.Context(codingPath: self.codingPath, debugDescription: "Cannot get unkeyed decoding container, invalid top container \(container)."))
        }
        guard let list = value as? [CKRecordValueProtocol] else {
            throw DecodingError.typeMismatch(UnkeyedDecodingContainer.self, DecodingError.Context(codingPath: self.codingPath, debugDescription: "Cannot get unkeyed value decoding container, invalid top container \(container)."))
        }
        return CKRecordUnkeyedDecodingContainer(referencing: self, wrapping: list)
    }
    
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        
        log?("Requested single value container for path \"\(codingPath.path)\"")
        
        let container = self.stack.top
        guard case let .value(value) = container else {
            throw DecodingError.typeMismatch(SingleValueDecodingContainer.self, DecodingError.Context(codingPath: self.codingPath, debugDescription: "Cannot get single value decoding container, invalid top container \(container)."))
        }
        return CKRecordSingleValueDecodingContainer(referencing: self, wrapping: value)
    }
}

// MARK: - Unboxing Values

internal extension CKRecordDecoder {
    
    func unbox <T: CKRecordValueProtocol> (_ recordValue: CKRecordValueProtocol, as type: T.Type) throws -> T {
        var recordValue = recordValue
        if let number = recordValue as? NSNumber {
            recordValue = number
        }
        guard let value = recordValue as? T else {
            throw DecodingError.typeMismatch(type, DecodingError.Context(codingPath: self.codingPath, debugDescription: "Could not parse \(type) from \(recordValue)"))
        }
        return value
    }
    
    /// Attempt to decode native value to expected type.
    func unboxDecodable <T: Decodable> (_ value: CKRecordValueProtocol, as type: T.Type) throws -> T {
        
        if let identifierType = type as? CloudKitIdentifier.Type {
            // unbox reference as identifier
            guard let reference = value as? CKRecord.Reference else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Expected reference for \(String(reflecting: type))"))
            }
            guard let identifier = identifierType.init(cloudRecordID: reference.recordID) else {
                throw DecodingError.typeMismatch(type, DecodingError.Context(codingPath: self.codingPath, debugDescription: "Could not initialize identifier \(identifierType) from \(reference)"))
            }
            return identifier as! T
        } else if let decodableType = type as? CloudKitDecodable.Type {
            // unbox reference as nested value
            guard let reference = value as? CKRecord.Reference else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Expected reference for \(String(reflecting: decodableType))"))
            }
            // get record for reference
            let record = try context.fetch(record: reference.recordID)
            // decode nested type
            let decoder = CKRecordDecoder(
                referencing: .record(record),
                at: codingPath,
                userInfo: userInfo,
                log: log,
                context: context,
                options: options
            )
            return try T.init(from: decoder)
        } else {
            // push container to stack and decode using Decodable implementation
            stack.push(.value(value))
            let decoded = try T.init(from: self)
            stack.pop()
            return decoded
        }
    }
}

// MARK: - Stack

internal extension CKRecordDecoder {
    
    struct Stack {
        
        private(set) var containers = [Container]()
        
        fileprivate init(_ container: Container) {
            self.containers = [container]
        }
        
        var top: Container {
            guard let container = containers.last
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
    
    enum Container {
        case record(CKRecord)
        case value(CKRecordValueProtocol?)
    }
}

// MARK: - KeyedDecodingContainer

internal struct CKRecordKeyedDecodingContainer <K: CodingKey> : KeyedDecodingContainerProtocol {
    
    typealias Key = K
    
    // MARK: Properties
    
    /// A reference to the encoder we're reading from.
    let decoder: CKRecordDecoder
    
    /// A reference to the container we're reading from.
    let container: CKRecord
    
    /// The path of coding keys taken to get to this point in decoding.
    let codingPath: [CodingKey]
    
    /// All the keys the Decoder has for this container.
    let allKeys: [Key]
    
    /// CloudKit Identifier Key
    let identifierKey: K?
    
    // MARK: Initialization
    
    /// Initializes `self` by referencing the given decoder and container.
    init(referencing decoder: CKRecordDecoder, wrapping container: CKRecord) {
        
        self.decoder = decoder
        self.container = container
        self.codingPath = decoder.codingPath
        let allKeys = container.allKeys().compactMap { Key(stringValue: $0) }
        self.allKeys = allKeys
        self.identifierKey = allKeys.first(where: { decoder.options.identifierKey($0) })
    }
    
    // MARK: KeyedDecodingContainerProtocol
    
    func contains(_ key: Key) -> Bool {
        self.decoder.log?("Check whether key \"\(key.stringValue)\" exists")
        return allKeys.contains(where: { $0.stringValue == key.stringValue })
    }
    
    func decodeNil(forKey key: Key) throws -> Bool {
        return self.value(for: key) == nil
    }
    
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        return try decodeRecordValue(type, forKey: key)
    }
    
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        return try decodeRecordValue(type, forKey: key)
    }
    
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        return try decodeRecordValue(type, forKey: key)
    }
    
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        return try decodeRecordValue(type, forKey: key)
    }
    
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        return try decodeRecordValue(type, forKey: key)
    }
    
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        return try decodeRecordValue(type, forKey: key)
    }
    
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        return try decodeRecordValue(type, forKey: key)
    }
    
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        return try decodeRecordValue(type, forKey: key)
    }
    
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        return try decodeRecordValue(type, forKey: key)
    }
    
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        return try decodeRecordValue(type, forKey: key)
    }
    
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        return try decodeRecordValue(type, forKey: key)
    }
    
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        return try decodeRecordValue(type, forKey: key)
    }
    
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        return try decodeRecordValue(type, forKey: key)
    }
    
    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        return try decodeRecordValue(type, forKey: key)
    }
    
    func decode <T: Decodable> (_ type: T.Type, forKey key: Key) throws -> T {
        
        // override identifier key
        if let identifierKey = self.identifierKey?.stringValue {
            guard key.stringValue != identifierKey else {
                decoder.codingPath.append(key)
                defer { decoder.codingPath.removeLast() }
                decoder.log?("Will read record ID at path \"\(decoder.codingPath.path)\"")
                guard let identifierType = type as? CloudKitIdentifier.Type else {
                    throw DecodingError.typeMismatch(type, DecodingError.Context(codingPath: self.codingPath, debugDescription: "Should decode identifier for \(identifierKey)"))
                }
                guard let identifier = identifierType.init(cloudRecordID: container.recordID) else {
                    throw DecodingError.typeMismatch(type, DecodingError.Context(codingPath: self.codingPath, debugDescription: "Could not initialize identifier \(identifierType) from \(container.recordID)"))
                }
                return identifier as! T
            }
        }
        
        return try self.value(for: key, type: type) { try decoder.unboxDecodable($0, as: type) }
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        fatalError()
    }
    
    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        fatalError()
    }
    
    func superDecoder() throws -> Decoder {
        fatalError()
    }
    
    func superDecoder(forKey key: Key) throws -> Decoder {
        fatalError()
    }
    
    // MARK: Private Methods
    
    /// Decode native value type from CloudKit value.
    private func decodeRecordValue <T: CKRecordValueProtocol> (_ type: T.Type, forKey key: Key) throws -> T {
        return try self.value(for: key, type: type) { try decoder.unbox($0, as: type) }
    }
    
    /// Access actual value
    private func value <T> (for key: Key, type: T.Type, decode: (CKRecordValueProtocol) throws -> T) throws -> T {
        
        guard let value = self.value(for: key) else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
        }
        return try decode(value)
    }
    
    /// Access actual value
    private func value(for key: Key) -> CKRecordValueProtocol? {
        
        decoder.codingPath.append(key)
        defer { decoder.codingPath.removeLast() }
        decoder.log?("Will read value at path \"\(decoder.codingPath.path)\"")
        if #available(macOS 10.11, iOS 9.0, watchOS 3.0, *) {
            return container[key.stringValue]
        } else {
            return container.object(forKey: key.stringValue) as! CKRecordValueProtocol?
        }
    }
}

// MARK: - SingleValueDecodingContainer

internal struct CKRecordSingleValueDecodingContainer: SingleValueDecodingContainer {
    
    // MARK: Properties
    
    /// A reference to the decoder we're reading from.
    let decoder: CKRecordDecoder
    
    /// A reference to the container we're reading from.
    let container: CKRecordValueProtocol?
    
    /// The path of coding keys taken to get to this point in decoding.
    let codingPath: [CodingKey]
    
    // MARK: Initialization
    
    /// Initializes `self` by referencing the given decoder and container.
    init(referencing decoder: CKRecordDecoder, wrapping container: CKRecordValueProtocol?) {
        
        self.decoder = decoder
        self.container = container
        self.codingPath = decoder.codingPath
    }
    
    // MARK: SingleValueDecodingContainer
    
    func decodeNil() -> Bool {
        return container == nil
    }
    
    func decode(_ type: Bool.Type) throws -> Bool {
        return try self.decoder.unbox(try value(type), as: type)
    }
    
    func decode(_ type: Int.Type) throws -> Int {
        return try self.decoder.unbox(try value(type), as: type)
    }
    
    func decode(_ type: Int8.Type) throws -> Int8 {
        return try self.decoder.unbox(try value(type), as: type)
    }
    
    func decode(_ type: Int16.Type) throws -> Int16 {
        return try self.decoder.unbox(try value(type), as: type)
    }
    
    func decode(_ type: Int32.Type) throws -> Int32 {
        return try self.decoder.unbox(try value(type), as: type)
    }
    
    func decode(_ type: Int64.Type) throws -> Int64 {
        return try self.decoder.unbox(try value(type), as: type)
    }
    
    func decode(_ type: UInt.Type) throws -> UInt {
        return try self.decoder.unbox(try value(type), as: type)
    }
    
    func decode(_ type: UInt8.Type) throws -> UInt8 {
        return try self.decoder.unbox(try value(type), as: type)
    }
    
    func decode(_ type: UInt16.Type) throws -> UInt16 {
        return try self.decoder.unbox(try value(type), as: type)
    }
    
    func decode(_ type: UInt32.Type) throws -> UInt32 {
        return try self.decoder.unbox(try value(type), as: type)
    }
    
    func decode(_ type: UInt64.Type) throws -> UInt64 {
        return try self.decoder.unbox(try value(type), as: type)
    }
    
    func decode(_ type: Float.Type) throws -> Float {
        return try self.decoder.unbox(try value(type), as: type)
    }
    
    func decode(_ type: Double.Type) throws -> Double {
        return try self.decoder.unbox(try value(type), as: type)
    }
    
    func decode(_ type: String.Type) throws -> String {
        return try self.decoder.unbox(try value(type), as: type)
    }
    
    func decode <T : Decodable> (_ type: T.Type) throws -> T {
        return try self.decoder.unboxDecodable(try value(type), as: type)
    }
    
    // MARK: - Private Methods
    
    private func value<T>(_ type: T.Type) throws -> CKRecordValueProtocol {
        guard let value = container else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
        }
        return value
    }
}

// MARK: UnkeyedDecodingContainer

internal struct CKRecordUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    
    // MARK: Properties
    
    /// A reference to the encoder we're reading from.
    let decoder: CKRecordDecoder
    
    /// A reference to the container we're reading from.
    let container: [CKRecordValueProtocol]
    
    /// The path of coding keys taken to get to this point in decoding.
    let codingPath: [CodingKey]
    
    private(set) var currentIndex: Int = 0
    
    // MARK: Initialization
    
    /// Initializes `self` by referencing the given decoder and container.
    init(referencing decoder: CKRecordDecoder, wrapping container: [CKRecordValueProtocol]) {
        
        self.decoder = decoder
        self.container = container
        self.codingPath = decoder.codingPath
    }
    
    // MARK: UnkeyedDecodingContainer
    
    var count: Int? {
        return _count
    }
    
    private var _count: Int {
        return container.count
    }
    
    var isAtEnd: Bool {
        return currentIndex >= _count
    }
    
    mutating func decodeNil() throws -> Bool {
        
        try assertNotEnd()
        
        // never optional, decode
        return false
    }
    
    mutating func decode(_ type: Bool.Type) throws -> Bool { fatalError("stub") }
    mutating func decode(_ type: Int.Type) throws -> Int { fatalError("stub") }
    mutating func decode(_ type: Int8.Type) throws -> Int8 { fatalError("stub") }
    mutating func decode(_ type: Int16.Type) throws -> Int16 { fatalError("stub") }
    mutating func decode(_ type: Int32.Type) throws -> Int32 { fatalError("stub") }
    mutating func decode(_ type: Int64.Type) throws -> Int64 { fatalError("stub") }
    mutating func decode(_ type: UInt.Type) throws -> UInt { fatalError("stub") }
    mutating func decode(_ type: UInt8.Type) throws -> UInt8 { fatalError("stub") }
    mutating func decode(_ type: UInt16.Type) throws -> UInt16 { fatalError("stub") }
    mutating func decode(_ type: UInt32.Type) throws -> UInt32 { fatalError("stub") }
    mutating func decode(_ type: UInt64.Type) throws -> UInt64 { fatalError("stub") }
    mutating func decode(_ type: Float.Type) throws -> Float { fatalError("stub") }
    mutating func decode(_ type: Double.Type) throws -> Double { fatalError("stub") }
    mutating func decode(_ type: String.Type) throws -> String { fatalError("stub") }
    
    mutating func decode <T : Decodable> (_ type: T.Type) throws -> T {
        
        try assertNotEnd()
        
        self.decoder.codingPath.append(Index(intValue: self.currentIndex))
        defer { self.decoder.codingPath.removeLast() }
        
        let item = self.container[self.currentIndex]
        
        let decoded = try self.decoder.unboxDecodable(item, as: type)
        
        self.currentIndex += 1
        
        return decoded
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        throw DecodingError.typeMismatch(type, DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot decode \(type)"))
    }
    
    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        throw DecodingError.typeMismatch([Any].self, DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot decode unkeyed container."))
    }
    
    mutating func superDecoder() throws -> Decoder {
        
        // set coding key context
        self.decoder.codingPath.append(Index(intValue: currentIndex))
        defer { self.decoder.codingPath.removeLast() }
        
        // log
        self.decoder.log?("Requested super decoder for path \"\(self.decoder.codingPath.path)\"")
        
        // check for end of array
        try assertNotEnd()
        
        // get value
        let value = container[currentIndex]
        
        // increment counter
        self.currentIndex += 1
        
        // create new decoder
        let decoder = CKRecordDecoder(referencing: .value(value),
                                      at: self.decoder.codingPath,
                                      userInfo: self.decoder.userInfo,
                                      log: self.decoder.log,
                                      context: self.decoder.context,
                                      options: self.decoder.options)
        
        return decoder
    }
    
    // MARK: Private Methods
    
    @inline(__always)
    private func assertNotEnd() throws {
        guard isAtEnd == false else {
            throw DecodingError.valueNotFound(Any?.self, DecodingError.Context(codingPath: self.decoder.codingPath + [Index(intValue: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }
    }
}

internal extension CKRecordUnkeyedDecodingContainer {
    
    struct Index: CodingKey {
        
        let index: Int
        
        init(intValue: Int) {
            self.index = intValue
        }
        
        init?(stringValue: String) {
            return nil
        }
        
        var intValue: Int? {
            return index
        }
        
        var stringValue: String {
            return "\(index)"
        }
    }
}
