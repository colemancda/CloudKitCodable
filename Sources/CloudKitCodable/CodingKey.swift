//
//  CodingKey.swift
//  
//
//  Created by Alsey Coleman Miller on 9/10/19.
//

internal extension Sequence where Element == CodingKey {
    
    /// KVC path string for current coding path.
    var path: String {
        return reduce("", { $0 + "\($0.isEmpty ? "" : ".")" + $1.stringValue })
    }
}

internal extension CodingKey {
    
    static var sanitizedName: String {
        
        let rawName = String(reflecting: self)
        #if swift(>=5.0)
        var elements = rawName.split(separator: ".")
        #else
        var elements = rawName.components(separatedBy: ".")
        #endif
        guard elements.count > 2
            else { return rawName }
        elements.removeFirst()
        #if swift(>=5.0)
        elements.removeAll { $0.contains("(unknown context") }
        #else
        while let index = elements.index(where: { $0.contains("(unknown context") }) {
            elements.remove(at: index)
        }
        #endif
        return elements.reduce("", { $0 + ($0.isEmpty ? "" : ".") + $1 })
    }
}
