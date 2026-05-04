public struct CodeGenerator {
    public enum GeneratorError: Error, Equatable, Sendable {
        case missingTitle
        case unsupportedPropertyType(property: String, context: String)
    }

    let resolved: ResolvedSchema

    public init(resolved: ResolvedSchema) {
        self.resolved = resolved
    }

    public func generate() throws -> String {
        guard let title = resolved.root.title else {
            throw GeneratorError.missingTitle
        }
        var parts: [String] = []
        for (name, def) in resolved.defs.sorted(by: { $0.key < $1.key }) {
            parts.append(try generateType(name: IdentifierSanitizer.typeName(from: name), schema: def))
        }
        parts.append(try generateType(name: IdentifierSanitizer.typeName(from: title), schema: resolved.root))
        return parts.joined(separator: "\n\n")
    }

    private func generateType(name: String, schema: JSONSchema) throws -> String {
        if let values = schema.enumValues {
            return generateEnumKeyword(name: name, values: values)
        }
        if let variants = schema.oneOf ?? schema.anyOf {
            return generateUnionEnum(name: name, variants: variants)
        }
        return try generateStruct(name: name, schema: schema)
    }

    // MARK: - Struct

    private func generateStruct(name: String, schema: JSONSchema) throws -> String {
        struct PropInfo {
            let jsonKey: String
            let swiftKey: String
            let typeStr: String
            let isRequired: Bool
            let minItems: Int?
            let maxItems: Int?
            let uniqueItems: Bool?
            var hasConstraints: Bool { minItems != nil || maxItems != nil || uniqueItems == true }
        }

        var lines: [String] = []
        if let desc = schema.description { lines.append("/// \(desc)") }
        lines.append("struct \(name): Codable, Hashable {")

        let sorted = (schema.properties ?? [:]).sorted(by: { $0.key < $1.key })
        let required = Set(schema.required ?? [])
        var info: [PropInfo] = []
        var needsCodingKeys = false

        for (i, (jsonKey, propSchema)) in sorted.enumerated() {
            let isRequired = required.contains(jsonKey)
            let swiftKey = IdentifierSanitizer.propertyName(from: jsonKey, fallbackIndex: i)
            let typeStr = swiftType(for: propSchema, isRequired: isRequired)
            guard typeStr != "Any" && typeStr != "Any?" && typeStr != "[Any]" && typeStr != "[Any]?" else {
                throw GeneratorError.unsupportedPropertyType(
                    property: jsonKey,
                    context: "type '\(propSchema.type.map { "\($0)" } ?? "none")' cannot be represented as a Codable Swift type; use $ref or a concrete type"
                )
            }
            info.append(PropInfo(
                jsonKey: jsonKey, swiftKey: swiftKey, typeStr: typeStr, isRequired: isRequired,
                minItems: propSchema.minItems, maxItems: propSchema.maxItems, uniqueItems: propSchema.uniqueItems
            ))
            if IdentifierSanitizer.needsCodingKey(jsonKey, swiftName: swiftKey) {
                needsCodingKeys = true
            }
        }

        for entry in info {
            lines.append("    \(entry.isRequired ? "let" : "var") \(entry.swiftKey): \(entry.typeStr)")
        }

        let needsCustomInit = info.contains { $0.hasConstraints }

        if needsCustomInit {
            lines.append("")
            lines.append("    init(from decoder: any Decoder) throws {")
            lines.append("        let container = try decoder.container(keyedBy: CodingKeys.self)")
            for entry in info {
                let baseType = entry.typeStr.hasSuffix("?") ? String(entry.typeStr.dropLast()) : entry.typeStr
                if entry.isRequired {
                    lines.append("        let \(entry.swiftKey) = try container.decode(\(baseType).self, forKey: .\(entry.swiftKey))")
                } else {
                    lines.append("        let \(entry.swiftKey) = try container.decodeIfPresent(\(baseType).self, forKey: .\(entry.swiftKey))")
                }
                if entry.hasConstraints {
                    lines.append(contentsOf: generateArrayValidation(
                        swiftKey: entry.swiftKey, isRequired: entry.isRequired,
                        minItems: entry.minItems, maxItems: entry.maxItems, uniqueItems: entry.uniqueItems
                    ))
                }
            }
            for entry in info {
                lines.append("        self.\(entry.swiftKey) = \(entry.swiftKey)")
            }
            lines.append("    }")
        }

        if needsCustomInit || needsCodingKeys {
            lines.append("")
            lines.append("    enum CodingKeys: String, CodingKey {")
            for entry in info {
                let plain = entry.swiftKey.hasPrefix("`")
                    ? String(entry.swiftKey.dropFirst().dropLast())
                    : entry.swiftKey
                let escapedCase = IdentifierSanitizer.reservedWords.contains(plain)
                    ? "`\(plain)`" : plain
                if plain == entry.jsonKey {
                    lines.append("        case \(escapedCase)")
                } else {
                    lines.append("        case \(escapedCase) = \"\(entry.jsonKey)\"")
                }
            }
            lines.append("    }")
        }

        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private func generateArrayValidation(
        swiftKey: String, isRequired: Bool,
        minItems: Int?, maxItems: Int?, uniqueItems: Bool?
    ) -> [String] {
        var checks: [String] = []
        if let min = minItems {
            let noun = min == 1 ? "item" : "items"
            checks += [
                "        guard \(swiftKey).count >= \(min) else {",
                "            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,",
                "                debugDescription: \"\(swiftKey): expected at least \(min) \(noun)\"))",
                "        }"
            ]
        }
        if let max = maxItems {
            let noun = max == 1 ? "item" : "items"
            checks += [
                "        guard \(swiftKey).count <= \(max) else {",
                "            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,",
                "                debugDescription: \"\(swiftKey): expected at most \(max) \(noun)\"))",
                "        }"
            ]
        }
        if uniqueItems == true {
            checks += [
                "        guard Set(\(swiftKey)).count == \(swiftKey).count else {",
                "            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,",
                "                debugDescription: \"\(swiftKey): items must be unique\"))",
                "        }"
            ]
        }
        guard !isRequired else { return checks }
        return ["        if let \(swiftKey) {"]
            + checks.map { "    " + $0 }
            + ["        }"]
    }

    // MARK: - Type resolution

    private func swiftType(for schema: JSONSchema, isRequired: Bool) -> String {
        let (base, typeIsNullable) = rawTypeAndNullability(for: schema)
        let optional = !isRequired || typeIsNullable
        return optional ? "\(base)?" : base
    }

    private func rawTypeAndNullability(for schema: JSONSchema) -> (String, Bool) {
        if let ref = schema.ref {
            let name = String(ref.dropFirst("#/$defs/".count))
            return (IdentifierSanitizer.typeName(from: name), false)
        }
        guard let type = schema.type else { return ("Any", false) }
        switch type {
        case .single(let p):
            return p == .null ? ("Void", true) : (swiftPrimitive(p, items: schema.items), false)
        case .array(let ps):
            let nonNull = ps.filter { $0 != .null }
            if nonNull.count == 1 {
                return (swiftPrimitive(nonNull[0], items: schema.items), ps.contains(.null))
            }
            return ("Any", false)
        }
    }

    private func swiftPrimitive(_ p: PrimitiveType, items: JSONSchema?) -> String {
        switch p {
        case .string: return "String"
        case .integer: return "Int"
        case .number: return "Double"
        case .boolean: return "Bool"
        case .null: return "Void"
        case .object: return "Any"
        case .array:
            let element = items.map { rawTypeAndNullability(for: $0).0 } ?? "Any"
            return "[\(element)]"
        }
    }

    private func generateEnumKeyword(name: String, values: [JSONSchemaValue]) -> String {
        let allStrings = values.allSatisfy { if case .string = $0 { return true }; return false }
        let conformance = allStrings ? "String, Codable, Hashable" : "Int, Codable, Hashable"
        var lines = ["enum \(name): \(conformance) {"]
        for (i, value) in values.enumerated() {
            switch value {
            case .string(let s):
                let caseName = IdentifierSanitizer.propertyName(from: s, fallbackIndex: i)
                lines.append("    case \(caseName) = \"\(s)\"")
            case .integer(let n):
                let caseName = n < 0 ? "valueNeg\(-n)" : "value\(n)"
                lines.append("    case \(caseName) = \(n)")
            }
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private func generateUnionEnum(name: String, variants: [JSONSchema]) -> String {
        var caseNames: [String] = []
        var caseTypes: [String] = []

        for (i, variant) in variants.enumerated() {
            if let ref = variant.ref {
                let typeName = IdentifierSanitizer.typeName(from: String(ref.dropFirst("#/$defs/".count)))
                caseNames.append(IdentifierSanitizer.propertyName(from: typeName, fallbackIndex: i))
                caseTypes.append(typeName)
            } else if let title = variant.title {
                let typeName = IdentifierSanitizer.typeName(from: title)
                caseNames.append(IdentifierSanitizer.propertyName(from: typeName, fallbackIndex: i))
                caseTypes.append(typeName)
            } else {
                caseNames.append("case\(i + 1)")
                caseTypes.append("Any")
            }
        }

        var lines = ["enum \(name): Codable, Hashable {"]
        for (caseName, caseType) in zip(caseNames, caseTypes) {
            lines.append("    case \(caseName)(\(caseType))")
        }

        // init(from:)
        lines.append("")
        lines.append("    init(from decoder: any Decoder) throws {")
        for (i, (caseName, caseType)) in zip(caseNames, caseTypes).enumerated() {
            let prefix = i == 0 ? "        if" : "        } else if"
            lines.append("\(prefix) let value = try? \(caseType)(from: decoder) {")
            lines.append("            self = .\(caseName)(value)")
        }
        lines.append("        } else {")
        lines.append("            throw DecodingError.dataCorrupted(")
        lines.append("                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: \"No variant matched\")")
        lines.append("            )")
        lines.append("        }")
        lines.append("    }")

        // encode(to:)
        lines.append("")
        lines.append("    func encode(to encoder: any Encoder) throws {")
        lines.append("        switch self {")
        for (caseName, _) in zip(caseNames, caseTypes) {
            lines.append("        case .\(caseName)(let value):")
            lines.append("            try value.encode(to: encoder)")
        }
        lines.append("        }")
        lines.append("    }")

        lines.append("}")
        return lines.joined(separator: "\n")
    }
}
