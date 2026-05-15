# swift-json-schema

A SwiftPM build tool plugin that generates `Codable` Swift types from `.schema.json` files (JSON Schema Draft 2020-12) at compile time.

## Usage

Add the package as a dependency and apply `JSONSchemaPlugin` to any target:

```swift
.package(url: "https://github.com/wendylabsinc/swift-json-schema.git", from: "0.1.0"),

.target(
    name: "MyTarget",
    plugins: [.plugin(name: "JSONSchemaPlugin", package: "swift-json-schema")]
)
```

Any `.schema.json` file in the target's sources is automatically processed. Each file produces a `.swift` file containing all generated types.

See [`Examples/UserDecoder/`](Examples/UserDecoder/) for a working end-to-end example.

---

## Supported JSON Schema keywords

### `title`

**Required on the root schema.** Used as the Swift type name. Converted to UpperCamelCase.

```json
{ "title": "UserProfile" }
```

```swift
struct UserProfile: Codable, Hashable { ... }
```

`$defs` entries are named from their key, not their `title`.

---

### `description`

Emitted as a Swift doc comment on the generated type.

```json
{ "title": "User", "description": "A registered user" }
```

```swift
/// A registered user
struct User: Codable { ... }
```

---

### `type` (scalar and nullable)

| JSON Schema | Swift |
|---|---|
| `"string"` | `String` |
| `"integer"` | `Int` |
| `"number"` | `Double` |
| `"boolean"` | `Bool` |
| `"array"` | `[T]` (element type from `items`) |
| `["T", "null"]` | `T?` |

```json
{ "type": ["string", "null"] }
```

```swift
var name: String?
```

---

### `properties` and `required`

Each entry in `properties` becomes a struct field. Properties listed in `required` use `let`; all others use `var` and are made optional.

```json
{
  "title": "Point",
  "type": "object",
  "properties": {
    "x": { "type": "number" },
    "y": { "type": "number" },
    "label": { "type": "string" }
  },
  "required": ["x", "y"]
}
```

```swift
struct Point: Codable, Hashable {
    var label: String?
    let x: Double
    let y: Double
}
```

Properties are sorted alphabetically in the generated output.

---

### `items`

Specifies the element type of an `"array"` property. The element can be a primitive type or a `$ref`.

```json
{ "type": "array", "items": { "type": "string" } }
```

```swift
[String]
```

```json
{ "type": "array", "items": { "$ref": "#/$defs/Product" } }
```

```swift
[Product]
```

---

### `minItems`, `maxItems`, `uniqueItems`

Validated at decode time. When any property carries these constraints, the generator emits a custom `init(from:)` that throws `DecodingError.dataCorrupted` on violation.

| Keyword | Validates |
|---|---|
| `minItems: N` | `array.count >= N` |
| `maxItems: N` | `array.count <= N` |
| `uniqueItems: true` | all elements are distinct |

Optional array properties (not in `required`) are only validated when present.

```json
{
  "title": "Playlist",
  "type": "object",
  "properties": {
    "tags": { "type": "array", "items": { "type": "string" }, "minItems": 1, "maxItems": 10, "uniqueItems": true }
  },
  "required": ["tags"]
}
```

```swift
struct Playlist: Codable, Hashable {
    let tags: [String]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tags = try container.decode([String].self, forKey: .tags)
        guard tags.count >= 1 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "tags: expected at least 1 item"))
        }
        guard tags.count <= 10 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "tags: expected at most 10 items"))
        }
        guard Set(tags).count == tags.count else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "tags: items must be unique"))
        }
        self.tags = tags
    }

    enum CodingKeys: String, CodingKey {
        case tags
    }
}
```

---

### `enum`

Generates a `String` or `Int` backed Swift enum. All values must be the same type (all strings or all integers).

```json
{ "title": "Direction", "enum": ["north", "south", "east", "west"] }
```

```swift
enum Direction: String, Codable, Hashable {
    case east = "east"
    case north = "north"
    case south = "south"
    case west = "west"
}
```

Integer case names are auto-generated as `value0`, `value1`, … (negative: `valueNeg1`, `valueNeg2`, …).

---

### `oneOf` / `anyOf`

