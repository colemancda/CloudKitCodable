import Foundation
import CloudKit
import CoreLocation
import XCTest
@testable import CloudKitCodable

final class CloudKitCodableTests: XCTestCase {
    
    static let allTests = [
        ("testCodable", testCodable),
        ("testInvalid", testInvalid),
        ("testDecodeEmptyList", testDecodeEmptyList)
    ]
    
    func testCodable() {
        
        func test <T: CloudKitCodable & Equatable> (_ value: T) {
            
            print("Test \(String(reflecting: T.self))")
                        
            let encoder = CloudKitEncoder(context: CloudKitTestContext(records: []))
            encoder.log = { print("Encoder:", $0) }
            var operation: CKModifyRecordsOperation!
            do {
                operation = try encoder.encode(value)
                XCTAssertEqual(operation.recordsToSave?.first?.recordID, value.cloudIdentifier.cloudRecordID)
                let recordIDs = operation.recordsToSave?.map { $0.recordID.recordName } ?? []
                XCTAssertEqual(recordIDs.count, Set(recordIDs).count, "No duplicate records")
            } catch {
                dump(error)
                XCTFail("Could not encode \(value)")
                return
            }
            
            guard let record = operation.recordsToSave?.first else {
                XCTFail("Did not save any records")
                return
            }
            
            let decoder = CloudKitDecoder(context: CloudKitTestContext(records: operation.recordsToSave ?? []))
            decoder.log = { print("Decoder:", $0) }
            do {
                let decodedValue = try decoder.decode(T.self, from: record)
                XCTAssertEqual(decodedValue, value)
            } catch {
                dump(error)
                XCTFail("Could not decode \(value)")
                return
            }
            
            let jsonEncoder = JSONEncoder()
            var jsonData = Data()
            do { jsonData = try jsonEncoder.encode(value) }
            catch {
                dump(error)
                XCTFail("Could not decode \(value)")
                return
            }
            let jsonDecoder = JSONDecoder()
            do {
                let jsonDecodedValue = try jsonDecoder.decode(T.self, from: jsonData)
                XCTAssertEqual(jsonDecodedValue, value)
            } catch {
                dump(error)
                XCTFail("Could not decode \(value)")
                return
            }
        }
        
        test(Person(id: "001", gender: .male, name: "Coleman"))
        test(Person(id: "0", gender: .male, name: ""))
        test(AttributesTest(
             id: .init(),
             boolean: true,
             int: -10,
             uint: 10,
             float: 1.1234,
             double: 10.9999,
             int8: .max,
             int16: -200,
             int32: -2000,
             int64: -20_000,
             uint8: .max,
             uint16: 300,
             uint32: 3000,
             uint64: 30_000,
             string: "test string",
             date: Date(),
             data: Data([0x01]),
             url: URL(string: "https://apple.com")!,
             uuid: UUID(),
             location: .init(latitude: 1.123, longitude: -1.123),
             asset: URL(fileURLWithPath: "/tmp/data.json")
            )
        )
        test(Profile(
                id: .init(),
                person: Person(
                    id: "001",
                    gender: .male,
                    name: "Coleman"
                ), friends: [
                    Person(
                        id: "002",
                        gender: .male,
                        name: "Jorge"
                    )
                ],
                favorites: [],
                userInfo: nil
            ))
        
        test(
            Profile(
                id: .init(),
                person: Person(
                    id: "001",
                    gender: .male,
                    name: "Coleman"
                ),
                friends: [
                    Person(
                        id: "002",
                        gender: .female,
                        name: "Gina"
                    ),
                    Person(
                        id: "003",
                        gender: .female,
                        name: "Jossy"
                    ),
                    Person(
                        id: "004",
                        gender: .male,
                        name: "Jorge"
                    )
                ],
                favorites: ["002"],
                userInfo: nil
            )
        )
        
        test(
            PrimitiveArray(
                id: .init(),
                strings: ["1", "two", "three", ""],
                integers: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
            )
        )
        
        test(
            DeviceInformation(
                id: .init(rawValue: UUID(uuidString: "B83DD6F4-A429-41B3-945A-3E0EE5915CA1")!),
                buildVersion: DeviceInformation.BuildVersion(rawValue: 1),
                version: Version(major: 1, minor: 2, patch: 3),
                status: .provisioned,
                features: .all
            )
        )
        
        test(
            CryptoRequest(secret: CryptoData())
        )
        
        test(
            ReferencesTest(
                id: .init(),
                reference: .init(),
                references: [.init()],
                nestedValue: Person(
                    id: "001",
                    gender: .male,
                    name: "Coleman"
                ),
                nestedList: [
                    Person(
                        id: "002",
                        gender: .female,
                        name: "Gina"
                    ),
                    Person(
                        id: "003",
                        gender: .male,
                        name: "Jorge"
                    )
                ],
                nestedNonCloud: nil,
                nestedNonCloudList: []
            )
        )
    }
    
