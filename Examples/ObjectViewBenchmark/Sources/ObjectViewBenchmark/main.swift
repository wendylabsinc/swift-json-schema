import Foundation
import IkigaJSON

let orderJSON = """
{
    "orderId": 98765,
    "status": "confirmed",
    "customerId": 42,
    "createdAt": "2024-03-15T09:22:00Z",
    "total": 149.97,
    "currency": "USD",
    "items": [
        {
            "productId": 1001,
            "sku": "WIDGET-A",
            "name": "Premium Widget",
            "quantity": 2,
            "unitPrice": 49.99
        },
        {
            "productId": 1042,
            "sku": "GADGET-B",
            "name": "Compact Gadget",
            "quantity": 1,
            "unitPrice": 49.99
        }
    ],
    "shipping": {
        "name": "Jane Smith",
        "street": "123 Main St",
        "city": "Springfield",
        "postalCode": "12345",
        "country": "US"
    },
    "notes": "Leave at door"
}
""".data(using: .utf8)!

let iterations = 100_000

func measure(_ label: String, _ block: () -> Void) {
    // Warmup
    for _ in 0..<1_000 { block() }

    let start = Date()
    for _ in 0..<iterations { block() }
    let elapsed = Date().timeIntervalSince(start)

    let perOp = elapsed / Double(iterations) * 1_000_000_000 // ns
    let throughput = Double(iterations) / elapsed
    let padded = label.padding(toLength: 38, withPad: " ", startingAt: 0)
    print(String(format: "  %@ %8.0f ns/op   %8.0f ops/sec", padded, perOp, throughput))
}

print("Parsing \(iterations) orders\n")

let decoder = JSONDecoder()
measure("Foundation JSONDecoder") {
    _ = try! decoder.decode(Order.self, from: orderJSON)
}

let ikigaDecoder = IkigaJSONDecoder()
measure("IkigaJSON Codable") {
    _ = try! ikigaDecoder.decode(Order.self, from: orderJSON)
}

measure("SwiftJSON JSONObject + init(json:)") {
    let obj = try! JSONObject(data: orderJSON)
    _ = try! Order(json: obj)
}

measure("SwiftJSON ObjectView (zero-copy)") {
    _ = try! Order(json: orderJSON.span)
}
