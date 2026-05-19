import Foundation
#if canImport(JSONSchemaSwiftJSON)
import JSONSchemaSwiftJSON
#endif

let inputData = FileHandle.standardInput.readDataToEndOfFile()
guard !inputData.isEmpty else {
    fputs("Error: no input\n", stderr)
    exit(1)
}

do {
    let user: User

    #if canImport(JSONSchemaSwiftJSON)
    // Non-Codable fast path: parse directly via IkigaJSON's JSONObject API.
    // Use init(json:) directly here since we have Foundation Data; the generated
    // init(_ span: Span<UInt8>) is the preferred entry point in zero-copy contexts
    // such as NIO pipelines where bytes already live in a contiguous buffer.
    user = try User(json: inputData.span)
    #else
    user = try JSONDecoder().decode(User.self, from: inputData)
    #endif

    print("id:      \(user.id)")
    print("name:    \(user.name)")
    print("email:   \(user.email)")
    print("role:    \(user.role.rawValue)")
    if let address = user.address {
        var line = "\(address.street), \(address.city)"
        if let zip = address.zipCode { line += " (zip: \(zip))" }
        print("address: \(line)")
    }
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
