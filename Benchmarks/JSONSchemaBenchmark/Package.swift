// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "JSONSchemaBenchmark",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../..", traits: ["SwiftJSON"]),
        .package(url: "https://github.com/orlandos-nl/swift-json.git", from: "2.5.0"),
        .package(url: "https://github.com/ordo-one/package-benchmark", from: "1.27.0"),
    ],
    targets: [
        .executableTarget(
            name: "JSONSchemaBenchmark",
            dependencies: [
                .product(name: "IkigaJSON", package: "swift-json"),
                .product(name: "Benchmark", package: "package-benchmark"),
            ],
            path: ".",
            exclude: ["Package.swift"],
            plugins: [
                .plugin(name: "JSONSchemaPlugin", package: "swift-json-schema"),
                .plugin(name: "BenchmarkPlugin", package: "package-benchmark"),
            ]
        )
    ]
)
