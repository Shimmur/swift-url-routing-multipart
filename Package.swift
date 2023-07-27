// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-url-routing-multipart",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .library(
            name: "URLRoutingMultipartSupport",
            targets: ["URLRoutingMultipartSupport"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-url-routing", from: "0.5.0"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "0.10.2"),
    ],
    targets: [
        .target(
            name: "URLRoutingMultipartSupport",
            dependencies: [
                .product(name: "URLRouting", package: "swift-url-routing")
            ]
        ),
        .testTarget(
            name: "URLRoutingMultipartSupportTests",
            dependencies: [
                .product(name: "CustomDump", package: "swift-custom-dump"),
                "URLRoutingMultipartSupport"
            ]
        )
    ]
)
