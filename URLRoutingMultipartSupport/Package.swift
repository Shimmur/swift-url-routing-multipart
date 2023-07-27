// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-url-routing-multipart",
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "URLRoutingMultipartSupport",
            targets: ["URLRoutingMultipartSupport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-url-routing", from: "0.5.0"),
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
            dependencies: ["URLRoutingMultipartSupport"]
        )
    ]
)
