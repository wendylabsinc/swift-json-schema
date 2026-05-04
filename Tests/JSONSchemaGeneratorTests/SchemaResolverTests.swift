import Testing
import Foundation
@testable import JSONSchemaGeneratorCore

@Suite struct SchemaResolverTests {
    private func schema(_ json: String) throws -> JSONSchema {
        try JSONDecoder().decode(JSONSchema.self, from: Data(json.utf8))
    }

    @Test func returnsDefsMap() throws {
        let s = try schema("""
        {"title":"Root","$defs":{"A":{"type":"string"},"B":{"type":"integer"}}}
        """)
        let resolved = try SchemaResolver.resolve(s)
        #expect(resolved.defs.count == 2)
        #expect(resolved.defs["A"]?.type == .single(.string))
        #expect(resolved.defs["B"]?.type == .single(.integer))
    }

    @Test func acceptsValidRef() throws {
        let s = try schema("""
        {"title":"Root","properties":{"x":{"$ref":"#/$defs/Item"}},"$defs":{"Item":{"type":"string"}}}
        """)
        #expect(throws: Never.self) { try SchemaResolver.resolve(s) }
    }

    @Test func throwsOnUnresolvableRef() throws {
        let s = try schema("""
        {"title":"Root","properties":{"x":{"$ref":"#/$defs/Missing"}},"$defs":{}}
        """)
        #expect(throws: ResolverError.unresolvableRef("#/$defs/Missing")) {
            try SchemaResolver.resolve(s)
        }
    }

    @Test func throwsOnUnsupportedRemoteRef() throws {
        let s = try schema("""
        {"title":"Root","properties":{"x":{"$ref":"https://example.com/schema"}}}
        """)
        #expect(throws: ResolverError.unsupportedRef("https://example.com/schema")) {
            try SchemaResolver.resolve(s)
        }
    }

    @Test func validatesRefInsideOneOf() throws {
        let s = try schema("""
        {"title":"Root","oneOf":[{"$ref":"#/$defs/Missing"}],"$defs":{}}
        """)
        #expect(throws: ResolverError.unresolvableRef("#/$defs/Missing")) {
            try SchemaResolver.resolve(s)
        }
    }

    @Test func validatesRefInDefsEntry() throws {
        let s = try schema("""
        {"title":"Root","$defs":{"A":{"$ref":"#/$defs/Missing"}}}
        """)
        #expect(throws: ResolverError.unresolvableRef("#/$defs/Missing")) {
            try SchemaResolver.resolve(s)
        }
    }

    @Test func emptyDefsIsValid() throws {
        let s = try schema(#"{"title":"Root","type":"object"}"#)
        let resolved = try SchemaResolver.resolve(s)
        #expect(resolved.defs.isEmpty)
    }
}
