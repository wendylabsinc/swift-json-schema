public struct CodeGenerator {
    public enum GeneratorError: Error, Equatable, Sendable {
        case missingTitle
        case unsupportedPropertyType(property: String, context: String)
    }

    public struct Options: Sendable {
        public var generateSpanInits: Bool

        public init(generateSpanInits: Bool = false) {
            self.generateSpanInits = generateSpanInits
        }
    }

    let resolved: ResolvedSchema
    let options: Options

    public init(resolved: ResolvedSchema, options: Options = Options()) {
        self.resolved = resolved
        self.options = options
    }

    public func generate() throws -> String {
        guard let title = resolved.root.title else {
            throw GeneratorError.missingTitle
        }
        var parts: [String] = []
        if options.generateSpanInits {
            parts.append("#if canImport(IkigaJSON)\nimport IkigaJSON\nimport JSONSchemaSwiftJSON\n#endif")
        }
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

        if options.generateSpanInits {
            lines.append("")
            lines.append("#if canImport(IkigaJSON)")
            lines.append(contentsOf: generateSpanInit(info: info))
            lines.append("")
            lines.append(contentsOf: generateObjectViewInit(info: info))
            lines.append("")
            lines.append(contentsOf: generateJSONObjectInit(info: info))
            lines.append("#endif")
        }

        lines.append("}")
        return lines.joined(separator: "\n")
    }

    // MARK: - Span / JSONObject / JSONObjectView inits

    private func generateSpanInit(info: [PropInfo]) -> [String] {
        return [
            "    init(json span: Span<UInt8>) throws {",
            "        let view = try JSONObjectView(span: span)",
            "        try self.init(view: view)",
            "    }",
        ]
    }

    private func generateObjectViewInit(info: [PropInfo]) -> [String] {
        var lines = ["    init(view: borrowing JSONObjectView) throws {"]
        for entry in info {
            lines.append(contentsOf: generateObjectViewFieldAccess(entry: entry))
        }
        lines.append("    }")
        return lines
    }

    private func viewTypedMethod(for jsonValueProperty: String) -> String {
        switch jsonValueProperty {
        case "int":  return "integer"
        case "bool": return "boolean"
        default:     return jsonValueProperty
        }
    }

    private func generateObjectViewFieldAccess(entry: PropInfo) -> [String] {
        let swiftKey = entry.swiftKey
        let jsonKey  = entry.jsonKey
        let typeStr  = entry.typeStr
        let mustExist = entry.isRequired && !typeStr.hasSuffix("?")

        switch jsonAccessor(for: typeStr) {
        case .scalar(let prop):
            let method = viewTypedMethod(for: prop)
            if mustExist {
                return [
                    "        guard let \(swiftKey) = try view.\(method)(forKey: \"\(jsonKey)\") else {",
                    "            throw JSONObjectError.expectedObject",
                    "        }",
                    "        self.\(swiftKey) = \(swiftKey)",
                ]
            } else {
                return ["        self.\(swiftKey) = try view.\(method)(forKey: \"\(jsonKey)\")"]
            }

        case .enumType(let typeName, let rawProperty):
            let method = viewTypedMethod(for: rawProperty)
            if mustExist {
                return [
                    "        guard let \(swiftKey)Raw = try view.\(method)(forKey: \"\(jsonKey)\"),",
                    "              let \(swiftKey) = \(typeName)(rawValue: \(swiftKey)Raw) else {",
                    "            throw JSONObjectError.expectedObject",
                    "        }",
                    "        self.\(swiftKey) = \(swiftKey)",
                ]
            } else {
                return [
                    "        self.\(swiftKey) = try view.\(method)(forKey: \"\(jsonKey)\").flatMap(\(typeName).init(rawValue:))",
                ]
            }

        case .nestedObject(let typeName):
            if mustExist {
                return [
                    "        guard let \(swiftKey) = try view.withObjectView(forKey: \"\(jsonKey)\", perform: { subView in",
                    "            try \(typeName)(view: subView)",
                    "        }) else {",
                    "            throw JSONObjectError.expectedObject",
                    "        }",
                    "        self.\(swiftKey) = \(swiftKey)",
                ]
            } else {
                return [
                    "        self.\(swiftKey) = try view.withObjectView(forKey: \"\(jsonKey)\") { subView in",
                    "            try \(typeName)(view: subView)",
                    "        }",
                ]
            }

        case .array(let element):
            return generateObjectViewArrayAccess(swiftKey: swiftKey, jsonKey: jsonKey, element: element, mustExist: mustExist)

        case .unsupported:
            return ["        self.\(swiftKey) = /* unsupported type */"]
        }
    }

    private func generateObjectViewArrayAccess(
        swiftKey: String, jsonKey: String, element: JSONValueAccessor, mustExist: Bool
    ) -> [String] {
        let elementLines: [String]
        switch element {
        case .scalar(let prop):
            let method = viewTypedMethod(for: prop)
            elementLines = [
                "                guard let value = try arrayView.\(method)(forIndex: i) else {",
                "                    throw JSONObjectError.expectedObject",
                "                }",
                "                elements.append(value)",
            ]
        case .enumType(let typeName, let rawProperty):
            let method = viewTypedMethod(for: rawProperty)
            elementLines = [
                "                guard let raw = try arrayView.\(method)(forIndex: i),",
                "                      let value = \(typeName)(rawValue: raw) else {",
                "                    throw JSONObjectError.expectedObject",
                "                }",
                "                elements.append(value)",
            ]
        case .nestedObject(let typeName):
            elementLines = [
                "                guard let value = try arrayView.withObjectView(forIndex: i, perform: { subView in",
                "                    try \(typeName)(view: subView)",
                "                }) else {",
                "                    throw JSONObjectError.expectedObject",
                "                }",
                "                elements.append(value)",
            ]
        case .array, .unsupported:
            return ["        self.\(swiftKey) = []"]
        }

        let innerType: String
        switch element {
        case .scalar(let prop):
            switch prop {
            case "string": innerType = "String"
            case "int":    innerType = "Int"
            case "double": innerType = "Double"
            case "bool":   innerType = "Bool"
            default:       innerType = "Any"
            }
        case .enumType(let typeName, _): innerType = typeName
        case .nestedObject(let typeName): innerType = typeName
        case .array, .unsupported: innerType = "Any"
        }

        let body = [
            "            var elements: [\(innerType)] = []",
            "            elements.reserveCapacity(arrayView.count)",
            "            for i in 0..<arrayView.count {",
        ] + elementLines + [
            "            }",
            "            return elements",
        ]

        if mustExist {
            return [
                "        guard let \(swiftKey) = try view.withArrayView(forKey: \"\(jsonKey)\", perform: { arrayView in",
            ] + body + [
                "        }) else {",
                "            throw JSONObjectError.expectedObject",
                "        }",
                "        self.\(swiftKey) = \(swiftKey)",
            ]
        } else {
            return [
                "        self.\(swiftKey) = try view.withArrayView(forKey: \"\(jsonKey)\") { arrayView in",
            ] + body + [
                "        }",
            ]
        }
    }

    private func generateJSONObjectInit(info: [PropInfo]) -> [String] {
        var lines: [String] = []
        lines.append("    init(json: JSONObject) throws {")
        for entry in info {
            lines.append(contentsOf: generateJSONFieldAccess(entry: entry))
        }
        lines.append("    }")
        return lines
    }

    private indirect enum JSONValueAccessor {
        case scalar(property: String)
        case enumType(typeName: String, rawProperty: String)
        case nestedObject(typeName: String)
        case array(element: JSONValueAccessor)
        case unsupported
    }

    private func isEnumDef(_ typeName: String) -> Bool {
        resolved.defs.contains { IdentifierSanitizer.typeName(from: $0.key) == typeName && $0.value.enumValues != nil }
    }

    private func isIntEnumDef(_ typeName: String) -> Bool {
        guard let schema = resolved.defs.first(where: { IdentifierSanitizer.typeName(from: $0.key) == typeName })?.value,
              let values = schema.enumValues else { return false }
        return values.allSatisfy { if case .integer = $0 { return true }; return false }
    }

    private func jsonAccessor(for typeStr: String) -> JSONValueAccessor {
        let base = typeStr.hasSuffix("?") ? String(typeStr.dropLast()) : typeStr
        if base.hasPrefix("[") && base.hasSuffix("]") {
            let inner = String(base.dropFirst().dropLast())
            let elementAccessor = jsonAccessor(for: inner)
            if case .unsupported = elementAccessor { return .unsupported }
            return .array(element: elementAccessor)
        }
        switch base {
        case "String": return .scalar(property: "string")
        case "Int":    return .scalar(property: "int")
        case "Double": return .scalar(property: "double")
        case "Bool":   return .scalar(property: "bool")
        case "Void", "Any": return .unsupported
        default:
            if isIntEnumDef(base) { return .enumType(typeName: base, rawProperty: "int") }
            if isEnumDef(base)    { return .enumType(typeName: base, rawProperty: "string") }
            return .nestedObject(typeName: base)
        }
    }

    private struct PropInfo {
        let jsonKey: String
        let swiftKey: String
        let typeStr: String
        let isRequired: Bool
        let minItems: Int?
        let maxItems: Int?
        let uniqueItems: Bool?
        var hasConstraints: Bool { minItems != nil || maxItems != nil || uniqueItems == true }
    }

    private func generateJSONFieldAccess(entry: PropInfo) -> [String] {
        let swiftKey = entry.swiftKey
        let jsonKey  = entry.jsonKey
        let typeStr  = entry.typeStr
        let isOptional = typeStr.hasSuffix("?")
        let mustExist  = entry.isRequired && !isOptional

        switch jsonAccessor(for: typeStr) {
        case .scalar(let prop):
            if mustExist {
                return [
                    "        guard let \(swiftKey) = json[\"\(jsonKey)\"]?.\(prop) else {",
                    "            throw JSONObjectError.expectedObject",
                    "        }",
                    "        self.\(swiftKey) = \(swiftKey)",
                ]
            } else {
                return ["        self.\(swiftKey) = json[\"\(jsonKey)\"]?.\(prop)"]
            }

        case .enumType(let typeName, let rawProperty):
            if mustExist {
                return [
                    "        guard let \(swiftKey)Raw = json[\"\(jsonKey)\"]?.\(rawProperty),",
                    "              let \(swiftKey) = \(typeName)(rawValue: \(swiftKey)Raw) else {",
                    "            throw JSONObjectError.expectedObject",
                    "        }",
                    "        self.\(swiftKey) = \(swiftKey)",
                ]
            } else {
                return [
                    "        self.\(swiftKey) = json[\"\(jsonKey)\"]?.\(rawProperty).flatMap(\(typeName).init(rawValue:))",
                ]
            }

        case .nestedObject(let typeName):
            if mustExist {
                return [
                    "        guard let \(swiftKey)JSON = json[\"\(jsonKey)\"]?.object else {",
                    "            throw JSONObjectError.expectedObject",
                    "        }",
                    "        self.\(swiftKey) = try \(typeName)(json: \(swiftKey)JSON)",
                ]
            } else {
                return [
                    "        if let \(swiftKey)JSON = json[\"\(jsonKey)\"]?.object {",
                    "            self.\(swiftKey) = try \(typeName)(json: \(swiftKey)JSON)",
                    "        } else {",
                    "            self.\(swiftKey) = nil",
                    "        }",
                ]
            }

        case .array(let element):
            return generateJSONArrayAccess(swiftKey: swiftKey, jsonKey: jsonKey, element: element, mustExist: mustExist)

        case .unsupported:
            return ["        self.\(swiftKey) = /* unsupported type, use Codable init */"]
        }
    }

    private func generateJSONArrayAccess(
        swiftKey: String, jsonKey: String, element: JSONValueAccessor, mustExist: Bool
    ) -> [String] {
        let mapBody: [String]
        switch element {
        case .scalar(let prop):
            mapBody = [
                "            guard let value = element.\(prop) else {",
                "                throw JSONObjectError.expectedObject",
                "            }",
                "            return value",
            ]
        case .enumType(let typeName, let rawProperty):
            mapBody = [
                "            guard let raw = element.\(rawProperty),",
                "                  let value = \(typeName)(rawValue: raw) else {",
                "                throw JSONObjectError.expectedObject",
                "            }",
                "            return value",
            ]
        case .nestedObject(let typeName):
            mapBody = [
                "            guard let obj = element.object else {",
                "                throw JSONObjectError.expectedObject",
                "            }",
                "            return try \(typeName)(json: obj)",
            ]
        case .array, .unsupported:
            return ["        self.\(swiftKey) = []  // nested arrays unsupported in swift-json init"]
        }

        if mustExist {
            return [
                "        guard let \(swiftKey)Array = json[\"\(jsonKey)\"]?.array else {",
                "            throw JSONObjectError.expectedObject",
                "        }",
                "        self.\(swiftKey) = try \(swiftKey)Array.map { element in",
            ] + mapBody + ["        }"]
        } else {
            return [
                "        if let \(swiftKey)Array = json[\"\(jsonKey)\"]?.array {",
                "            self.\(swiftKey) = try \(swiftKey)Array.map { element in",
            ] + mapBody.map { "    " + $0 } + [
                "            }",
                "        } else {",
                "            self.\(swiftKey) = nil",
                "        }",
            ]
        }
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
