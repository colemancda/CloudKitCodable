// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CloudKitCodable",
    products: [
        .library(
            name: "CloudKitCodable",
            targets: ["CloudKitCodable"]),
    ],
    targets: [
        .target(
            name: "CloudKitCodable",
            dependencies: []
        ),
        .testTarget(
            name: "CloudKitCodableTests",
            dependencies: ["CloudKitCodable"]
        ),
    ]
)
