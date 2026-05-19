// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "UserDecoder",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(name: "swift-json-schema", path: "../..", traits: ["SwiftJSON"]),
    ],
    targets: [
        .executableTarget(
            name: "UserDecoder",
            dependencies: [
                .product(name: "JSONSchemaSwiftJSON", package: "swift-json-schema"),
            ],
            plugins: [.plugin(name: "JSONSchemaPlugin", package: "swift-json-schema")]
        )
    ]
)
