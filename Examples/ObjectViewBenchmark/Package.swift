// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ObjectViewBenchmark",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "swift-json-schema", path: "../..", traits: ["SwiftJSON"]),
        .package(path: "/Users/joannisorlandos/git/orlandos-nl/swift-json"),
    ],
    targets: [
        .executableTarget(
            name: "ObjectViewBenchmark",
            dependencies: [
                .product(name: "IkigaJSON", package: "swift-json"),
            ],
            plugins: [.plugin(name: "JSONSchemaPlugin", package: "swift-json-schema")]
        )
    ]
)
