// swift-tools-version: 6.2

import PackageDescription

let includesBenchmarks = Context.environment["SWIFT_NIO_UDP_ENABLE_BENCHMARKS"] == "1"

let package = Package(
    name: "swift-nio-udp",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2),
    ],
    products: [
        .library(
            name: "NIOUDPTransport",
            targets: ["NIOUDPTransport"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.92.0"),
    ],
    targets: [
        .target(
            name: "NIOUDPTransport",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ],
            path: "Sources/NIOUDPTransport",
            exclude: ["CONTEXT.md"]
        ),
        .testTarget(
            name: "NIOUDPTransportTests",
            dependencies: ["NIOUDPTransport"],
            path: "Tests/NIOUDPTransportTests"
        ),
    ] + (includesBenchmarks ? [
        .executableTarget(
            name: "NIOUDPTransportBenchmarks",
            dependencies: [
                "NIOUDPTransport",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ],
            path: "Benchmarks/NIOUDPTransportBenchmarks"
        ),
    ] : [])
)
