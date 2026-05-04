import Testing
@testable import JSONSchemaGeneratorCore

@Suite struct IdentifierSanitizerTests {

    // MARK: - propertyName

    @Test func preservesCamelCase() {
        #expect(IdentifierSanitizer.propertyName(from: "firstName", fallbackIndex: 0) == "firstName")
    }

    @Test func convertsSnakeCase() {
        #expect(IdentifierSanitizer.propertyName(from: "user_name", fallbackIndex: 0) == "userName")
    }

    @Test func convertsKebabCase() {
        #expect(IdentifierSanitizer.propertyName(from: "user-name", fallbackIndex: 0) == "userName")
    }

    @Test func lowercasesFirstLetterOfPascalCase() {
        #expect(IdentifierSanitizer.propertyName(from: "UserName", fallbackIndex: 0) == "userName")
    }

    @Test func escapesReservedWordClass() {
        #expect(IdentifierSanitizer.propertyName(from: "class", fallbackIndex: 0) == "`class`")
    }

    @Test func escapesReservedWordIn() {
        #expect(IdentifierSanitizer.propertyName(from: "in", fallbackIndex: 0) == "`in`")
    }

    @Test func prefixesLeadingDigit() {
        #expect(IdentifierSanitizer.propertyName(from: "123field", fallbackIndex: 0) == "_123field")
    }

    @Test func fallsBackWhenAllSeparators() {
        #expect(IdentifierSanitizer.propertyName(from: "---", fallbackIndex: 3) == "_field3")
    }

    // MARK: - typeName

    @Test func typeNameIsPascalCaseFromSnake() {
        #expect(IdentifierSanitizer.typeName(from: "user_profile") == "UserProfile")
    }

    @Test func typeNameIsPascalCaseFromCamel() {
        #expect(IdentifierSanitizer.typeName(from: "userProfile") == "UserProfile")
    }

    @Test func typeNamePreservesAlreadyPascal() {
        #expect(IdentifierSanitizer.typeName(from: "UserProfile") == "UserProfile")
    }

    // MARK: - needsCodingKey

    @Test func needsCodingKeyForKebab() {
        let swift = IdentifierSanitizer.propertyName(from: "user-name", fallbackIndex: 0)
        #expect(IdentifierSanitizer.needsCodingKey("user-name", swiftName: swift))
    }

    @Test func doesNotNeedCodingKeyForIdentical() {
        let swift = IdentifierSanitizer.propertyName(from: "name", fallbackIndex: 0)
        #expect(!IdentifierSanitizer.needsCodingKey("name", swiftName: swift))
    }

    @Test func doesNotNeedCodingKeyForReservedWord() {
        // JSON key "class" → Swift "`class`"; underlying name is the same
        let swift = IdentifierSanitizer.propertyName(from: "class", fallbackIndex: 0)
        #expect(!IdentifierSanitizer.needsCodingKey("class", swiftName: swift))
    }
}