    func testInvalid() {
        
        let encoder = CloudKitEncoder(context: CloudKitTestContext(records: []))
        encoder.log = { print("Encoder:", $0) }
        
        do {
            let value = ReferencesTest(
                id: .init(),
                reference: nil,
                references: [],
                nestedValue: nil,
                nestedList: [],
                nestedNonCloud: .init(
                    name: "Non Cloud Nested",
                    value: Data([0x01, 0x02]),
                    url: URL(string: "http://google.com")!
                ),
                nestedNonCloudList: []
            )
            let _ = try encoder.encode(value)
            XCTFail("Should throw error")
        } catch {
            dump(error)
        }
        
        do {
            let value = ReferencesTest(
                id: .init(),
                reference: nil,
                references: [],
                nestedValue: nil,
                nestedList: [],
                nestedNonCloud: nil,
                nestedNonCloudList: [
                    .init(
                        name: "Non Cloud Nested 1",
                        value: Data([0x01, 0x02, 0x02]),
                        url: URL(string: "http://google.com/index.html")!
                    ),
                ]
            )
            let _ = try encoder.encode(value)
            XCTFail("Should throw error")
        } catch {
            dump(error)
        }
    }
    
    func testDecodeEmptyList() {
        
        let value = ReferencesTest(
            id: .init(),
            reference: nil,
            references: [],
            nestedValue: nil,
            nestedList: [],
            nestedNonCloud: nil,
            nestedNonCloudList: []
        )
        
        let record = CKRecord(
            recordType: type(of: value.id).cloudRecordType,
            recordID: value.id.cloudRecordID
        )
        
        let context = CloudKitTestContext(records: [record])
        let decoder = CloudKitDecoder(context: context)
        do {
            let decodedValue = try decoder.decode(ReferencesTest.self, from: record)
            XCTAssertEqual(value, decodedValue)
        } catch {
            dump(error)
            XCTFail("\(error)")
        }
    }
}

// MARK: - Supporting Types

internal struct CloudKitTestContext: CloudKitContext {
    
    let records: [CKRecord]
    
    func fetch(record identifier: CKRecord.ID) throws -> CKRecord? {
        return records.first(where: { $0.recordID == identifier })
    }
}

extension CloudKitTestContext: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: CKRecord...) {
        self.init(records: elements)
    }
}

public struct Person: Codable, Equatable, Hashable {
    
    public let id: Person.ID
    public var gender: Gender
    public var name: String
}

public extension Person {
    struct ID: RawRepresentable, Equatable, Hashable, Codable {
        public let rawValue: String
        public init(rawValue: String = UUID().uuidString) {
            self.rawValue = rawValue
        }
    }
}

extension Person.ID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

extension Person.ID: CustomStringConvertible {
    public var description: String {
        return rawValue
    }
}

extension Person: CloudKitCodable {
    
