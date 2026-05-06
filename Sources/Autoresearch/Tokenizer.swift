import Foundation

public protocol LanguageTokenizer: Sendable {
    var name: String { get }
    var bosTokenID: Int { get }
    var vocabSize: Int { get }

    func encode(_ text: String, prependBOS: Bool) -> [Int]
    func decode(_ ids: [Int]) -> String
    func byteLength(of tokenID: Int) -> Int
}

public extension LanguageTokenizer {
    func encode(_ text: String) -> [Int] {
        encode(text, prependBOS: false)
    }
}

public struct ByteTokenizer: LanguageTokenizer {
    public let name = "byte"
    public let bosTokenID = 256
    public let vocabSize = 257

    public init() {}

    public func encode(_ text: String, prependBOS: Bool = false) -> [Int] {
        var ids = text.utf8.map { Int($0) }
        if prependBOS {
            ids.insert(bosTokenID, at: 0)
        }
        return ids
    }

    public func decode(_ ids: [Int]) -> String {
        let bytes = ids.compactMap { id -> UInt8? in
            guard id >= 0, id < 256 else { return nil }
            return UInt8(id)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    public func byteLength(of tokenID: Int) -> Int {
        tokenID >= 0 && tokenID < 256 ? 1 : 0
    }
}

public struct BPETokenizer: LanguageTokenizer {
    public let name = "bpe"
    public let bosTokenID: Int
    public let vocabSize: Int

    private let tokenBytes: [Data]
    private let byteLengths: [Int]
    private let byteTokenIDs: [Data: Int]
    private let mergeRanks: [TokenPair: Int]
    private let specialTokenIDs: Set<Int>

    public init(artifactURL: URL) throws {
        let data = try Data(contentsOf: artifactURL)
        let artifact = try JSONDecoder().decode(BPEArtifact.self, from: data)
        try Self.validate(artifact: artifact, source: artifactURL)

        var decodedTokenBytes = [Data]()
        decodedTokenBytes.reserveCapacity(artifact.tokenBytes.count)
        for encoded in artifact.tokenBytes {
            guard let data = Data(base64Encoded: encoded) else {
                throw AutoresearchError.invalidConfiguration(
                    "BPE tokenizer artifact contains invalid base64 token bytes."
                )
            }
            decodedTokenBytes.append(data)
        }

        var byteTokenIDs = [Data: Int]()
        for (id, bytes) in decodedTokenBytes.enumerated() where !bytes.isEmpty {
            byteTokenIDs[bytes] = id
        }

        for value in UInt8.min...UInt8.max {
            guard byteTokenIDs[Data([value])] != nil else {
                throw AutoresearchError.invalidConfiguration(
                    "BPE tokenizer artifact must include single-byte token \(value)."
                )
            }
        }

        var ranks = [TokenPair: Int]()
        for merge in artifact.mergeRanks {
            guard let left = Data(base64Encoded: merge.left),
                  let right = Data(base64Encoded: merge.right) else {
                throw AutoresearchError.invalidConfiguration(
                    "BPE tokenizer artifact contains invalid base64 merge bytes."
                )
            }
            ranks[TokenPair(left: left, right: right)] = merge.rank
        }

        var specialIDs = Set(artifact.specialTokens.values)
        specialIDs.insert(artifact.bosTokenID)

        self.bosTokenID = artifact.bosTokenID
        self.vocabSize = decodedTokenBytes.count
        self.tokenBytes = decodedTokenBytes
        self.byteTokenIDs = byteTokenIDs
        self.mergeRanks = ranks
        self.specialTokenIDs = specialIDs
        self.byteLengths = decodedTokenBytes.enumerated().map { id, bytes in
            specialIDs.contains(id) ? 0 : bytes.count
        }
    }

    public func encode(_ text: String, prependBOS: Bool = false) -> [Int] {
        var ids = text.utf8.map { byte -> Int in
            guard let id = byteTokenIDs[Data([byte])] else {
                preconditionFailure("BPE tokenizer artifact is missing byte token \(byte).")
            }
            return id
        }

        ids = merge(ids)

        if prependBOS {
            ids.insert(bosTokenID, at: 0)
        }
        return ids
    }

    public func decode(_ ids: [Int]) -> String {
        var data = Data()
        for id in ids where id >= 0 && id < tokenBytes.count && !specialTokenIDs.contains(id) {
            data.append(tokenBytes[id])
        }
        return String(decoding: data, as: UTF8.self)
    }

    public func byteLength(of tokenID: Int) -> Int {
        guard tokenID >= 0, tokenID < byteLengths.count else {
            return 0
        }
        return byteLengths[tokenID]
    }

    private func merge(_ ids: [Int]) -> [Int] {
        guard ids.count > 1, !mergeRanks.isEmpty else {
            return ids
        }

        var ids = ids
        var chunks = ids.map { tokenBytes[$0] }

        while true {
            var bestIndex: Int?
            var bestRank = Int.max
            var bestMergedID: Int?

            for index in 0..<(chunks.count - 1) {
                let pair = TokenPair(left: chunks[index], right: chunks[index + 1])
                guard let rank = mergeRanks[pair], rank < bestRank else {
                    continue
                }

                var merged = chunks[index]
                merged.append(chunks[index + 1])
                guard let mergedID = byteTokenIDs[merged] else {
                    continue
                }

                bestIndex = index
                bestRank = rank
                bestMergedID = mergedID
            }

            guard let index = bestIndex, let mergedID = bestMergedID else {
                break
            }

            ids[index] = mergedID
            chunks[index].append(chunks[index + 1])
            ids.remove(at: index + 1)
            chunks.remove(at: index + 1)

            if chunks.count < 2 {
                break
            }
        }

        return ids
    }

    private static func validate(artifact: BPEArtifact, source: URL) throws {
        guard artifact.version == 1 else {
            throw AutoresearchError.invalidConfiguration(
                "Unsupported BPE tokenizer artifact version \(artifact.version) at \(source.path)."
            )
        }
        guard !artifact.tokenBytes.isEmpty else {
            throw AutoresearchError.invalidConfiguration("BPE tokenizer artifact has no token bytes.")
        }
        guard artifact.bosTokenID >= 0, artifact.bosTokenID < artifact.tokenBytes.count else {
            throw AutoresearchError.invalidConfiguration("BPE tokenizer artifact BOS token id is out of range.")
        }
        for (name, id) in artifact.specialTokens {
            guard id >= 0, id < artifact.tokenBytes.count else {
                throw AutoresearchError.invalidConfiguration(
                    "BPE tokenizer special token \(name) has out-of-range id \(id)."
                )
            }
        }
    }
}

struct BPEArtifact: Codable {
    var version: Int
    var bosTokenID: Int
    var tokenBytes: [String]
    var mergeRanks: [BPEMergeRank]
    var specialTokens: [String: Int]

    enum CodingKeys: String, CodingKey {
        case version
        case bosTokenID = "bos_token_id"
        case tokenBytes = "token_bytes"
        case mergeRanks = "merge_ranks"
        case specialTokens = "special_tokens"
    }
}

struct BPEMergeRank: Codable {
    var left: String
    var right: String
    var rank: Int
}

private struct TokenPair: Hashable {
    var left: Data
    var right: Data
}
