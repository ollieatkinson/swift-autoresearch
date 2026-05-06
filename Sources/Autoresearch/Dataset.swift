import Foundation

public struct PreparationSummary: Sendable {
    public var cacheDirectory: URL
    public var trainDocuments: Int
    public var validationDocuments: Int
    public var trainBytes: Int
    public var validationBytes: Int
}

public struct DatasetPreparer {
    public init() {}

    public func prepare(
        input: URL,
        validationFraction: Double = 0.1,
        paths: CachePaths = CachePaths()
    ) throws -> PreparationSummary {
        guard validationFraction > 0, validationFraction < 1 else {
            throw AutoresearchError.invalidConfiguration("validationFraction must be between 0 and 1.")
        }

        let documents = try Self.loadDocuments(input: input)
        guard !documents.isEmpty else {
            throw AutoresearchError.emptyCorpus
        }

        let split = Self.split(documents: documents, validationFraction: validationFraction)
        try FileManager.default.createDirectory(at: paths.dataDirectory, withIntermediateDirectories: true)

        let trainText = split.train.joined(separator: "\n\n")
        let validationText = split.validation.joined(separator: "\n\n")
        try trainText.write(to: paths.trainText, atomically: true, encoding: .utf8)
        try validationText.write(to: paths.validationText, atomically: true, encoding: .utf8)

        return PreparationSummary(
            cacheDirectory: paths.root,
            trainDocuments: split.train.count,
            validationDocuments: split.validation.count,
            trainBytes: trainText.utf8.count,
            validationBytes: validationText.utf8.count
        )
    }