    public var cloudIdentifier: CloudKitIdentifier {
        return id
    }
}

extension Person.ID: CloudKitIdentifier {
    
    public static var cloudRecordType: CKRecord.RecordType {
        return "Person"
    }
    
    public init(cloudRecordID: CKRecord.ID) {
        self.init(rawValue: cloudRecordID.recordName)
    }
    
    public var cloudRecordID: CKRecord.ID {
        return CKRecord.ID(recordName: rawValue)
    }
}

public enum Gender: UInt8, Codable {
    
    case male
    case female
}

public struct Profile: Codable, Equatable {
    
    public let id: ID
    public let person: Person
    public var friends: [Person]
    public var favorites: [Person.ID]
    public var userInfo: [UInt: String]?
}

public extension Profile {
    struct ID: RawRepresentable, Equatable, Hashable, Codable {
        public let rawValue: UInt
        public init(rawValue: UInt = .random(in: .min ... UInt(UInt8.max))) {
            self.rawValue = rawValue
        }
    }
}

extension Profile.ID: CustomStringConvertible {
    public var description: String {
        return rawValue.description
    }
}

extension Profile.ID: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: UInt) {
        self.init(rawValue: value)
    }
}
extension Profile: CloudKitCodable {
    
    public var cloudIdentifier: CloudKitIdentifier {
        return id
    }
}

extension Profile.ID: CloudKitIdentifier {
    
    public static var cloudRecordType: CKRecord.RecordType {
        return "Profile"
    }
    
    public init?(cloudRecordID: CKRecord.ID) {
        guard let rawValue = UInt(cloudRecordID.recordName)
            else { return nil }
        self.init(rawValue: rawValue)
    }
    
    public var cloudRecordID: CKRecord.ID {
        return CKRecord.ID(recordName: rawValue.description)
    }
}

public struct AttributesTest: Codable, Equatable, Hashable {
    
    public var id: ID
    public var boolean: Bool
    public var int: Int
    public var uint: UInt
    public var float: Float
    public var double: Double
    public var int8: Int8
    public var int16: Int16
    public var int32: Int32
    public var int64: Int64
    public var uint8: UInt8
    public var uint16: UInt16
    public var uint32: UInt32
    public var uint64: UInt64
    public var string: String
    public var date: Date
    public var data: Data
    public var url: URL
    public var uuid: UUID
    public var location: Location
    public var asset: URL
}

public struct Location: Codable, Equatable, Hashable {
    public let latitude: Double
    public let longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

extension Location: CloudKitLocation {
    public init(location: CLLocation) {
        self.init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }
    public var location: CLLocation {
        return .init(latitude: latitude, longitude: longitude)
    }
}

public extension AttributesTest {
    struct ID: RawRepresentable, Equatable, Hashable, Codable {
        public let rawValue: UUID
        public init(rawValue: UUID = UUID()) {
            self.rawValue = rawValue
        }
    }
}

extension AttributesTest: CloudKitCodable {
    public var cloudIdentifier: CloudKitIdentifier {
        return id
    }
}

extension AttributesTest.ID: CloudKitIdentifier {
    public static var cloudRecordType: CKRecord.RecordType {
        return "AttributesTest"
    }
    public init?(cloudRecordID: CKRecord.ID) {
        guard let rawValue = UUID(uuidString: cloudRecordID.recordName)
            else { return nil }
        self.init(rawValue: rawValue)
    }
    public var cloudRecordID: CKRecord.ID {
        return CKRecord.ID(recordName: rawValue.uuidString)
    }
}

public struct PrimitiveArray: Codable, Equatable {
    
    public let id: ID
    public var strings: [String]
    public var integers: [Int]
}

public extension PrimitiveArray {
    struct ID: RawRepresentable, Equatable, Hashable, Codable {
        public let rawValue: UUID
        public init(rawValue: UUID = UUID()) {
            self.rawValue = rawValue
        }
    }
}

extension PrimitiveArray: CloudKitCodable {
    public var cloudIdentifier: CloudKitIdentifier {
        return id
    }
}

extension PrimitiveArray.ID: CloudKitIdentifier {
    
