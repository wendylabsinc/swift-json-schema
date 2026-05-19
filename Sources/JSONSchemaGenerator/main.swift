import Foundation
import JSONSchemaGeneratorCore

let args = CommandLine.arguments.dropFirst()
let positional = args.filter { !$0.hasPrefix("--") }
let flags = Set(args.filter { $0.hasPrefix("--") })

guard positional.count == 2 else {
    FileHandle.standardError.write(Data("Usage: JSONSchemaGenerator <input.schema.json> <output.swift> [--swift-json]\n".utf8))
    exit(1)
}

let inputPath = positional[positional.startIndex]
let outputPath = positional[positional.index(after: positional.startIndex)]

guard !inputPath.isEmpty, !outputPath.isEmpty else {
    FileHandle.standardError.write(Data("Usage: JSONSchemaGenerator <input.schema.json> <output.swift> [--swift-json]\n".utf8))
    exit(1)
}

do {
    let data = try Data(contentsOf: URL(fileURLWithPath: inputPath))
    let schema = try JSONDecoder().decode(JSONSchema.self, from: data)
    let resolved = try SchemaResolver.resolve(schema)
    let options = CodeGenerator.Options(generateSpanInits: flags.contains("--swift-json"))
    let output = try CodeGenerator(resolved: resolved, options: options).generate()
    try output.write(toFile: outputPath, atomically: true, encoding: .utf8)
} catch let error as ResolverError {
    FileHandle.standardError.write(Data("Schema error in \(inputPath): \(error)\n".utf8))
    exit(1)
} catch let error as CodeGenerator.GeneratorError {
    FileHandle.standardError.write(Data("Code generation error in \(inputPath): \(error)\n".utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data("Error processing \(inputPath): \(error)\n".utf8))
    exit(1)
}
