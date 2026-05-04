import Testing
import Foundation
@testable import JSONSchemaGeneratorCore

@Suite struct SchemaParsingTests {
    private func decode(_ json: String) throws -> JSONSchema {
        try JSONDecoder().decode(JSONSchema.self, from: Data(json.utf8))
    }

    @Test func parsesTitle() throws {
        #expect(try decode(#"{"title":"Person"}"#).title == "Person")
    }

    @Test func parsesSingleType() throws {
        #expect(try decode(#"{"type":"string"}"#).type == .single(.string))
    }

    @Test func parsesTypeArray() throws {
        #expect(try decode(#"{"type":["string","null"]}"#).type == .array([.string, .null]))
    }

    @Test func parsesProperties() throws {
        let s = try decode(#"{"properties":{"name":{"type":"string"}}}"#)
        #expect(s.properties?["name"]?.type == .single(.string))
    }

    @Test func parsesRequired() throws {
        #expect(try decode(#"{"required":["name","age"]}"#).required == ["name", "age"])
    }

    @Test func parsesItems() throws {
        #expect(try decode(#"{"items":{"type":"integer"}}"#).items?.type == .single(.integer))
    }

    @Test func parsesStringEnumValues() throws {
        #expect(try decode(#"{"enum":["a","b"]}"#).enumValues == [.string("a"), .string("b")])
    }

    @Test func parsesIntegerEnumValues() throws {
        #expect(try decode(#"{"enum":[1,2]}"#).enumValues == [.integer(1), .integer(2)])
    }

    @Test func parsesOneOf() throws {
        #expect(try decode(#"{"oneOf":[{"type":"string"}]}"#).oneOf?.first?.type == .single(.string))
    }

    @Test func parsesAnyOf() throws {
        #expect(try decode(#"{"anyOf":[{"type":"boolean"}]}"#).anyOf?.first?.type == .single(.boolean))
    }

    @Test func parsesDefs() throws {
        let s = try decode(#"{"$defs":{"Foo":{"type":"number"}}}"#)
        #expect(s.defs?["Foo"]?.type == .single(.number))
    }

    @Test func parsesRef() throws {
        let json = "{\"$ref\":\"#/$defs/Foo\"}"
        #expect(try decode(json).ref == "#/$defs/Foo")
    }

    @Test func parsesDescription() throws {
        #expect(try decode(#"{"description":"A person"}"#).description == "A person")
    }

    @Test func parsesMinItems() throws {
        #expect(try decode(#"{"minItems":2}"#).minItems == 2)
    }

    @Test func parsesMaxItems() throws {
        #expect(try decode(#"{"maxItems":10}"#).maxItems == 10)
    }

    @Test func parsesUniqueItems() throws {
        #expect(try decode(#"{"uniqueItems":true}"#).uniqueItems == true)
    }
}
