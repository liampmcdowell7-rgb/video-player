import Foundation

/// #33 B: reads the screenshots of a CI run on Linux, where there is no image library, so the pixel checks can be run on
/// the real pictures (CI screenshots are 8-bit RGB or RGBA, not interlaced). Supports bit depth 8 with colour types 0 (grey),
/// 2 (RGB), 4 (grey and alpha) and 6 (RGBA), the five PNG row filters, and zlib/deflate (stored, fixed and dynamic Huffman
/// blocks, RFC 1950/1951). The UI tests do not use it: they read the screenshot with CoreGraphics.
public enum PNGDecoder {
    public enum Failure: Error, Equatable {
        case notPNG
        case unsupported(String)
        case corrupt(String)
    }

    public static func decode(_ data: [UInt8]) throws -> RGBImage {
        let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        guard data.count > 8, Array(data[0..<8]) == signature else { throw Failure.notPNG }
        var offset: Int = 8
        var width: Int = 0, height: Int = 0, colourType: Int = -1
        var compressed: [UInt8] = []
        func be32(_ at: Int) -> Int { Int(data[at]) << 24 | Int(data[at + 1]) << 16 | Int(data[at + 2]) << 8 | Int(data[at + 3]) }
        while offset + 8 <= data.count {
            let length: Int = be32(offset)
            let type: String = String(decoding: data[(offset + 4)..<(offset + 8)], as: UTF8.self)
            let start: Int = offset + 8
            guard start + length + 4 <= data.count else { throw Failure.corrupt("chunk \(type) runs past the end") }
            switch type {
            case "IHDR":
                width = be32(start)
                height = be32(start + 4)
                let depth: Int = Int(data[start + 8])
                colourType = Int(data[start + 9])
                guard depth == 8 else { throw Failure.unsupported("bit depth \(depth)") }
                guard data[start + 12] == 0 else { throw Failure.unsupported("interlaced") }
            case "IDAT":
                compressed.append(contentsOf: data[start..<(start + length)])
            case "IEND":
                offset = data.count
                continue
            default:
                break
            }
            offset = start + length + 4
        }
        let channels: Int
        switch colourType {
        case 0: channels = 1
        case 2: channels = 3
        case 4: channels = 2
        case 6: channels = 4
        default: throw Failure.unsupported("colour type \(colourType)")
        }
        guard width > 0, height > 0, compressed.count > 2 else { throw Failure.corrupt("no image data") }
        guard compressed[0] & 0x0F == 8 else { throw Failure.unsupported("zlib method \(compressed[0] & 0x0F)") }
        let stride: Int = width * channels
        var raw: [UInt8] = try Inflate.run(Array(compressed[2...]), expected: height * (stride + 1))
        guard raw.count >= height * (stride + 1) else { throw Failure.corrupt("\(raw.count) bytes for \(height) rows of \(stride + 1)") }
        try unfilter(&raw, rows: height, stride: stride, bytesPerPixel: channels)
        var rgb: [UInt8] = [UInt8](repeating: 0, count: width * height * 3)
        rgb.withUnsafeMutableBufferPointer { (out: inout UnsafeMutableBufferPointer<UInt8>) in
            raw.withUnsafeBufferPointer { (src: UnsafeBufferPointer<UInt8>) in
                for y in 0..<height {
                    let row: Int = y * (stride + 1) + 1
                    for x in 0..<width {
                        let s: Int = row + x * channels, d: Int = (y * width + x) * 3
                        if channels >= 3 {
                            out[d] = src[s]; out[d + 1] = src[s + 1]; out[d + 2] = src[s + 2]
                        } else {
                            out[d] = src[s]; out[d + 1] = src[s]; out[d + 2] = src[s]
                        }
                    }
                }
            }
        }
        return RGBImage(width: width, height: height, bytes: rgb)
    }

    /// Undoes the per-row filters in place (PNG specification, section 9).
    static func unfilter(_ raw: inout [UInt8], rows: Int, stride: Int, bytesPerPixel bpp: Int) throws {
        try raw.withUnsafeMutableBufferPointer { (buf: inout UnsafeMutableBufferPointer<UInt8>) in
            for y in 0..<rows {
                let row: Int = y * (stride + 1)
                let filter: UInt8 = buf[row]
                let cur: Int = row + 1
                let prev: Int = cur - (stride + 1)
                for i in 0..<stride {
                    let a: Int = i >= bpp ? Int(buf[cur + i - bpp]) : 0
                    let b: Int = y > 0 ? Int(buf[prev + i]) : 0
                    let c: Int = (y > 0 && i >= bpp) ? Int(buf[prev + i - bpp]) : 0
                    let x: Int = Int(buf[cur + i])
                    let value: Int
                    switch filter {
                    case 0: value = x
                    case 1: value = x + a
                    case 2: value = x + b
                    case 3: value = x + (a + b) / 2
                    case 4:
                        let p: Int = a + b - c
                        let pa: Int = abs(p - a), pb: Int = abs(p - b), pc: Int = abs(p - c)
                        value = x + ((pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c))
                    default: throw Failure.corrupt("row filter \(filter)")
                    }
                    buf[cur + i] = UInt8(truncatingIfNeeded: value)
                }
            }
        }
    }
}

