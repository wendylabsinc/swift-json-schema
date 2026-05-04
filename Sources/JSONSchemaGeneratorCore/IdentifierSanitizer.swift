public enum IdentifierSanitizer {
    public static let reservedWords: Set<String> = [
        "class", "struct", "enum", "protocol", "extension", "func", "var", "let",
        "init", "deinit", "subscript", "typealias", "import", "return", "throw",
        "throws", "rethrows", "try", "catch", "do", "if", "else", "switch", "case",
        "default", "for", "in", "while", "repeat", "break", "continue", "fallthrough",
        "where", "guard", "defer", "as", "is", "nil", "true", "false", "self", "Self",
        "super", "any", "some", "actor", "async", "await", "nonisolated", "isolated",
        "consuming", "borrowing", "copy", "discard", "open", "public", "internal",
        "fileprivate", "private", "static", "final", "lazy", "override", "required",
        "weak", "unowned", "dynamic", "optional", "prefix", "postfix", "infix",
        "operator", "precedencegroup", "associatedtype", "mutating", "nonmutating",
        "convenience", "willSet", "didSet", "get", "set", "Type", "Any",
    ]

    /// JSON property name → lowerCamelCase Swift identifier.
    public static func propertyName(from input: String, fallbackIndex: Int) -> String {
        let camel = toLowerCamelCase(input)
        if camel.isEmpty { return "_field\(fallbackIndex)" }
        if reservedWords.contains(camel) { return "`\(camel)`" }
        return camel
    }

    /// String → UpperCamelCase Swift type name.
    public static func typeName(from input: String) -> String {
        let pascal = toUpperCamelCase(input)
        if pascal.isEmpty { return "_Type" }
        return ensureStartsWithLetter(pascal)
    }

    /// Returns true when an explicit CodingKey entry is needed.
    /// Reserved-word escaping (backticks) doesn't change the underlying key.
    public static func needsCodingKey(_ jsonKey: String, swiftName: String) -> Bool {
        let plain = swiftName.hasPrefix("`") ? String(swiftName.dropFirst().dropLast()) : swiftName
        return jsonKey != plain
    }

    // MARK: - Private

    private static func toLowerCamelCase(_ input: String) -> String {
        let words = splitIntoWords(input)
        guard !words.isEmpty else { return "" }
        let result = words.enumerated().map { i, w in
            i == 0 ? w.lowercased() : w.prefix(1).uppercased() + w.dropFirst().lowercased()
        }.joined()
        return ensureStartsWithLetter(result)
    }

    private static func toUpperCamelCase(_ input: String) -> String {
        let words = splitIntoWords(input)
        guard !words.isEmpty else { return "" }
        return words.map { w in
            w.prefix(1).uppercased() + w.dropFirst().lowercased()
        }.joined()
    }

    /// Splits on separator characters and on camelCase upper→lower transitions.
    private static func splitIntoWords(_ input: String) -> [String] {
        var words: [String] = []
        var current = ""
        for char in input {
            if char.isLetter || char.isNumber {
                if char.isUppercase && !current.isEmpty {
                    words.append(current)
                    current = String(char)
                } else {
                    current.append(char)
                }
            } else {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private static func ensureStartsWithLetter(_ s: String) -> String {
        guard let first = s.first, !first.isLetter else { return s }
        return "_" + s
    }
}
