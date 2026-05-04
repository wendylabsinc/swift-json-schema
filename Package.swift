// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-json-schema",
    platforms: [.macOS(.v13)],
    products: [
        .plugin(name: "JSONSchemaPlugin", targets: ["JSONSchemaPlugin"]),
    ],
    targets: [
        .plugin(
            name: "JSONSchemaPlugin",
            capability: .buildTool(),
            dependencies: ["JSONSchemaGenerator"]
        ),
        .target(
            name: "JSONSchemaGeneratorCore"
        ),
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