    public static var cloudRecordType: CKRecord.RecordType {
        return "PrimitiveArray"
    }
    
    public init?(cloudRecordID: CKRecord.ID) {
        guard let rawValue = UUID(uuidString: cloudRecordID.recordName)
            else { return nil }
        self.init(rawValue: rawValue)
    }
    
    public var cloudRecordID: CKRecord.ID {
        return CKRecord.ID(recordName: rawValue.uuidString)
    }
}

public struct DeviceInformation: Equatable, Codable {
    
    public let id: Identifier
    public let buildVersion: BuildVersion
    public let version: Version
    public var status: Status
    public let features: BitMaskOptionSet<Feature>
}

public extension DeviceInformation {
    struct Identifier: RawRepresentable, Equatable, Hashable, Codable {
        public let rawValue: UUID
        public init(rawValue: UUID = UUID()) {
            self.rawValue = rawValue
        }
    }
}

extension DeviceInformation: CloudKitCodable {
    public var cloudIdentifier: CloudKitIdentifier {
        return id
    }
}

extension DeviceInformation.Identifier: CloudKitIdentifier {
    
    public static var cloudRecordType: CKRecord.RecordType {
        return "DeviceInformation"
    }
    
    public init?(cloudRecordID: CKRecord.ID) {
        guard let rawValue = UUID(uuidString: cloudRecordID.recordName)
            else { return nil }
        self.init(rawValue: rawValue)
    }
    
    public var cloudRecordID: CKRecord.ID {
        return CKRecord.ID(recordName: rawValue.uuidString)
    }
}

public extension DeviceInformation {
    
    enum Status: UInt8, Codable {
        case idle = 0x00
        case provisioning = 0x01
        case provisioned = 0x02
    }
    
    struct BuildVersion: RawRepresentable, Equatable, Hashable, Codable {
        
        public let rawValue: UInt64
        
        public init(rawValue: UInt64) {
            self.rawValue = rawValue
        }
        
        public init(from decoder: Decoder) throws {
            
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(RawValue.self)
            self.init(rawValue: rawValue)
        }
        
        public func encode(to encoder: Encoder) throws {
            
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }
    
    enum Feature: UInt8, BitMaskOption, Codable, CaseIterable {
        
        case bluetooth  = 0b001
        case camera     = 0b010
        case gps        = 0b100
    }
}

public struct Version: Equatable, Hashable, Codable {
    
    public var major: UInt8
    
    public var minor: UInt8
    
    public var patch: UInt8
}

extension Version {
    public var description: String {
        return "\(major).\(minor).\(patch)"
    }
}

public extension Version {
    struct Identifier: RawRepresentable, Equatable, Hashable, Codable {
        public let rawValue: String
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }
}

extension Version: CloudKitCodable {
    public var cloudIdentifier: CloudKitIdentifier {
        return Identifier(rawValue: description)
    }
}

extension Version.Identifier: CloudKitIdentifier {
    
    public static var cloudRecordType: CKRecord.RecordType {
        return "Version"
    }
    
    public init?(cloudRecordID: CKRecord.ID) {
        self.init(rawValue: cloudRecordID.recordName)
    }
    
    public var cloudRecordID: CKRecord.ID {
        return CKRecord.ID(recordName: rawValue)
    }
}

public struct CryptoRequest: Equatable, Codable {
    
    public let identifier: Identifier
    
    ///  Private key data.
    public let secret: CryptoData
    
