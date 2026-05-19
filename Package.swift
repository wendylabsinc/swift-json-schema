// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "swift-json-schema",
    platforms: [.macOS(.v13)],
    products: [
        .plugin(name: "JSONSchemaPlugin", targets: ["JSONSchemaPlugin"]),
    ],
    traits: [
        .trait(name: "SwiftJSON", description: "Generate Span<UInt8> initializers using IkigaJSON"),
    ],
    dependencies: [
        .package(path: "/Users/joannisorlandos/git/orlandos-nl/swift-json"),
    ],
    targets: [
        .plugin(
            name: "JSONSchemaPlugin",
            capability: .buildTool(),
            dependencies: ["JSONSchemaGenerator"]
        ),
        .target(name: "JSONSchemaGeneratorCore"),
        .executableTarget(
            name: "JSONSchemaGenerator",
            dependencies: ["JSONSchemaGeneratorCore"]
        ),
        .testTarget(
            name: "JSONSchemaGeneratorTests",
            dependencies: ["JSONSchemaGeneratorCore"]
        ),
    ]
)
