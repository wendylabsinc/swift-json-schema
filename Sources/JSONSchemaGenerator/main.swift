import Foundation
import JSONSchemaGeneratorCore

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: JSONSchemaGenerator <input.schema.json> <output.swift>\n", stderr)
    exit(1)
}

let inputPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]

guard !inputPath.isEmpty, !outputPath.isEmpty else {
    fputs("Usage: JSONSchemaGenerator <input.schema.json> <output.swift>\n", stderr)
    exit(1)
}

do {
    let data = try Data(contentsOf: URL(fileURLWithPath: inputPath))
    let schema = try JSONDecoder().decode(JSONSchema.self, from: data)
    let resolved = try SchemaResolver.resolve(schema)
    let output = try CodeGenerator(resolved: resolved).generate()
    try output.write(toFile: outputPath, atomically: true, encoding: .utf8)
} catch let error as ResolverError {
    fputs("Schema error in \(inputPath): \(error)\n", stderr)
    exit(1)
} catch let error as CodeGenerator.GeneratorError {
    fputs("Code generation error in \(inputPath): \(error)\n", stderr)
    exit(1)
} catch {
    fputs("Error processing \(inputPath): \(error)\n", stderr)
    exit(1)
}
