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
    
    // MARK: - Initialization
    
    public init(context: CloudKitDecoderContext) {
        self.context = context
    }
    
    // MARK: - Methods
    
    public func decode <T: CloudKitDecodable> (_ type: T.Type, from record: CKRecord) throws -> T {
        
        log?("Will decode \(String(reflecting: T.self))")
        
        let decoder = CKRecordDecoder(
            referencing: record,
            userInfo: userInfo,
            log: log,
            context: context
        )
        
        return try T.init(from: decoder)
    }
}

// MARK: - Supporting Types

/// CloudKit Decoder context.
public protocol CloudKitDecoderContext {
    
    func fetch(record: CKRecord.ID) -> CKRecord
}

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
    
    private(set) var stack: Stack
    
    // MARK: - Initialization
    
    fileprivate init(referencing container: CKRecord,
                     at codingPath: [CodingKey] = [],
                     userInfo: [CodingUserInfoKey : Any],
                     log: ((String) -> ())?,
                     context: CloudKitDecoderContext) {
        
        self.stack = Stack(.record(container))
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.log = log
        self.context = context
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
        
        fatalError()
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
            return identifierType.init(cloudRecordID: reference.recordID) as! T
        } else if let decodableType = type as? CloudKitDecodable.Type {
            // unbox reference as nested value
            guard let reference = value as? CKRecord.Reference else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Expected reference for \(String(reflecting: decodableType))"))
            }
            // get record for reference
            let record = context.fetch(record: reference.recordID)
            // decode nested type
            let decoder = CKRecordDecoder(
                referencing: record,
                at: codingPath,
                userInfo: userInfo,
                log: log,
                context: context
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
    
    // MARK: Initialization
    
    /// Initializes `self` by referencing the given decoder and container.
    init(referencing decoder: CKRecordDecoder, wrapping container: CKRecord) {
        
        self.decoder = decoder
        self.container = container
        self.codingPath = decoder.codingPath
        self.allKeys = container.allKeys().compactMap { Key(stringValue: $0) }
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
        return try decode(type, forKey: key)
    }
    
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        return try decode(type, forKey: key)
    }
    
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        return try decode(type, forKey: key)
    }
    
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        return try decode(type, forKey: key)
    }
    
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        return try decode(type, forKey: key)
    }
    
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        return try decode(type, forKey: key)
    }
    
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        return try decode(type, forKey: key)
    }
    
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        return try decode(type, forKey: key)
    }
    
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        return try decode(type, forKey: key)
    }
    
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        return try decode(type, forKey: key)
    }
    
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        return try decode(type, forKey: key)
    }
    
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        return try decode(type, forKey: key)
    }
    
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        return try decode(type, forKey: key)
    }
    
    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        return try decode(type, forKey: key)
    }
    
    func decode <T: Decodable> (_ type: T.Type, forKey key: Key) throws -> T {
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
    private func decode <T: CKRecordValueProtocol> (_ type: T.Type, forKey key: Key) throws -> T {
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
