import Foundation

/// Exact front-coded lookup: one shared physical-key index for both languages.
/// A query decodes at most 16 short keys; no probabilistic membership and no SQL.
package struct CompactLexicon: Sendable {
    package struct Entry: Equatable, Sendable {
        package let english: UInt8
        package let russian: UInt8
        package let flags: UInt8
    }
    private struct Block: Sendable {
        let key: [UInt8]
        let offset: Int
        let end: Int
    }
    private let bytes: [UInt8]
    private let blocks: [Block]
    package let count: Int
    package let decodedBytes: Int
    package static let shared: CompactLexicon? = load()
    package static func load() -> CompactLexicon? {
        guard let url = Bundle.module.url(forResource: "Lexicon", withExtension: "lzfse"),
              let compressed = try? Data(contentsOf: url),
              compressed.count <= 2_000_000,
              let data = try? (compressed as NSData).decompressed(using: .lzfse) as Data else { return nil }
        return CompactLexicon(data: data)
    }

    package init?(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 20, bytes.count <= 4_000_000,
              Array(bytes[0..<8]) == [76, 83, 76, 88, 1, 0, 0, 0] else { return nil }
        func u32(_ offset: Int) -> Int {
            Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 |
                Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
        }
        let metadataSize = u32(8)
        let count = u32(12)
        let blockCount = u32(16)
        guard metadataSize <= 100_000, count > 0, count <= 300_000,
              blockCount == (count + 15) / 16 else { return nil }
        let indexStart = 20 + metadataSize
        let payloadStart = indexStart + (blockCount + 1) * 4
        guard payloadStart < bytes.count else { return nil }
        var blocks: [Block] = []
        blocks.reserveCapacity(blockCount)
        var records = 0
        var previousKey: [UInt8] = []
        for index in 0..<blockCount {
            let offset = payloadStart + u32(indexStart + index * 4)
            let end = payloadStart + u32(indexStart + (index + 1) * 4)
            guard offset >= payloadStart, offset < end, end <= bytes.count else { return nil }
            let number = Int(bytes[offset])
            guard number == min(16, count - records) else { return nil }
            var cursor = offset + 1
            var key: [UInt8] = []
            var firstKey: [UInt8] = []
            for record in 0..<number {
                guard cursor + 5 <= end else { return nil }
                let prefix = Int(bytes[cursor]), suffix = Int(bytes[cursor + 1])
                guard prefix <= key.count, prefix + suffix <= 40, suffix > 0,
                      cursor + 5 + suffix <= end, record != 0 || prefix == 0 else { return nil }
                key = Array(key.prefix(prefix)) + bytes[(cursor + 5)..<(cursor + 5 + suffix)]
                guard previousKey.isEmpty || previousKey.lexicographicallyPrecedes(key),
                      key.allSatisfy({ (32...126).contains($0) }) else { return nil }
                if record == 0 { firstKey = key }
                previousKey = key
                cursor += 5 + suffix
                records += 1
            }
            guard cursor == end else { return nil }
            blocks.append(Block(key: firstKey, offset: offset, end: end))
        }
        guard records == count, blocks.last?.end == bytes.count else { return nil }
        self.bytes = bytes
        self.blocks = blocks
        self.count = count
        decodedBytes = data.count
    }

    package func lookup(_ key: [UInt8]) -> Entry? {
        var low = 0, high = blocks.count
        while low < high {
            let middle = (low + high) / 2
            if key.lexicographicallyPrecedes(blocks[middle].key) { high = middle }
            else { low = middle + 1 }
        }
        guard low > 0 else { return nil }
        let block = blocks[low - 1]
        var cursor = block.offset + 1
        var current: [UInt8] = []
        current.reserveCapacity(40)
        for _ in 0..<Int(bytes[block.offset]) {
            let prefix = Int(bytes[cursor]), suffix = Int(bytes[cursor + 1])
            current.removeLast(current.count - prefix)
            current.append(contentsOf: bytes[(cursor + 5)..<(cursor + 5 + suffix)])
            if current == key {
                return Entry(english: bytes[cursor + 2], russian: bytes[cursor + 3], flags: bytes[cursor + 4])
            }
            if key.lexicographicallyPrecedes(current) { return nil }
            cursor += 5 + suffix
        }
        return nil
    }

    /// Used by the release benchmark to compare an ordinary hash table with the
    /// compact index. The application only uses lookup(_:).
    package func forEach(_ body: (String, Entry) -> Void) {
        for block in blocks {
            var cursor = block.offset + 1
            var key: [UInt8] = []
            for _ in 0..<Int(bytes[block.offset]) {
                let prefix = Int(bytes[cursor]), suffix = Int(bytes[cursor + 1])
                key.removeLast(key.count - prefix)
                key.append(contentsOf: bytes[(cursor + 5)..<(cursor + 5 + suffix)])
                body(String(decoding: key, as: UTF8.self), Entry(english: bytes[cursor + 2], russian: bytes[cursor + 3], flags: bytes[cursor + 4]))
                cursor += 5 + suffix
            }
        }
    }
}
