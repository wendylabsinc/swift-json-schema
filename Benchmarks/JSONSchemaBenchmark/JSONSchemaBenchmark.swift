import Benchmark
import Foundation
import IkigaJSON

// MARK: - JSON test data (mirrors the swift-json JSONBenchmark payloads)

let smallJSONData = """
    {
        "id": 12345,
        "name": "John Doe",
        "email": "john.doe@example.com",
        "active": true
    }
    """.data(using: .utf8)!

let mediumJSONData = """
    {
        "id": 12345,
        "username": "johndoe",
        "email": "john.doe@example.com",
        "firstName": "John",
        "lastName": "Doe",
        "age": 32,
        "isActive": true,
        "createdAt": "2024-01-15T10:30:00Z",
        "roles": ["admin", "user", "moderator"],
        "settings": {
            "theme": "dark",
            "notifications": true,
            "language": "en-US"
        }
    }
    """.data(using: .utf8)!

let largeJSONData: Data = {
    let users = (0..<100).map { i in
        """
        {
            "id": \(i),
            "username": "user\(i)",
            "email": "user\(i)@example.com",
            "firstName": "First\(i)",
            "lastName": "Last\(i)",
            "age": \(20 + (i % 50)),
            "isActive": \(i % 2 == 0),
            "createdAt": "2024-01-15T10:30:00Z",
            "roles": ["user", "member"],
            "settings": {
                "theme": "light",
                "notifications": false,
                "language": "en-US"
            }
        }
        """
    }.joined(separator: ",\n")

    return """
        {
            "users": [\(users)],
            "metadata": {
                "total": 100,
                "page": 1,
                "perPage": 100,
                "totalPages": 1
            },
            "tags": ["api", "users", "export", "batch", "data"]
        }
        """.data(using: .utf8)!
}()

// Pre-parsed JSONObjects for extraction-only benchmarks
nonisolated(unsafe) let smallJSONObject = try! JSONObject(data: smallJSONData)
nonisolated(unsafe) let mediumJSONObject = try! JSONObject(data: mediumJSONData)
nonisolated(unsafe) let largeJSONObject = try! JSONObject(data: largeJSONData)

// MARK: - Benchmarks

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration = .init(
        metrics: [
            .cpuTotal,
            .wallClock,
            .throughput,
            .peakMemoryResident,
            .mallocCountTotal,
        ],
        warmupIterations: 10
    )

    // ============================================================
    // SMALL PAYLOAD
    // ============================================================

    Benchmark("Decode Small - Foundation") { benchmark in
        let decoder = JSONDecoder()
        for _ in benchmark.scaledIterations {
            blackHole(try! decoder.decode(SmallUser.self, from: smallJSONData))
        }
    }

    Benchmark("Decode Small - IkigaJSON Codable") { benchmark in
        let decoder = IkigaJSONDecoder()
        for _ in benchmark.scaledIterations {
            blackHole(try! decoder.decode(SmallUser.self, from: smallJSONData))
        }
    }

    Benchmark("Decode Small - SwiftJSON init(json:)") { benchmark in
        for _ in benchmark.scaledIterations {
            let json = try! JSONObject(data: smallJSONData)
            blackHole(try! SmallUser(json: json))
        }
    }

    Benchmark("Decode Small - SwiftJSON ObjectView") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try! SmallUser(json: smallJSONData.span))
        }
    }

    Benchmark("Extract Small - SwiftJSON init(json:) only") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try! SmallUser(json: smallJSONObject))
        }
    }

    // ============================================================
    // MEDIUM PAYLOAD
    // ============================================================

    Benchmark("Decode Medium - Foundation") { benchmark in
        let decoder = JSONDecoder()
        for _ in benchmark.scaledIterations {
            blackHole(try! decoder.decode(MediumUser.self, from: mediumJSONData))
        }
    }

    Benchmark("Decode Medium - IkigaJSON Codable") { benchmark in
        let decoder = IkigaJSONDecoder()
        for _ in benchmark.scaledIterations {
            blackHole(try! decoder.decode(MediumUser.self, from: mediumJSONData))
        }
    }

    Benchmark("Decode Medium - SwiftJSON init(json:)") { benchmark in
        for _ in benchmark.scaledIterations {
            let json = try! JSONObject(data: mediumJSONData)
            blackHole(try! MediumUser(json: json))
        }
    }

    Benchmark("Decode Medium - SwiftJSON ObjectView") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try! MediumUser(json: mediumJSONData.span))
        }
    }

    Benchmark("Extract Medium - SwiftJSON init(json:) only") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try! MediumUser(json: mediumJSONObject))
        }
    }

    // ============================================================
    // LARGE PAYLOAD (100 users)
    // ============================================================

    Benchmark("Decode Large - Foundation") { benchmark in
        let decoder = JSONDecoder()
        for _ in benchmark.scaledIterations {
            blackHole(try! decoder.decode(LargePayload.self, from: largeJSONData))
        }
    }

    Benchmark("Decode Large - IkigaJSON Codable") { benchmark in
        let decoder = IkigaJSONDecoder()
        for _ in benchmark.scaledIterations {
            blackHole(try! decoder.decode(LargePayload.self, from: largeJSONData))
        }
    }

    Benchmark("Decode Large - SwiftJSON init(json:)") { benchmark in
        for _ in benchmark.scaledIterations {
            let json = try! JSONObject(data: largeJSONData)
            blackHole(try! LargePayload(json: json))
        }
    }

    Benchmark("Decode Large - SwiftJSON ObjectView") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try! LargePayload(json: largeJSONData.span))
        }
    }

    Benchmark("Extract Large - SwiftJSON init(json:) only") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try! LargePayload(json: largeJSONObject))
        }
    }
}
