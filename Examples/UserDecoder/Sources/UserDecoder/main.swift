import Foundation

let inputData = FileHandle.standardInput.readDataToEndOfFile()
guard !inputData.isEmpty else {
    fputs("Error: no input\n", stderr)
    exit(1)
}

do {
    let user = try JSONDecoder().decode(User.self, from: inputData)
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