Generates a Swift `enum` with associated values and a custom `Codable` implementation. Decoding tries each variant in order.

```json
{
  "title": "Shape",
  "oneOf": [
    { "$ref": "#/$defs/Circle" },
    { "$ref": "#/$defs/Rectangle" }
  ]
}
```

```swift
enum Shape: Codable, Hashable {
    case circle(Circle)
    case rectangle(Rectangle)

    init(from decoder: any Decoder) throws {
        if let value = try? Circle(from: decoder) {
            self = .circle(value)
        } else if let value = try? Rectangle(from: decoder) {
            self = .rectangle(value)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "No variant matched")
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .circle(let value): try value.encode(to: encoder)
        case .rectangle(let value): try value.encode(to: encoder)
        }
    }
}
```

`anyOf` is handled identically to `oneOf`.

Variant names are derived from `$ref` keys or the variant's `title`. Variants with neither get a fallback name (`case1`, `case2`, …).

---

### `$defs` and `$ref`

`$defs` entries are each generated as a named Swift type (using the entry key as the type name), emitted before the root type.

`$ref` must point to a local `$defs` entry using the `#/$defs/<name>` format. The referenced name becomes the Swift type.

```json
{
  "title": "Order",
  "properties": {
    "item": { "$ref": "#/$defs/Item" }
  },
  "$defs": {
    "Item": { "type": "object", "properties": { "id": { "type": "integer" } } }
  }
}
```

```swift
struct Item: Codable, Hashable {
    var id: Int?
}

struct Order: Codable, Hashable {
    var item: Item?
}
```

---

### Identifier sanitization

JSON property names are converted to lowerCamelCase Swift identifiers. When the JSON name and Swift name differ, a `CodingKeys` enum is emitted automatically.

```json
{ "properties": { "first-name": { "type": "string" }, "APIKey": { "type": "string" } } }
```

```swift
var apiKey: String?
var firstName: String?

enum CodingKeys: String, CodingKey {
    case apiKey = "APIKey"
    case firstName = "first-name"
}
```

Swift reserved words are escaped with backticks (e.g. `class` → `` `class` ``). Since the underlying key is unchanged, no `CodingKeys` entry is needed.

---

## Unsupported keywords

The following keywords are **read and parsed** but produce no effect on generated output — they are silently ignored:

- **Combining:** `allOf`, `not`, `if`, `then`, `else`
- **String validation:** `pattern`, `format`, `minLength`, `maxLength`
- **Number validation:** `minimum`, `maximum`, `exclusiveMinimum`, `exclusiveMaximum`, `multipleOf`
- **Object validation:** `minProperties`, `maxProperties`, `additionalProperties`, `patternProperties`, `unevaluatedProperties`
- **Metadata:** `$schema`, `$id`, `$anchor`, `$comment`, `default`, `examples`, `deprecated`, `readOnly`, `writeOnly`
- **Content:** `const`, `contentEncoding`, `contentMediaType`, `contentSchema`

---

## Errors

The generator throws when it cannot produce valid, compilable Swift code.

| Error | Cause |
|---|---|
| `GeneratorError.missingTitle` | Root schema has no `title` keyword |
| `GeneratorError.unsupportedPropertyType(property:context:)` | A property's type cannot be expressed as a `Codable` Swift type — see below |
| `ResolverError.unsupportedRef(String)` | A `$ref` value is not in `#/$defs/<name>` format (e.g. a remote URL) |
| `ResolverError.unresolvableRef(String)` | A `$ref` points to a `$defs` key that does not exist |

### What causes `unsupportedPropertyType`

| Schema | Reason |
|---|---|
| `{ "type": "object" }` (no `$ref`) | Inline objects must be defined in `$defs` and referenced via `$ref` |
| `{}` (no `type`, no `$ref`) | Cannot infer a concrete Swift type |
| `{ "type": ["string", "integer"] }` | Multiple non-null types have no single Swift equivalent |
| `{ "type": "array" }` (no `items`) | Element type unknown — add `"items"` with a concrete type or `$ref` |

**Fix:** Move the inline object to `$defs` and reference it with `$ref`, or use a concrete scalar type.
