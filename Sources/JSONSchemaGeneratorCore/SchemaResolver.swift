public struct ResolvedSchema: Sendable {
    public let root: JSONSchema
    public let defs: [String: JSONSchema]

    public init(root: JSONSchema, defs: [String: JSONSchema]) {
        self.root = root
        self.defs = defs
    }
}

public enum ResolverError: Error, Equatable, Sendable {
    case unsupportedRef(String)
    case unresolvableRef(String)
}

public struct SchemaResolver {
    public static func resolve(_ schema: JSONSchema) throws -> ResolvedSchema {
        let defs = schema.defs ?? [:]
        try validateRefs(in: schema, defs: defs)
        for (_, def) in defs {
            try validateRefs(in: def, defs: defs)
        }
        return ResolvedSchema(root: schema, defs: defs)
    }

    private static func validateRefs(in schema: JSONSchema, defs: [String: JSONSchema]) throws {
        if let ref = schema.ref {
            guard ref.hasPrefix("#/$defs/") else {
                throw ResolverError.unsupportedRef(ref)
            }
            let name = String(ref.dropFirst("#/$defs/".count))
            guard defs[name] != nil else {
                throw ResolverError.unresolvableRef(ref)
            }
        }
        for (_, prop) in schema.properties ?? [:] {
            try validateRefs(in: prop, defs: defs)
        }
        if let items = schema.items {
            try validateRefs(in: items, defs: defs)
        }
        for sub in (schema.oneOf ?? []) + (schema.anyOf ?? []) {
            try validateRefs(in: sub, defs: defs)
        }
    }
}