    public init(identifier: Identifier = .init(), secret: CryptoData) {
        self.identifier = identifier
        self.secret = secret
    }
}

public extension CryptoRequest {
    struct Identifier: RawRepresentable, Equatable, Hashable, Codable {
        public let rawValue: UUID
        public init(rawValue: UUID = UUID()) {
            self.rawValue = rawValue
        }
    }
}

extension CryptoRequest: CloudKitCodable {
    public var cloudIdentifier: CloudKitIdentifier {
        return identifier
    }
}

extension CryptoRequest.Identifier: CloudKitIdentifier {
    
    public static var cloudRecordType: CKRecord.RecordType {
        return "CryptoRequest"
    }
    
    public init?(cloudRecordID: CKRecord.ID) {
        guard let rawValue = UUID(uuidString: cloudRecordID.recordName)
            else { return nil }
        self.init(rawValue: rawValue)
    }
    
    public var cloudRecordID: CKRecord.ID {
        return CKRecord.ID(recordName: rawValue.uuidString)
    }
}

public protocol SecureData: Hashable {
    
    /// The data length.
    static var length: Int { get }
    
    /// The data.
    var data: Data { get }
    
    /// Initialize with data.
    init?(data: Data)
    
    /// Initialize with random value.
    init()
}

public extension SecureData where Self: Decodable {
    
    init(from decoder: Decoder) throws {
        
        let container = try decoder.singleValueContainer()
        let data = try container.decode(Data.self)
        guard let value = Self(data: data) else {
            throw DecodingError.typeMismatch(Self.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid number of bytes \(data.count) for \(String(reflecting: Self.self))"))
        }
        self = value
    }
}

public extension SecureData where Self: Encodable {
    
    func encode(to encoder: Encoder) throws {
        
        var container = encoder.singleValueContainer()
        try container.encode(data)
    }
}

/// Crypto Data
public struct CryptoData: SecureData, Codable {
    
    public static let length = 256 / 8 // 32
    
    public let data: Data
    
    public init?(data: Data) {
        
        guard data.count == type(of: self).length
            else { return nil }
        
        self.data = data
    }
    
    /// Initializes with a random value.
    public init() {
        self.data = Data(repeating: 0xFF, count: type(of: self).length) // not really random
    }
}

public struct ReferencesTest: Equatable, Codable {
    
    public let id: Identifier
    public var reference: Identifier?
    public var references: Set<Identifier>
    public var nestedValue: Person?
    public var nestedList: [Person]
    public var nestedNonCloud: NonCloud?
    public var nestedNonCloudList: [NonCloud]
}

public extension ReferencesTest {
    
    struct NonCloud: Equatable, Codable {
        let name: String
        let value: Data
        let url: URL
    }
}

public extension ReferencesTest {
    struct Identifier: RawRepresentable, Equatable, Hashable, Codable {
        public let rawValue: UUID
        public init(rawValue: UUID = UUID()) {
            self.rawValue = rawValue
        }
    }
}

extension ReferencesTest: CloudKitCodable {
    public var cloudIdentifier: CloudKitIdentifier {
        return id
    }
}

extension ReferencesTest.Identifier: CloudKitIdentifier {
    
    public static var cloudRecordType: CKRecord.RecordType {
        return "ReferencesTest"
    }
    
    public init?(cloudRecordID: CKRecord.ID) {
        guard let rawValue = UUID(uuidString: cloudRecordID.recordName)
            else { return nil }
        self.init(rawValue: rawValue)
    }
    
    public var cloudRecordID: CKRecord.ID {
        return CKRecord.ID(recordName: rawValue.uuidString)
    }
}

/// Enum that represents a bit mask flag / option.
///
/// Basically `Swift.OptionSet` for enums.
public protocol BitMaskOption: RawRepresentable, Hashable, CaseIterable where RawValue: FixedWidthInteger { }

public extension Sequence where Element: BitMaskOption {
    
    /// Convert Swift enums for bit mask options into their raw values OR'd.
    var rawValue: Element.RawValue {
        
        @inline(__always)
        get { return reduce(0, { $0 | $1.rawValue }) }
    }
}

public extension BitMaskOption {
    
