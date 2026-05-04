import Testing
import Foundation
@testable import JSONSchemaGeneratorCore

@Suite struct CodeGeneratorTests {
    private func generate(_ json: String) throws -> String {
        let schema = try JSONDecoder().decode(JSONSchema.self, from: Data(json.utf8))
        let resolved = try SchemaResolver.resolve(schema)
        return try CodeGenerator(resolved: resolved).generate()
    }

    // MARK: - Error paths

    @Test func throwsOnMissingTitle() throws {
        #expect(throws: CodeGenerator.GeneratorError.missingTitle) {
            try generate(#"{"type":"object"}"#)
        }
    }

    // MARK: - Error paths for unsupported types

    @Test func throwsOnObjectTypeProperty() throws {
        #expect(throws: CodeGenerator.GeneratorError.self) {
            try generate("""
            {"title":"Box","type":"object","properties":{"data":{"type":"object"}},"required":["data"]}
            """)
        }
    }

    @Test func throwsOnUntypedProperty() throws {
        #expect(throws: CodeGenerator.GeneratorError.self) {
            try generate("""
            {"title":"Box","type":"object","properties":{"data":{}},"required":["data"]}
            """)
        }
    }

    // MARK: - Struct basics

    @Test func generatesStruct() throws {
        let out = try generate("""
        {"title":"Person","type":"object","properties":{"name":{"type":"string"}},"required":["name"]}
        """)
        #expect(out.contains("struct Person: Codable, Hashable {"))
        #expect(out.contains("let name: String"))
    }

    @Test func optionalPropertyUsesVar() throws {
        let out = try generate("""
        {"title":"Foo","type":"object","properties":{"age":{"type":"integer"}}}
        """)
        #expect(out.contains("var age: Int?"))
    }

    @Test func emitsDocComment() throws {
        let out = try generate("""
        {"title":"Foo","description":"A foo type","type":"object"}
        """)
        #expect(out.contains("/// A foo type"))
    }

    @Test func emptyObjectGeneratesEmptyStruct() throws {
        let out = try generate(#"{"title":"Empty","type":"object"}"#)
        #expect(out.contains("struct Empty: Codable, Hashable {"))
        #expect(out.contains("}"))
    }

    // MARK: - Primitive type mapping

    @Test func stringType() throws {
        let out = try generate("""
        {"title":"T","type":"object","properties":{"x":{"type":"string"}},"required":["x"]}
        """)
        #expect(out.contains("let x: String"))
    }

    @Test func integerType() throws {
        let out = try generate("""
        {"title":"T","type":"object","properties":{"x":{"type":"integer"}},"required":["x"]}
        """)
        #expect(out.contains("let x: Int"))
    }

    @Test func numberType() throws {
        let out = try generate("""
        {"title":"T","type":"object","properties":{"x":{"type":"number"}},"required":["x"]}
        """)
        #expect(out.contains("let x: Double"))
    }

    @Test func booleanType() throws {
        let out = try generate("""
        {"title":"T","type":"object","properties":{"x":{"type":"boolean"}},"required":["x"]}
        """)
        #expect(out.contains("let x: Bool"))
    }

    @Test func arrayOfStringType() throws {
        let out = try generate("""
        {"title":"T","type":"object","properties":{"tags":{"type":"array","items":{"type":"string"}}},"required":["tags"]}
        """)
        #expect(out.contains("let tags: [String]"))
    }

    @Test func optionalArrayType() throws {
        let out = try generate("""
        {"title":"T","type":"object","properties":{"tags":{"type":"array","items":{"type":"string"}}}}
        """)
        #expect(out.contains("var tags: [String]?"))
    }

    @Test func arrayOfRefType() throws {
        let out = try generate("""
        {
          "title":"Order","type":"object",
          "properties":{"items":{"type":"array","items":{"$ref":"#/$defs/Product"}}},
          "required":["items"],
          "$defs":{"Product":{"type":"object","properties":{"id":{"type":"integer"}}}}
        }
        """)
        #expect(out.contains("let items: [Product]"))
    }

    @Test func typeArrayWithNullBecomesOptional() throws {
        let out = try generate("""
        {"title":"T","type":"object","properties":{"name":{"type":["string","null"]}},"required":["name"]}
        """)
        #expect(out.contains("let name: String?"))
    }

    @Test func typeArrayWithNullAndAlreadyOptionalProperty() throws {
        // Property not in required AND type includes null — should produce String? not String??
        let out = try generate("""
        {"title":"T","type":"object","properties":{"name":{"type":["string","null"]}}}
        """)
        #expect(out.contains("var name: String?"))
        #expect(!out.contains("String??"))
    }

    @Test func refPropertyUsesDefTypeName() throws {
        let out = try generate("""
        {
          "title":"Order","type":"object",
          "properties":{"item":{"$ref":"#/$defs/Item"}},
          "required":["item"],
          "$defs":{"Item":{"type":"object","properties":{"id":{"type":"integer"}}}}
        }
        """)
        #expect(out.contains("let item: Item"))
    }

    // MARK: - $defs ordering

    @Test func defsEmittedBeforeRootType() throws {
        let out = try generate("""
        {
          "title":"Root","type":"object",
          "properties":{"x":{"$ref":"#/$defs/Child"}},
          "$defs":{"Child":{"type":"object","properties":{"id":{"type":"integer"}}}}
        }
        """)
        let childPos = out.range(of: "struct Child")!.lowerBound
        let rootPos = out.range(of: "struct Root")!.lowerBound
        #expect(childPos < rootPos)
    }

    // MARK: - CodingKeys

    @Test func emitsCodingKeysForKebabCase() throws {
        let out = try generate("""
        {"title":"Foo","type":"object","properties":{"user-name":{"type":"string"}}}
        """)
        #expect(out.contains("enum CodingKeys: String, CodingKey {"))
        #expect(out.contains(#"case userName = "user-name""#))
    }

    @Test func omitsCodingKeysWhenAllNamesMatch() throws {
        let out = try generate("""
        {"title":"Foo","type":"object","properties":{"name":{"type":"string"},"age":{"type":"integer"}}}
        """)
        #expect(!out.contains("CodingKeys"))
    }

    @Test func codingKeysIncludesAllPropertiesWhenNeeded() throws {
        // When CodingKeys is emitted it must list ALL properties, not just the renamed one
        let out = try generate("""
        {"title":"Foo","type":"object","properties":{"name":{"type":"string"},"user-id":{"type":"integer"}}}
        """)
        #expect(out.contains("case name"))
        #expect(out.contains(#"case userId = "user-id""#))
    }

    @Test func escapesReservedWordInCodingKeys() throws {
        let out = try generate("""
        {"title":"Foo","type":"object","properties":{"class":{"type":"string"}}}
        """)
        // "class" property: swiftKey = "`class`", json key = "class" — names match, no CodingKeys
        #expect(!out.contains("CodingKeys"))
        #expect(out.contains("var `class`: String?"))
    }

    // MARK: - enum keyword

    @Test func generatesStringEnum() throws {
        let out = try generate("""
        {"title":"Status","enum":["active","inactive","pending"]}
        """)
        #expect(out.contains("enum Status: String, Codable, Hashable {"))
        #expect(out.contains(#"case active = "active""#))
        #expect(out.contains(#"case inactive = "inactive""#))
        #expect(out.contains(#"case pending = "pending""#))
    }

    @Test func generatesIntegerEnum() throws {
        let out = try generate("""
        {"title":"Priority","enum":[1,2,3]}
        """)
        #expect(out.contains("enum Priority: Int, Codable, Hashable {"))
        #expect(out.contains("case value1 = 1"))
        #expect(out.contains("case value2 = 2"))
    }

    // MARK: - oneOf / anyOf

    @Test func generatesOneOfEnum() throws {
        let out = try generate("""
        {
          "title":"Shape",
          "oneOf":[{"$ref":"#/$defs/Circle"},{"$ref":"#/$defs/Rectangle"}],
          "$defs":{
            "Circle":{"type":"object","properties":{"radius":{"type":"number"}}},
            "Rectangle":{"type":"object","properties":{"width":{"type":"number"}}}
          }
        }
        """)
        #expect(out.contains("enum Shape: Codable, Hashable {"))
        #expect(out.contains("case circle(Circle)"))
        #expect(out.contains("case rectangle(Rectangle)"))
        #expect(out.contains("init(from decoder: any Decoder) throws {"))
        #expect(out.contains("func encode(to encoder: any Encoder) throws {"))
    }

    @Test func oneOfCustomDecoderTriesEachVariant() throws {
        let out = try generate("""
        {
          "title":"Union",
          "oneOf":[{"$ref":"#/$defs/A"},{"$ref":"#/$defs/B"}],
          "$defs":{
            "A":{"type":"object","properties":{"x":{"type":"string"}}},
            "B":{"type":"object","properties":{"y":{"type":"integer"}}}
          }
        }
        """)
        #expect(out.contains("try? A(from: decoder)"))
        #expect(out.contains("try? B(from: decoder)"))
        #expect(out.contains("No variant matched"))
    }

    @Test func anyOfGeneratesEnum() throws {
        let out = try generate("""
        {
          "title":"Result",
          "anyOf":[{"$ref":"#/$defs/Ok"},{"$ref":"#/$defs/Err"}],
          "$defs":{
            "Ok":{"type":"object","properties":{"value":{"type":"string"}}},
            "Err":{"type":"object","properties":{"message":{"type":"string"}}}
          }
        }
        """)
        #expect(out.contains("enum Result: Codable, Hashable {"))
        #expect(out.contains("case ok(Ok)"))
        #expect(out.contains("case err(Err)"))
    }

    // MARK: - Hashable conformance

    @Test func structIsHashable() throws {
        let out = try generate(#"{"title":"Foo","type":"object","properties":{"name":{"type":"string"}}}"#)
        #expect(out.contains("struct Foo: Codable, Hashable {"))
    }

    @Test func stringEnumIsHashable() throws {
        let out = try generate(#"{"title":"Status","enum":["active","inactive"]}"#)
        #expect(out.contains("enum Status: String, Codable, Hashable {"))
    }

    @Test func intEnumIsHashable() throws {
        let out = try generate(#"{"title":"Priority","enum":[1,2,3]}"#)
        #expect(out.contains("enum Priority: Int, Codable, Hashable {"))
    }

    @Test func unionEnumIsHashable() throws {
        let out = try generate("""
        {
          "title":"Shape",
          "oneOf":[{"$ref":"#/$defs/Circle"},{"$ref":"#/$defs/Square"}],
          "$defs":{
            "Circle":{"type":"object","properties":{"r":{"type":"number"}}},
            "Square":{"type":"object","properties":{"s":{"type":"number"}}}
          }
        }
        """)
        #expect(out.contains("enum Shape: Codable, Hashable {"))
        #expect(out.contains("struct Circle: Codable, Hashable {"))
        #expect(out.contains("struct Square: Codable, Hashable {"))
    }

    // MARK: - Array validation

    @Test func minItemsGeneratesCustomInit() throws {
        let out = try generate("""
        {
          "title":"Playlist","type":"object",
          "properties":{"tags":{"type":"array","items":{"type":"string"},"minItems":1}},
          "required":["tags"]
        }
        """)
        #expect(out.contains("init(from decoder: any Decoder) throws {"))
        #expect(out.contains("guard tags.count >= 1 else {"))
        #expect(out.contains("tags: expected at least 1 item"))
    }

    @Test func maxItemsGeneratesCustomInit() throws {
        let out = try generate("""
        {
          "title":"Playlist","type":"object",
          "properties":{"tags":{"type":"array","items":{"type":"string"},"maxItems":5}},
          "required":["tags"]
        }
        """)
        #expect(out.contains("guard tags.count <= 5 else {"))
        #expect(out.contains("tags: expected at most 5 items"))
    }

    @Test func uniqueItemsGeneratesCustomInit() throws {
        let out = try generate("""
        {
          "title":"Playlist","type":"object",
          "properties":{"tags":{"type":"array","items":{"type":"string"},"uniqueItems":true}},
          "required":["tags"]
        }
        """)
        #expect(out.contains("guard Set(tags).count == tags.count else {"))
        #expect(out.contains("tags: items must be unique"))
    }

    @Test func allThreeConstraintsCombined() throws {
        let out = try generate("""
        {
          "title":"Playlist","type":"object",
          "properties":{"tags":{"type":"array","items":{"type":"string"},"minItems":1,"maxItems":10,"uniqueItems":true}},
          "required":["tags"]
        }
        """)
        #expect(out.contains("guard tags.count >= 1 else {"))
        #expect(out.contains("guard tags.count <= 10 else {"))
        #expect(out.contains("guard Set(tags).count == tags.count else {"))
    }

    @Test func optionalConstrainedArrayWrappedInIfLet() throws {
        let out = try generate("""
        {
          "title":"Playlist","type":"object",
          "properties":{"tags":{"type":"array","items":{"type":"string"},"minItems":1}}
        }
        """)
        #expect(out.contains("if let tags {"))
        #expect(out.contains("guard tags.count >= 1 else {"))
    }

    @Test func unconstrainedStructHasNoCustomInit() throws {
        let out = try generate("""
        {"title":"Foo","type":"object","properties":{"name":{"type":"string"}}}
        """)
        #expect(!out.contains("init(from decoder"))
    }

    @Test func mixedStructDecodesAllPropertiesInInit() throws {
        let out = try generate("""
        {
          "title":"Order","type":"object",
          "properties":{
            "id":{"type":"integer"},
            "items":{"type":"array","items":{"type":"string"},"minItems":1}
          },
          "required":["id","items"]
        }
        """)
        #expect(out.contains("let id = try container.decode(Int.self, forKey: .id)"))
        #expect(out.contains("let items = try container.decode([String].self, forKey: .items)"))
        #expect(out.contains("self.id = id"))
        #expect(out.contains("self.items = items"))
    }

    @Test func customInitAlwaysEmitsCodingKeys() throws {
        let out = try generate("""
        {
          "title":"Bag","type":"object",
          "properties":{"items":{"type":"array","items":{"type":"string"},"minItems":1}},
          "required":["items"]
        }
        """)
        #expect(out.contains("enum CodingKeys: String, CodingKey {"))
        #expect(out.contains("case items"))
    }

    @Test func renamedKeyPlusConstrainedArrayInSameStruct() throws {
        // struct with a renamed property AND an array constraint — exercises
        // needsCodingKeys + needsCustomInit in combination
        let out = try generate("""
        {
          "title":"Foo","type":"object",
          "properties":{
            "user-name":{"type":"string"},
            "tags":{"type":"array","items":{"type":"string"},"minItems":1}
          },
          "required":["tags"]
        }
        """)
        #expect(out.contains("init(from decoder: any Decoder) throws {"))
        #expect(out.contains("enum CodingKeys: String, CodingKey {"))
        #expect(out.contains(#"case userName = "user-name""#))
        #expect(out.contains("let tags = try container.decode([String].self, forKey: .tags)"))
        #expect(out.contains("guard tags.count >= 1 else {"))
    }

    @Test func optionalConstrainedArrayWithMaxItemsWrappedInIfLet() throws {
        let out = try generate("""
        {
          "title":"Foo","type":"object",
          "properties":{"tags":{"type":"array","items":{"type":"string"},"maxItems":5}}
        }
        """)
        #expect(out.contains("if let tags {"))
        #expect(out.contains("guard tags.count <= 5 else {"))
    }

    @Test func minItemsOneUsesItemSingular() throws {
        let out = try generate("""
        {
          "title":"Foo","type":"object",
          "properties":{"items":{"type":"array","items":{"type":"string"},"minItems":1}},
          "required":["items"]
        }
        """)
        #expect(out.contains("expected at least 1 item\""))
        #expect(!out.contains("expected at least 1 items\""))
    }
}
