import Foundation

public struct BPETrainingConfig: Sendable {
    public var vocabSize: Int
    public var minPairFrequency: Int
    public var maxTrainingBytes: Int?

    public init(
        vocabSize: Int = 8_192,
        minPairFrequency: Int = 2,
        maxTrainingBytes: Int? = 50_000_000
    ) {
        self.vocabSize = vocabSize
        self.minPairFrequency = minPairFrequency
        self.maxTrainingBytes = maxTrainingBytes
    }

    public func validate() throws {
        guard vocabSize >= BPETokenizerTrainer.baseVocabularySize else {
            throw AutoresearchError.invalidConfiguration(
                "BPE vocab size must be at least \(BPETokenizerTrainer.baseVocabularySize)."
            )
        }
        guard minPairFrequency > 0 else {
            throw AutoresearchError.invalidConfiguration("BPE min pair frequency must be greater than zero.")
        }
        if let maxTrainingBytes {
            guard maxTrainingBytes > 0 else {
                throw AutoresearchError.invalidConfiguration("BPE max training bytes must be greater than zero.")
            }
        }
    }
}

public struct BPETrainingSummary: Sendable {
    public var outputURL: URL
    public var documents: Int
    public var trainingBytes: Int
    public var vocabSize: Int
    public var merges: Int
    public var initialTokenCount: Int
    public var finalTokenCount: Int

    public var compressionRatio: Double {
        guard initialTokenCount > 0 else { return 1.0 }
        return Double(finalTokenCount) / Double(initialTokenCount)
    }
}

public struct BPETokenizerTrainer: Sendable {
    public static let baseVocabularySize = 257
    private static let bosTokenID = 256
    private static let bosToken = "<|reserved_0|>"

    public init() {}

    public func train(
        documents: [String],
        config: BPETrainingConfig = BPETrainingConfig(),
        outputURL: URL
    ) throws -> BPETrainingSummary {
        try config.validate()

        var sequences = Self.trainingSequences(from: documents, maxTrainingBytes: config.maxTrainingBytes)
        guard !sequences.isEmpty else {
            throw AutoresearchError.emptyCorpus
        }

        let initialTokenCount = sequences.reduce(0) { $0 + $1.count }
        let trainingBytes = initialTokenCount

        var tokenBytes = (UInt8.min...UInt8.max).map { Data([$0]) }
        tokenBytes.append(Data())
        var tokenIDsByBytes = Dictionary(uniqueKeysWithValues: tokenBytes.enumerated().map { ($0.element, $0.offset) })
        var merges: [BPEMergeRank] = []

        while tokenBytes.count < config.vocabSize {
            let counts = Self.pairCounts(in: sequences)
            guard let best = Self.bestPair(in: counts),
                  best.count >= config.minPairFrequency else {
                break
            }

            var mergedBytes = tokenBytes[best.pair.left]
            mergedBytes.append(tokenBytes[best.pair.right])

            let mergedID: Int
            if let existing = tokenIDsByBytes[mergedBytes] {
                mergedID = existing
            } else {
                mergedID = tokenBytes.count
                tokenBytes.append(mergedBytes)
                tokenIDsByBytes[mergedBytes] = mergedID
            }

            merges.append(
                BPEMergeRank(
                    left: tokenBytes[best.pair.left].base64EncodedString(),
                    right: tokenBytes[best.pair.right].base64EncodedString(),
                    rank: merges.count
                )
            )

            sequences = sequences.map { Self.replacing(pair: best.pair, with: mergedID, in: $0) }
        }

        let artifact = BPEArtifact(
            version: 1,
            bosTokenID: Self.bosTokenID,
            tokenBytes: tokenBytes.map { $0.base64EncodedString() },
            mergeRanks: merges,
            specialTokens: [Self.bosToken: Self.bosTokenID]
        )

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(artifact).write(to: outputURL, options: .atomic)

        return BPETrainingSummary(
            outputURL: outputURL,
            documents: sequences.count,
            trainingBytes: trainingBytes,
            vocabSize: tokenBytes.count,
            merges: merges.count,
            initialTokenCount: initialTokenCount,
            finalTokenCount: sequences.reduce(0) { $0 + $1.count }
        )
    }

    private static func trainingSequences(from documents: [String], maxTrainingBytes: Int?) -> [[Int]] {
        var remaining = maxTrainingBytes
        var sequences: [[Int]] = []

        for document in documents {
            guard remaining.map({ $0 > 0 }) ?? true else {
                break
            }

            let bytes = Array(document.utf8)
            guard !bytes.isEmpty else {
                continue
            }

            let selectedBytes: ArraySlice<UInt8>
            if let available = remaining {
                selectedBytes = bytes.prefix(available)
                remaining = available - selectedBytes.count
            } else {
                selectedBytes = bytes[...]
            }

            guard !selectedBytes.isEmpty else {
                continue
            }
            sequences.append(selectedBytes.map { Int($0) })
        }

        return sequences
    }

    private static func pairCounts(in sequences: [[Int]]) -> [TokenIDPair: Int] {
        var counts = [TokenIDPair: Int]()

        for sequence in sequences where sequence.count > 1 {
            for index in 0..<(sequence.count - 1) {
                counts[TokenIDPair(left: sequence[index], right: sequence[index + 1]), default: 0] += 1
            }
        }

        return counts
    }

    private static func bestPair(in counts: [TokenIDPair: Int]) -> (pair: TokenIDPair, count: Int)? {
        counts.max { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value < rhs.value
            }
            if lhs.key.left != rhs.key.left {
                return lhs.key.left > rhs.key.left
            }
            return lhs.key.right > rhs.key.right
        }.map { ($0.key, $0.value) }
    }

    private static func replacing(pair: TokenIDPair, with mergedID: Int, in sequence: [Int]) -> [Int] {
        guard sequence.count > 1 else {
            return sequence
        }

        var output: [Int] = []
        output.reserveCapacity(sequence.count)
        var index = 0

        while index < sequence.count {
            if index < sequence.count - 1,
               sequence[index] == pair.left,
               sequence[index + 1] == pair.right {
                output.append(mergedID)
                index += 2
            } else {
                output.append(sequence[index])
                index += 1
            }
        }

        return output
    }
}

private struct TokenIDPair: Hashable {
    var left: Int
    var right: Int
}
