// swift-tools-version:6.0
//
//  Package.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

import PackageDescription

let package = Package(
    name: "SwiftCheck",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwiftCheckCore", targets: ["SwiftCheckCore"]),
        .executable(name: "swiftcheck", targets: ["swiftcheck"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "602.0.0"..<"603.0.0"),
    ],
    targets: [
        .target(
            name: "SwiftCheckCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .executableTarget(
            name: "swiftcheck",
            dependencies: ["SwiftCheckCore"]
        ),
        .testTarget(
            name: "SwiftCheckCoreTests",
            dependencies: [
                "SwiftCheckCore",
                "swiftcheck",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