/// Raw deflate (RFC 1951), after the 2-byte zlib header. Canonical Huffman decoding in the manner of zlib's "puff".
enum Inflate {
    struct Huffman {
        var counts: [Int] = [Int](repeating: 0, count: 16)
        var symbols: [Int]

        init(lengths: [Int]) {
            symbols = [Int](repeating: 0, count: lengths.count)
            for length in lengths { counts[length] += 1 }
            counts[0] = 0
            var offsets: [Int] = [Int](repeating: 0, count: 16)
            for i in 1..<15 { offsets[i + 1] = offsets[i] + counts[i] }
            for (symbol, length) in lengths.enumerated() where length != 0 {
                symbols[offsets[length]] = symbol
                offsets[length] += 1
            }
        }
    }

    struct Bits {
        let input: [UInt8]
        var position: Int = 0
        var buffer: UInt64 = 0
        var count: Int = 0

        mutating func need(_ n: Int) throws -> Int {
            while count < n {
                guard position < input.count else { throw PNGDecoder.Failure.corrupt("deflate data ends early") }
                buffer |= UInt64(input[position]) << UInt64(count)
                position += 1
                count += 8
            }
            let value: Int = Int(buffer & ((1 << UInt64(n)) - 1))
            buffer >>= UInt64(n)
            count -= n
            return value
        }

        mutating func align() {
            buffer = 0
            count = 0
        }

        mutating func decode(_ h: Huffman) throws -> Int {
            var code: Int = 0, first: Int = 0, index: Int = 0
            for length in 1...15 {
                code |= try need(1)
                let n: Int = h.counts[length]
                if code - n < first { return h.symbols[index + (code - first)] }
                index += n
                first += n
                first <<= 1
                code <<= 1
            }
            throw PNGDecoder.Failure.corrupt("bad Huffman code")
        }
    }

    static let lengthBase: [Int] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    static let lengthExtra: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    static let distanceBase: [Int] = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    static let distanceExtra: [Int] = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    static let order: [Int] = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    static let fixed: (Huffman, Huffman) = {
        var lengths: [Int] = [Int](repeating: 8, count: 288)
        for i in 144..<256 { lengths[i] = 9 }
        for i in 256..<280 { lengths[i] = 7 }
        return (Huffman(lengths: lengths), Huffman(lengths: [Int](repeating: 5, count: 30)))
    }()

    static func run(_ input: [UInt8], expected: Int) throws -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(expected)
        var bits: Bits = Bits(input: input)
        var last: Int = 0
        repeat {
            last = try bits.need(1)
            switch try bits.need(2) {
            case 0:
                bits.align()
                guard bits.position + 4 <= input.count else { throw PNGDecoder.Failure.corrupt("stored block header") }
                let length: Int = Int(input[bits.position]) | Int(input[bits.position + 1]) << 8
                bits.position += 4
                guard bits.position + length <= input.count else { throw PNGDecoder.Failure.corrupt("stored block runs past the end") }
                out.append(contentsOf: input[bits.position..<(bits.position + length)])
                bits.position += length
            case 1:
                try codes(&bits, &out, fixed.0, fixed.1)
            case 2:
                let literals: Int = try bits.need(5) + 257, distances: Int = try bits.need(5) + 1, codeCount: Int = try bits.need(4) + 4
                var codeLengths: [Int] = [Int](repeating: 0, count: 19)
                for i in 0..<codeCount { codeLengths[order[i]] = try bits.need(3) }
                let lengthCode: Huffman = Huffman(lengths: codeLengths)
                var lengths: [Int] = []
                while lengths.count < literals + distances {
                    let symbol: Int = try bits.decode(lengthCode)
                    switch symbol {
                    case 0..<16: lengths.append(symbol)
                    case 16:
                        guard let previous = lengths.last else { throw PNGDecoder.Failure.corrupt("repeat with no length") }
                        lengths.append(contentsOf: [Int](repeating: previous, count: 3 + (try bits.need(2))))
                    case 17: lengths.append(contentsOf: [Int](repeating: 0, count: 3 + (try bits.need(3))))
                    default: lengths.append(contentsOf: [Int](repeating: 0, count: 11 + (try bits.need(7))))
                    }
                }
                try codes(&bits, &out, Huffman(lengths: Array(lengths[0..<literals])), Huffman(lengths: Array(lengths[literals..<(literals + distances)])))
            default:
                throw PNGDecoder.Failure.corrupt("block type 3")
            }
        } while last == 0
        return out
    }

    static func codes(_ bits: inout Bits, _ out: inout [UInt8], _ literal: Huffman, _ distance: Huffman) throws {
        while true {
            let symbol: Int = try bits.decode(literal)
            if symbol < 256 {
                out.append(UInt8(symbol))
            } else if symbol == 256 {
                return
            } else {
                let l: Int = symbol - 257
                guard l < 29 else { throw PNGDecoder.Failure.corrupt("length symbol \(symbol)") }
                let length: Int = lengthBase[l] + (try bits.need(lengthExtra[l]))
                let d: Int = try bits.decode(distance)
                guard d < 30 else { throw PNGDecoder.Failure.corrupt("distance symbol \(d)") }
                let back: Int = distanceBase[d] + (try bits.need(distanceExtra[d]))
                guard back <= out.count else { throw PNGDecoder.Failure.corrupt("distance \(back) before the start") }
                let from: Int = out.count - back
                for i in 0..<length { out.append(out[from + i]) }
            }
        }
    }
}
