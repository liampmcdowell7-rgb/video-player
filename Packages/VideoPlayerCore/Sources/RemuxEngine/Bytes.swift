import Foundation

/// Big-endian byte writer used by the box writer and by the tests that build files.
public struct ByteWriter {
    public private(set) var bytes: [UInt8] = []

    public init() {}
    public init(capacity: Int) { bytes.reserveCapacity(capacity) }

    public var count: Int { bytes.count }

    public mutating func u8(_ v: UInt8) { bytes.append(v) }
    public mutating func u16(_ v: UInt16) { bytes.append(UInt8(v >> 8)); bytes.append(UInt8(v & 0xFF)) }
    public mutating func u24(_ v: UInt32) {
        bytes.append(UInt8((v >> 16) & 0xFF)); bytes.append(UInt8((v >> 8) & 0xFF)); bytes.append(UInt8(v & 0xFF))
    }
    public mutating func u32(_ v: UInt32) {
        bytes.append(UInt8(v >> 24)); bytes.append(UInt8((v >> 16) & 0xFF))
        bytes.append(UInt8((v >> 8) & 0xFF)); bytes.append(UInt8(v & 0xFF))
    }
    public mutating func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }
    public mutating func u64(_ v: UInt64) { u32(UInt32(v >> 32)); u32(UInt32(v & 0xFFFF_FFFF)) }
    public mutating func append(_ b: [UInt8]) { bytes.append(contentsOf: b) }
    public mutating func append(_ b: ArraySlice<UInt8>) { bytes.append(contentsOf: b) }
    public mutating func append(data: Data) { bytes.append(contentsOf: data) }
    public mutating func zeros(_ n: Int) { if n > 0 { bytes.append(contentsOf: [UInt8](repeating: 0, count: n)) } }
    /// A four-character code (ASCII).
    public mutating func fourCC(_ s: String) {
        let a = Array(s.utf8)
        precondition(a.count == 4, "four-character code must be 4 bytes")
        bytes.append(contentsOf: a)
    }
    /// A padded fixed-size string (compressor name).
    public mutating func fixedString(_ s: String, length: Int) {
        var a = Array(s.utf8.prefix(length - 1))
        a.insert(UInt8(a.count), at: 0)
        a.append(contentsOf: [UInt8](repeating: 0, count: max(0, length - a.count)))
        bytes.append(contentsOf: a.prefix(length))
    }

    public mutating func patchU32(at offset: Int, _ v: UInt32) {
        bytes[offset] = UInt8(v >> 24); bytes[offset + 1] = UInt8((v >> 16) & 0xFF)
        bytes[offset + 2] = UInt8((v >> 8) & 0xFF); bytes[offset + 3] = UInt8(v & 0xFF)
    }

    /// Writes `size, type, body`. The size is patched after the body; 32-bit sizes only (every box this engine
    /// writes is far below 4 GB: one segment at most).
    public mutating func box(_ type: String, _ body: (inout ByteWriter) -> Void) {
        let start = bytes.count
        u32(0); fourCC(type)
        body(&self)
        patchU32(at: start, UInt32(bytes.count - start))
    }

    /// `box` with a version and 24-bit flags header.
    public mutating func fullBox(_ type: String, version: UInt8, flags: UInt32, _ body: (inout ByteWriter) -> Void) {
        box(type) { w in
            w.u8(version); w.u24(flags)
            body(&w)
        }
    }
}

/// Bounds-checked big-endian reader over an array.
public struct ByteCursor {
    public let bytes: [UInt8]
    public var pos: Int
    public let end: Int

    public init(_ bytes: [UInt8], pos: Int = 0, end: Int? = nil) {
        self.bytes = bytes; self.pos = pos; self.end = min(end ?? bytes.count, bytes.count)
    }

    public var remaining: Int { end - pos }

    private mutating func need(_ n: Int) throws {
        if n < 0 || pos + n > end { throw RemuxError.truncated("need \(n) bytes at \(pos), have \(end - pos)") }
    }
    public mutating func u8() throws -> UInt8 { try need(1); defer { pos += 1 }; return bytes[pos] }
    public mutating func u16() throws -> UInt16 { try need(2); defer { pos += 2 }; return UInt16(bytes[pos]) << 8 | UInt16(bytes[pos + 1]) }
    public mutating func u24() throws -> UInt32 {
        try need(3); defer { pos += 3 }
        return UInt32(bytes[pos]) << 16 | UInt32(bytes[pos + 1]) << 8 | UInt32(bytes[pos + 2])
    }
    public mutating func u32() throws -> UInt32 {
        try need(4); defer { pos += 4 }
        return UInt32(bytes[pos]) << 24 | UInt32(bytes[pos + 1]) << 16 | UInt32(bytes[pos + 2]) << 8 | UInt32(bytes[pos + 3])
    }
    public mutating func u64() throws -> UInt64 { let hi = try u32(); let lo = try u32(); return UInt64(hi) << 32 | UInt64(lo) }
    public mutating func take(_ n: Int) throws -> [UInt8] { try need(n); defer { pos += n }; return Array(bytes[pos..<pos + n]) }
    public mutating func skip(_ n: Int) throws { try need(n); pos += n }
    public mutating func fourCC() throws -> String {
        let b = try take(4)
        return String(decoding: b, as: UTF8.self)
    }
}

/// MSB-first bit reader with emulation-prevention awareness handled by the caller (see `unescapeRBSP`).
public struct BitReader {
    private let bytes: [UInt8]
    public private(set) var bitPos: Int = 0

    public init(_ bytes: [UInt8]) { self.bytes = bytes }

    public var bitsLeft: Int { bytes.count * 8 - bitPos }

    public mutating func bit() throws -> Int {
        guard bitPos < bytes.count * 8 else { throw RemuxError.truncated("bit reader") }
        let b = (Int(bytes[bitPos >> 3]) >> (7 - (bitPos & 7))) & 1
        bitPos += 1
        return b
    }
    public mutating func bits(_ n: Int) throws -> Int {
        var v = 0
        for _ in 0..<n { v = (v << 1) | (try bit()) }
        return v
    }
    public mutating func skip(_ n: Int) throws {
        guard bitPos + n <= bytes.count * 8 else { throw RemuxError.truncated("bit reader skip") }
        bitPos += n
    }
    /// Exp-Golomb unsigned.
    public mutating func ue() throws -> Int {
        var zeros = 0
        while try bit() == 0 {
            zeros += 1
            if zeros > 32 { throw RemuxError.malformed("exp-golomb too long") }
        }
        if zeros == 0 { return 0 }
        return (1 << zeros) - 1 + (try bits(zeros))
    }
    /// Exp-Golomb signed.
    public mutating func se() throws -> Int {
        let k = try ue()
        return k % 2 == 1 ? (k + 1) / 2 : -(k / 2)
    }
}

/// Removes H.264/H.265 emulation-prevention bytes (00 00 03 -> 00 00).
public func unescapeRBSP(_ b: ArraySlice<UInt8>) -> [UInt8] {
    var out: [UInt8] = []
    out.reserveCapacity(b.count)
    var zeros = 0
    for x in b {
        if zeros >= 2 && x == 3 { zeros = 0; continue }
        out.append(x)
        zeros = x == 0 ? zeros + 1 : 0
    }
    return out
}
