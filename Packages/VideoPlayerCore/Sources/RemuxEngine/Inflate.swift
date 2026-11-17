import Foundation

// A small zlib / DEFLATE decoder (RFC 1950, RFC 1951). Foundation has no portable inflate (Linux and Apple differ), and
// the engine needs one thing: Matroska subtitle tracks that mkvmerge stored with zlib compression (ContentCompAlgo 0).
// Cue blocks are tiny, so clarity beats speed here. Every failure is a thrown error, never a crash, and the output size
// is capped so a damaged or hostile block cannot grow without limit.

public enum Inflate {
    public enum Failure: Error, Equatable { case badHeader, truncated, badBlock, badCode, badDistance, tooLarge }

    /// Decodes a zlib stream (2 byte header, DEFLATE data, Adler-32). The Adler-32 is not verified (a damaged cue is
    /// shown as-is rather than dropped; the DEFLATE structure itself is fully checked).
    public static func zlib(_ input: [UInt8], maxOutput: Int = 4 * 1024 * 1024) throws -> [UInt8] {
        guard input.count >= 2 else { throw Failure.truncated }
        let cmf = Int(input[0]), flg = Int(input[1])
        guard cmf & 0x0F == 8, (cmf << 8 | flg) % 31 == 0, flg & 0x20 == 0 else { throw Failure.badHeader }
        return try deflate(input, from: 2, maxOutput: maxOutput)
    }

    /// Decodes raw DEFLATE data starting at `from`.
    public static func deflate(_ input: [UInt8], from start: Int = 0, maxOutput: Int = 4 * 1024 * 1024) throws -> [UInt8] {
        var r = Reader(input, start)
        var out: [UInt8] = []
        var final = false
        while !final {
            final = try r.bits(1) == 1
            switch try r.bits(2) {
            case 0:
                r.alignToByte()
                let len = try r.byte() | (try r.byte() << 8)
                let nlen = try r.byte() | (try r.byte() << 8)
                guard len == (~nlen & 0xFFFF) else { throw Failure.badBlock }
                guard out.count + len <= maxOutput else { throw Failure.tooLarge }
                for _ in 0..<len { out.append(UInt8(try r.byte())) }
            case 1:
                try block(&r, &out, lit: Huffman.fixedLiteral, dist: Huffman.fixedDistance, maxOutput: maxOutput)
            case 2:
                let hlit = try r.bits(5) + 257, hdist = try r.bits(5) + 1, hclen = try r.bits(4) + 4
                let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
                var clens = [Int](repeating: 0, count: 19)
                for i in 0..<hclen { clens[order[i]] = try r.bits(3) }
                let clTable = try Huffman(lengths: clens)
                var lengths: [Int] = []
                while lengths.count < hlit + hdist {
                    let sym = try clTable.decode(&r)
                    switch sym {
                    case 0...15: lengths.append(sym)
                    case 16:
                        guard let prev = lengths.last else { throw Failure.badCode }
                        lengths += [Int](repeating: prev, count: 3 + (try r.bits(2)))
                    case 17: lengths += [Int](repeating: 0, count: 3 + (try r.bits(3)))
                    default: lengths += [Int](repeating: 0, count: 11 + (try r.bits(7)))
                    }
                }
                guard lengths.count == hlit + hdist else { throw Failure.badCode }
                try block(&r, &out, lit: try Huffman(lengths: Array(lengths[0..<hlit])),
                          dist: try Huffman(lengths: Array(lengths[hlit...])), maxOutput: maxOutput)
            default:
                throw Failure.badBlock
            }
        }
        return out
    }

    private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

    private static func block(_ r: inout Reader, _ out: inout [UInt8], lit: Huffman, dist: Huffman, maxOutput: Int) throws {
        while true {
            let sym = try lit.decode(&r)
            if sym < 256 {
                guard out.count < maxOutput else { throw Failure.tooLarge }
                out.append(UInt8(sym))
            } else if sym == 256 {
                return
            } else {
                let li = sym - 257
                guard li < lengthBase.count else { throw Failure.badCode }
                let length = lengthBase[li] + (try r.bits(lengthExtra[li]))
                let di = try dist.decode(&r)
                guard di < distBase.count else { throw Failure.badCode }
                let distance = distBase[di] + (try r.bits(distExtra[di]))
                guard distance <= out.count else { throw Failure.badDistance }
                guard out.count + length <= maxOutput else { throw Failure.tooLarge }
                for _ in 0..<length { out.append(out[out.count - distance]) }
            }
        }
    }

    // LSB-first bit reader.
    struct Reader {
        let data: [UInt8]
        var pos: Int
        var bitBuffer = 0
        var bitCount = 0
        init(_ d: [UInt8], _ p: Int) { data = d; pos = p }
        mutating func bits(_ n: Int) throws -> Int {
            if n == 0 { return 0 }
            while bitCount < n {
                guard pos < data.count else { throw Failure.truncated }
                bitBuffer |= Int(data[pos]) << bitCount
                pos += 1; bitCount += 8
            }
            let v = bitBuffer & ((1 << n) - 1)
            bitBuffer >>= n; bitCount -= n
            return v
        }
        mutating func alignToByte() { bitBuffer = 0; bitCount = 0 }
        mutating func byte() throws -> Int {
            guard pos < data.count else { throw Failure.truncated }
            defer { pos += 1 }
            return Int(data[pos])
        }
    }

    // Canonical Huffman decoding by code length (the "puff" method: slow but small and obviously correct).
    struct Huffman {
        var counts = [Int](repeating: 0, count: 16)
        var symbols: [Int] = []

        init(lengths: [Int]) throws {
            for l in lengths { guard l >= 0, l <= 15 else { throw Failure.badCode }; counts[l] += 1 }
            counts[0] = 0
            var left = 1
            for len in 1...15 {
                left <<= 1
                left -= counts[len]
                guard left >= 0 else { throw Failure.badCode }     // over-subscribed
            }
            var offsets = [Int](repeating: 0, count: 16)
            for len in 1..<15 { offsets[len + 1] = offsets[len] + counts[len] }
            symbols = [Int](repeating: 0, count: lengths.count)
            for (sym, l) in lengths.enumerated() where l != 0 { symbols[offsets[l]] = sym; offsets[l] += 1 }
        }

        func decode(_ r: inout Reader) throws -> Int {
            var code = 0, first = 0, index = 0
            for len in 1...15 {
                code |= try r.bits(1)
                let count = counts[len]
                if code - count < first { return symbols[index + (code - first)] }
                index += count; first += count; first <<= 1; code <<= 1
            }
            throw Failure.badCode
        }

        static let fixedLiteral: Huffman = {
            let l = [Int](repeating: 8, count: 144) + [Int](repeating: 9, count: 112) + [Int](repeating: 7, count: 24) + [Int](repeating: 8, count: 8)
            // The fixed tables are valid by construction, so `try!` cannot fail.
            return try! Huffman(lengths: l)
        }()
        static let fixedDistance: Huffman = try! Huffman(lengths: [Int](repeating: 5, count: 30))
    }
}
