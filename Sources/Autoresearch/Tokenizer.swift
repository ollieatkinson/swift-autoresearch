import Foundation

public struct ByteTokenizer: Sendable {
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
