// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UserDecoder",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "UserDecoder",
            plugins: [.plugin(name: "JSONSchemaPlugin", package: "swift-json-schema")]
        )
    ]
)
