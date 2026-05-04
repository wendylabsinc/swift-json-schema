import PackagePlugin

@main
struct JSONSchemaPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        let generator = try context.tool(named: "JSONSchemaGenerator")

        return target.sourceFiles(withSuffix: ".schema.json").map { file in
            let stem = file.url.deletingPathExtension().lastPathComponent
            let baseName = stem.hasSuffix(".schema") ? String(stem.dropLast(".schema".count)) : stem
            let outputURL = context.pluginWorkDirectoryURL.appending(component: "\(baseName).swift")

            return .buildCommand(
                displayName: "Generating \(baseName).swift from \(file.url.lastPathComponent)",
                executable: generator.url,
                arguments: [file.url.path(percentEncoded: false), outputURL.path(percentEncoded: false)],
                inputFiles: [file.url],
                outputFiles: [outputURL]
            )
        }
    }
}
