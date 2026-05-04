import Foundation

public struct JSONSchema: Decodable, Sendable {
    private final class _Storage: @unchecked Sendable {
        let title: String?
        let description: String?
        let type: SchemaType?
        let properties: [String: JSONSchema]?
        let required: [String]?
        let items: JSONSchema?
        let enumValues: [JSONSchemaValue]?
        let oneOf: [JSONSchema]?
        let anyOf: [JSONSchema]?
        let defs: [String: JSONSchema]?
        let ref: String?
        let minItems: Int?
        let maxItems: Int?
        let uniqueItems: Bool?

        init(
            title: String?, description: String?, type: SchemaType?,
            properties: [String: JSONSchema]?, required: [String]?,
            items: JSONSchema?, enumValues: [JSONSchemaValue]?,
            oneOf: [JSONSchema]?, anyOf: [JSONSchema]?,
            defs: [String: JSONSchema]?, ref: String?,
            minItems: Int?, maxItems: Int?, uniqueItems: Bool?
        ) {
            self.title = title; self.description = description; self.type = type
            self.properties = properties; self.required = required; self.items = items
            self.enumValues = enumValues; self.oneOf = oneOf; self.anyOf = anyOf
            self.defs = defs; self.ref = ref
            self.minItems = minItems; self.maxItems = maxItems; self.uniqueItems = uniqueItems
        }
    }

    private let storage: _Storage

    public var title: String? { storage.title }
    public var description: String? { storage.description }
    public var type: SchemaType? { storage.type }
    public var properties: [String: JSONSchema]? { storage.properties }
    public var required: [String]? { storage.required }
    public var items: JSONSchema? { storage.items }
    public var enumValues: [JSONSchemaValue]? { storage.enumValues }
    public var oneOf: [JSONSchema]? { storage.oneOf }
    public var anyOf: [JSONSchema]? { storage.anyOf }
    public var defs: [String: JSONSchema]? { storage.defs }
    public var ref: String? { storage.ref }
    public var minItems: Int? { storage.minItems }
    public var maxItems: Int? { storage.maxItems }
    public var uniqueItems: Bool? { storage.uniqueItems }

    public enum CodingKeys: String, CodingKey {
        case title, description, type, properties, required, items
        case enumValues = "enum"
        case oneOf, anyOf
        case defs = "$defs"
        case ref = "$ref"
        case minItems, maxItems, uniqueItems
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        storage = _Storage(
            title: try c.decodeIfPresent(String.self, forKey: .title),
            description: try c.decodeIfPresent(String.self, forKey: .description),
            type: try c.decodeIfPresent(SchemaType.self, forKey: .type),
            properties: try c.decodeIfPresent([String: JSONSchema].self, forKey: .properties),
            required: try c.decodeIfPresent([String].self, forKey: .required),
            items: try c.decodeIfPresent(JSONSchema.self, forKey: .items),
            enumValues: try c.decodeIfPresent([JSONSchemaValue].self, forKey: .enumValues),
            oneOf: try c.decodeIfPresent([JSONSchema].self, forKey: .oneOf),
            anyOf: try c.decodeIfPresent([JSONSchema].self, forKey: .anyOf),
            defs: try c.decodeIfPresent([String: JSONSchema].self, forKey: .defs),
            ref: try c.decodeIfPresent(String.self, forKey: .ref),
            minItems: try c.decodeIfPresent(Int.self, forKey: .minItems),
            maxItems: try c.decodeIfPresent(Int.self, forKey: .maxItems),
            uniqueItems: try c.decodeIfPresent(Bool.self, forKey: .uniqueItems)
        )
    }
}

public enum SchemaType: Decodable, Equatable, Sendable {
    case single(PrimitiveType)
    case array([PrimitiveType])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(PrimitiveType.self) {
            self = .single(single)
        } else {
            self = .array(try container.decode([PrimitiveType].self))
        }
    }
}

public enum PrimitiveType: String, Decodable, Equatable, Sendable {
    case string, integer, number, boolean, array, object, null
}

public enum JSONSchemaValue: Decodable, Equatable, Sendable {
    case string(String)
    case integer(Int)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            self = .integer(try container.decode(Int.self))
        }
    }
}
