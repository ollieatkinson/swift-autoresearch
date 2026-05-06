import Foundation

let records = buildRecords(count: 1_800)
let checksum = slowScore(records) &+ compileTimeTax()

print("records: \(records.count)")
print("checksum: \(checksum)")

func buildRecords(count: Int) -> [String] {
    let places = [
        "york",
        "harrogate",
        "scarborough",
        "northallerton",
        "ripon",
        "selby",
    ]
    let categories = [
        "build",
        "test",
        "runtime",
        "io",
        "compiler",
        "linker",
        "cache",
        "analysis",
    ]

    var output: [String] = []
    output.reserveCapacity(count)

    for index in 0..<count {
        let place = places[(index * 37 + 11) % places.count]
        let category = categories[(index * 17 + 5) % categories.count]
        let severity = (index * index + 31 * index + 7) % 97
        let bucket = (index * 13 + 3) % 29
        output.append(
            "id=\(index) place=\(place) category=\(category) severity=\(severity) bucket=\(bucket)"
        )
    }

    return output
}

func slowScore(_ records: [String]) -> Int {
    var checksum = 0

    for outer in records {
        let outerParts = outer.split(separator: " ")
        let outerPlace = outerParts[1]
        let outerCategory = outerParts[2]
        let outerSeverity = Int(outerParts[3].split(separator: "=")[1]) ?? 0
        var local = 0

        for inner in records {
            let innerParts = inner.split(separator: " ")

            if innerParts[1] == outerPlace {
                local &+= 3
            }
            if innerParts[2] == outerCategory {
                local &+= 5
            }
            if innerParts[4].last == outerParts[4].last {
                local &+= 7
            }
        }

        checksum &+= local &* ((outerSeverity % 17) + 1)
    }

    return checksum
}

func compileTimeTax() -> Int {
    // This intentionally keeps tuple-heavy transforms in the compile path.
    // A real optimization pass would replace this with simpler named types.
    let labels = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta"]
    let regions = ["north", "south", "east", "west", "central", "outer"]
    let pairs = labels.flatMap { left in
        regions.map { right in
            (key: "\(left)-\(right)", value: left.count * 31 + right.count * 17)
        }
    }
    let filtered = pairs.filter { entry in
        entry.value % 3 != 0 || entry.key.count % 2 == 0
    }
    let scored = filtered.map { entry in
        (
            name: entry.key.uppercased(),
            score: (entry.value * entry.key.count) ^ (entry.key.utf8.first.map(Int.init) ?? 0)
        )
    }
    let sorted = scored.sorted { lhs, rhs in
        if lhs.score == rhs.score {
            return lhs.name < rhs.name
        }
        return lhs.score > rhs.score
    }
    let report = sorted.enumerated().map { offset, entry in
        (rank: offset + 1, label: entry.name, score: entry.score)
    }

    return report.reduce(0) { partial, entry in
        partial &+ entry.rank &* entry.score &+ entry.label.count
    }
}