    private static func loadDocuments(input: URL) throws -> [String] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: input.path, isDirectory: &isDirectory) else {
            throw AutoresearchError.invalidConfiguration("Input path does not exist: \(input.path)")
        }

        if isDirectory.boolValue {
            let urls = try FileManager.default.contentsOfDirectory(
                at: input,
                includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension.lowercased() == "txt" }
            .sorted { $0.path < $1.path }

            let joined = try urls
                .map { try String(contentsOf: $0, encoding: .utf8) }
                .joined(separator: "\n\n")
            return splitDocuments(joined)
        } else {
            return splitDocuments(try String(contentsOf: input, encoding: .utf8))
        }
    }

    private static func split(documents: [String], validationFraction: Double) -> (train: [String], validation: [String]) {
        if documents.count == 1 {
            let bytes = Array(documents[0].utf8)
            guard bytes.count > 1 else {
                return (documents, documents)
            }
            let cut = max(1, min(bytes.count - 1, Int(Double(bytes.count) * (1.0 - validationFraction))))
            let train = String(decoding: bytes[..<cut], as: UTF8.self)
            let validation = String(decoding: bytes[cut...], as: UTF8.self)
            return ([train], [validation])
        }

        let validationCount = max(1, Int((Double(documents.count) * validationFraction).rounded(.up)))
        let splitIndex = max(1, documents.count - validationCount)
        return (
            Array(documents[..<splitIndex]),
            Array(documents[splitIndex...])
        )
    }

    public static func splitDocuments(_ text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let paragraphDocuments = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if paragraphDocuments.count > 1 {
            return paragraphDocuments
        }

        return normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

public struct TextCorpus: Sendable {
    public var trainDocuments: [String]
    public var validationDocuments: [String]

    public init(trainDocuments: [String], validationDocuments: [String]) {
        self.trainDocuments = trainDocuments
        self.validationDocuments = validationDocuments
    }

    public static func load(paths: CachePaths) throws -> TextCorpus {
        guard FileManager.default.fileExists(atPath: paths.trainText.path),
              FileManager.default.fileExists(atPath: paths.validationText.path) else {
            throw AutoresearchError.missingData(paths.dataDirectory)
        }

        let train = DatasetPreparer.splitDocuments(try String(contentsOf: paths.trainText, encoding: .utf8))
        let validation = DatasetPreparer.splitDocuments(try String(contentsOf: paths.validationText, encoding: .utf8))
        guard !train.isEmpty, !validation.isEmpty else {
            throw AutoresearchError.emptyCorpus
        }
        return TextCorpus(trainDocuments: train, validationDocuments: validation)
    }
}

public struct TokenBatch: Sendable {
    public var inputs: [Int]
    public var targets: [Int]
    public var epoch: Int

    public var tokenCount: Int {
        inputs.count
    }
}

public final class PackedBatchLoader {
    private let tokenizer: any LanguageTokenizer
    private let documents: [[Int]]
    private let batchSize: Int
    private let sequenceLength: Int
    private let rowCapacity: Int
    private let bufferSize: Int
    private var documentIndex = 0
    private var currentEpoch = 1
    private var documentBuffer: [[Int]] = []

    public init(
        tokenizer: any LanguageTokenizer,
        documents: [String],
        batchSize: Int,
        sequenceLength: Int,
        bufferSize: Int = 1_000
    ) throws {
        guard batchSize > 0, sequenceLength > 0, bufferSize > 0 else {
            throw AutoresearchError.invalidConfiguration("Batch size, sequence length, and buffer size must be positive.")
        }

        self.tokenizer = tokenizer
        self.batchSize = batchSize
        self.sequenceLength = sequenceLength
        self.rowCapacity = sequenceLength + 1
        self.bufferSize = bufferSize
        self.documents = Self.tokenize(documents: documents, tokenizer: tokenizer, sequenceLength: sequenceLength)

        guard !self.documents.isEmpty else {
            throw AutoresearchError.emptyCorpus
        }
    }

    public func next() -> TokenBatch {
        var rows = [Int](repeating: tokenizer.bosTokenID, count: batchSize * rowCapacity)

        for rowIndex in 0..<batchSize {
            var position = 0
            while position < rowCapacity {
                refillBufferIfNeeded()
                let remaining = rowCapacity - position

                if let bestIndex = bestDocumentIndex(fitting: remaining) {
                    let document = documentBuffer.remove(at: bestIndex)
                    copy(document, into: &rows, rowIndex: rowIndex, position: position)
                    position += document.count
                } else {
                    let shortestIndex = shortestDocumentIndex()
                    let document = Array(documentBuffer.remove(at: shortestIndex).prefix(remaining))
                    copy(document, into: &rows, rowIndex: rowIndex, position: position)
                    position += document.count
                }
            }
        }

        var inputs: [Int] = []
        var targets: [Int] = []
        inputs.reserveCapacity(batchSize * sequenceLength)
        targets.reserveCapacity(batchSize * sequenceLength)

        for rowIndex in 0..<batchSize {
            let base = rowIndex * rowCapacity
            inputs.append(contentsOf: rows[base..<(base + sequenceLength)])
            targets.append(contentsOf: rows[(base + 1)..<(base + rowCapacity)])
        }

        return TokenBatch(inputs: inputs, targets: targets, epoch: currentEpoch)
    }

    private static func tokenize(
        documents: [String],
        tokenizer: any LanguageTokenizer,
        sequenceLength: Int
    ) -> [[Int]] {
        documents.flatMap { document -> [[Int]] in
            let payload = tokenizer.encode(document)
            guard !payload.isEmpty else { return [] }

            var chunks: [[Int]] = []
            var offset = 0
            while offset < payload.count {
                let end = min(offset + sequenceLength, payload.count)
                var chunk = [tokenizer.bosTokenID]
                chunk.append(contentsOf: payload[offset..<end])
                if chunk.count > 1 {
                    chunks.append(chunk)
                }
                offset = end
            }
            return chunks
        }
    }

    private func refillBufferIfNeeded() {
        while documentBuffer.count < bufferSize {
            documentBuffer.append(documents[documentIndex])
            documentIndex += 1
            if documentIndex == documents.count {
                documentIndex = 0
                currentEpoch += 1
            }
        }
    }

    private func bestDocumentIndex(fitting remaining: Int) -> Int? {
        var bestIndex: Int?
        var bestLength = 0

        for index in documentBuffer.indices {
            let count = documentBuffer[index].count
            if count <= remaining, count > bestLength {
                bestIndex = index
                bestLength = count
            }
        }

        return bestIndex
    }

    private func shortestDocumentIndex() -> Int {
        var shortestIndex = documentBuffer.startIndex
        var shortestLength = documentBuffer[shortestIndex].count

        for index in documentBuffer.indices.dropFirst() {
            let count = documentBuffer[index].count
            if count < shortestLength {
                shortestIndex = index
                shortestLength = count
            }
        }

        return shortestIndex
    }

    private func copy(_ document: [Int], into rows: inout [Int], rowIndex: Int, position: Int) {
        let base = rowIndex * rowCapacity + position
        for (offset, token) in document.enumerated() {
            rows[base + offset] = token
        }
    }
}