    /// Whether the enum case is present in the raw value.
    @inline(__always)
    func isContained(in rawValue: RawValue) -> Bool {
        
        return (self.rawValue & rawValue) != 0
    }
    
    @inline(__always)
    static func from(rawValue: RawValue) -> [Self] {
        
        return Self.allCases.filter { $0.isContained(in: rawValue) }
    }
}

// MARK: - BitMaskOptionSet

/// Integer-backed array type for `BitMaskOption`.
///
/// The elements are packed in the integer with bitwise math and stored on the stack.
public struct BitMaskOptionSet <Element: BitMaskOption>: RawRepresentable {
    
    public typealias RawValue = Element.RawValue
    
    public private(set) var rawValue: RawValue
    
    @inline(__always)
    public init(rawValue: RawValue) {
        
        self.rawValue = rawValue
    }
    
    @inline(__always)
    public init() {
        
        self.rawValue = 0
    }
    
    public static var all: BitMaskOptionSet<Element> {
        
        return BitMaskOptionSet<Element>(rawValue: Element.allCases.rawValue)
    }
    
    @inline(__always)
    public mutating func insert(_ element: Element) {
        
        rawValue = rawValue | element.rawValue
    }
    
    @discardableResult
    public mutating func remove(_ element: Element) -> Bool {
        
        guard contains(element) else { return false }
        
        rawValue = rawValue & ~element.rawValue
        
        return true
    }
    
    @inline(__always)
    public mutating func removeAll() {
        
        self.rawValue = 0
    }
    
    @inline(__always)
    public func contains(_ element: Element) -> Bool {
        
        return element.isContained(in: rawValue)
    }
    
    public func contains <S: Sequence> (_ other: S) -> Bool where S.Iterator.Element == Element {
        
        for element in other {
            
            guard element.isContained(in: rawValue)
                else { return false }
        }
        
        return true
    }
    
    public var count: Int {
        
        return Element.allCases.reduce(0, { $0 + ($1.isContained(in: rawValue) ? 1 : 0) })
    }
    
    public var isEmpty: Bool {
        
        return rawValue == 0
    }
}

// MARK: - Sequence Conversion

public extension BitMaskOptionSet {
    
    init<S: Sequence>(_ sequence: S) where S.Iterator.Element == Element {
        self.rawValue = sequence.rawValue
    }
}

extension BitMaskOptionSet: Equatable {
    
    public static func == (lhs: BitMaskOptionSet, rhs: BitMaskOptionSet) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }
}

extension BitMaskOptionSet: CustomStringConvertible {
    
    public var description: String {
        
        return Element.from(rawValue: rawValue)
            .sorted(by: { $0.rawValue < $1.rawValue })
            .description
    }
}

extension BitMaskOptionSet: Hashable {
    
    #if swift(>=4.2)
    public func hash(into hasher: inout Hasher) {
        rawValue.hash(into: &hasher)
    }
    #else
    public var hashValue: Int {
        return rawValue.hashValue
    }
    #endif
}

extension BitMaskOptionSet: ExpressibleByArrayLiteral {
    
    public init(arrayLiteral elements: Element...) {
        
        self.init(elements)
    }
}

extension BitMaskOptionSet: ExpressibleByIntegerLiteral {
    
    public init(integerLiteral value: UInt64) {
        
        self.init(rawValue: numericCast(value))
    }
}

extension BitMaskOptionSet: Sequence {
    
    public func makeIterator() -> IndexingIterator<[Element]> {
        
        return Element.from(rawValue: rawValue).makeIterator()
    }
}

extension BitMaskOptionSet: Codable where BitMaskOptionSet.RawValue: Codable {
    
    public init(from decoder: Decoder) throws {
        
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(RawValue.self)
        self.init(rawValue: rawValue)
    }
    
    public func encode(to encoder: Encoder) throws {
        
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
