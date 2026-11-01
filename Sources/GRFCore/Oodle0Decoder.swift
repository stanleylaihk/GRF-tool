import Foundation

// Adapted from granny-ro-js (MIT), Copyright (c) 2026 Stitchuuuu,
// and blendergranny (MIT), Copyright (c) 2026 ciupix and contributors.
// See THIRD_PARTY_NOTICES.md. No Windows runtime is loaded by this decoder.
public enum Oodle0Decoder {
    public static func decompress(_ compressed: Data, expandedSize: Int,
                                  first16Bit: Int, first8Bit: Int) throws -> Data {
        let limit = 64 * 1024 * 1024
        guard expandedSize >= 0, expandedSize <= limit, compressed.count <= limit else {
            throw GRFError.invalid("Oodle-0 section exceeds the 64 MiB limit.")
        }
        guard first16Bit >= 0, first16Bit <= first8Bit, first8Bit <= expandedSize else {
            throw GRFError.invalid("Invalid Oodle-0 block boundaries.")
        }
        if expandedSize == 0 { return Data() }
        guard compressed.count >= 36, expandedSize <= compressed.count * 1024 else {
            throw GRFError.invalid("Invalid Oodle-0 section size or expansion ratio.")
        }
        let input = Array(compressed)
        let budget = OodleWorkBudget()
        let bits = try OodleArithmeticBits(input, offset: 36, budget: budget)
        var output = [UInt8](repeating: 0, count: expandedSize)
        let stops = [0, first16Bit, first8Bit, expandedSize]
        var cursor = 0
        for block in 0..<3 where stops[block + 1] > stops[block] {
            let p = block * 12
            let maxWord = OodleVarBits.word(input, p)
            let uniqueWord = OodleVarBits.word(input, p + 4)
            let lengthsWord = OodleVarBits.word(input, p + 8)
            let maxBytes = Int(maxWord & 0x1ff), maxOffsets = Int(maxWord >> 9)
            let uniqueBytes = Int(uniqueWord & 0x1ff), uniqueOffsets = Int(uniqueWord >> 9)
            guard maxBytes <= 256, uniqueBytes <= 256 else {
                throw GRFError.invalid("Invalid Oodle-0 literal alphabet.")
            }
            let literals = try OodleModel(uniqueBytes, budget: budget)
            let lengths = try (0...64).map { index -> OodleModel in
                let group = min(index / 16, 3)
                let n = Int((lengthsWord >> UInt32((3 - group) * 8)) & 0xff)
                guard n <= 65 else { throw GRFError.invalid("Invalid Oodle-0 length alphabet.") }
                return try OodleModel(n, budget: budget)
            }
            let maxLow = min(maxOffsets, 4)
            let offsetLow = try OodleModel(maxLow, budget: budget)
            let offsetHigh = try OodleModel(uniqueOffsets, budget: budget)
            var decompressed = 0, previousLength = 0
            while cursor < stops[block + 1] {
                try budget.spend()
                let symbol = try lengths[previousLength].read(bits, escapeScale: 65)
                guard (0...64).contains(symbol) else { throw GRFError.invalid("Invalid Oodle-0 length symbol.") }
                previousLength = symbol
                if symbol == 0 {
                    let literal = try literals.read(bits, escapeScale: maxBytes)
                    guard (0...255).contains(literal), cursor < output.count else {
                        throw GRFError.invalid("Invalid Oodle-0 literal or output range.")
                    }
                    output[cursor] = UInt8(literal); cursor += 1; decompressed += 1
                } else {
                    let length = symbol >= 61 ? [128, 192, 256, 512][symbol - 61] : symbol + 1
                    let low = try offsetLow.read(bits, escapeScale: maxLow)
                    let highScale = (min(maxOffsets, decompressed) >> 2) + 1
                    let high = try offsetHigh.read(bits, escapeScale: highScale)
                    let distance = low + 1 + (high << 2)
                    guard distance > 0, distance <= cursor, length <= output.count - cursor else {
                        throw GRFError.invalid("Invalid Oodle-0 back-reference.")
                    }
                    for k in 0..<length { output[cursor + k] = output[cursor - distance + k] }
                    cursor += length; decompressed += length
                }
            }
        }
        guard cursor == expandedSize else { throw GRFError.invalid("Oodle-0 output length does not match the section header.") }
        return Data(output)
    }
}

private final class OodleWorkBudget {
    private var remaining = 200_000_000
    func spend(_ amount: Int = 1) throws {
        remaining -= amount
        guard remaining >= 0 else { throw GRFError.invalid("Oodle-0 section exceeded the decoding work limit.") }
    }
}

private final class OodleVarBits {
    let data: [UInt8]
    var cursor: Int
    var bits: UInt32 = 0
    var bitLength = 0
    init(_ data: [UInt8], offset: Int) { self.data = data; cursor = offset }
    static func word(_ data: [UInt8], _ offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for i in 0..<4 where offset + i < data.count { value |= UInt32(data[offset + i]) << UInt32(i * 8) }
        return value
    }
    func get(_ n: Int) throws -> UInt32 {
        if n == 0 { return 0 }
        let mask = (UInt32(1) << UInt32(n)) - 1
        if bitLength >= n {
            let value = bits & mask; bits >>= UInt32(n); bitLength -= n; return value
        }
        // The bitstream is word padded. Bound implicit zero padding so truncated
        // or hostile inputs cannot request an unlimited stream of zero words.
        guard cursor <= data.count + 32 else { throw GRFError.invalid("Truncated Oodle-0 bitstream.") }
        let word = Self.word(data, cursor); cursor += 4
        let needed = n - bitLength
        let lowMask = (UInt32(1) << UInt32(needed)) - 1
        let value = bits | ((word & lowMask) << UInt32(bitLength))
        bits = word >> UInt32(needed); bitLength += 32 - n
        return value
    }
}

private func oodleReverse(_ value: UInt32, _ n: Int) -> UInt32 {
    var result: UInt32 = 0
    for i in 0..<n { result = (result << 1) | ((value >> UInt32(i)) & 1) }
    return result
}

private final class OodleArithmeticBits {
    let source: OodleVarBits
    let budget: OodleWorkBudget
    var high: UInt32 = 0x7fffffff
    var low: UInt32 = 0
    var code: UInt32
    init(_ input: [UInt8], offset: Int, budget: OodleWorkBudget) throws {
        source = OodleVarBits(input, offset: offset); self.budget = budget
        code = oodleReverse(try source.get(31), 31)
    }
    func count(_ scale: Int) throws -> Int {
        guard scale > 0, high >= low, code >= low, code <= high else {
            throw GRFError.invalid("Invalid Oodle-0 arithmetic interval.")
        }
        let width = UInt64(high) - UInt64(low) + 1
        return Int(((UInt64(code) - UInt64(low) + 1) * UInt64(scale) - 1) / width)
    }
    func value(_ scale: Int) throws -> Int {
        guard scale > 0 else { throw GRFError.invalid("Invalid Oodle-0 escape scale.") }
        let value = min(try count(scale), scale - 1)
        try remove(value, 1, scale)
        return value
    }
    func remove(_ start: Int, _ amount: Int, _ scale: Int) throws {
        guard scale > 0, amount > 0, start >= 0, start <= scale - amount, high >= low else {
            throw GRFError.invalid("Invalid Oodle-0 arithmetic symbol.")
        }
        var high = self.high, low = self.low, code = self.code
        let width = UInt64(high) - UInt64(low) + 1
        let nextHigh = UInt64(low) + width * UInt64(start + amount) / UInt64(scale)
        let nextLow = UInt64(low) + width * UInt64(start) / UInt64(scale)
        guard nextHigh > 0, nextHigh > nextLow else { throw GRFError.invalid("Empty Oodle-0 arithmetic interval.") }
        high = UInt32(truncatingIfNeeded: nextHigh - 1)
        low = UInt32(truncatingIfNeeded: nextLow)
        if ((high ^ low) & 0x40000000) == 0 {
            while ((high ^ low) & 0x7f800000) == 0 {
                try budget.spend()
                low <<= 8; high = (high << 8) | 0xff
                let byte = try source.get(8)
                code = (code << 8) | (oodleReverse(byte & 0xf, 4) << 4) | oodleReverse(byte >> 4, 4)
            }
            if ((high ^ low) & 0x78000000) == 0 {
                low <<= 4; high = (high << 4) | 0xf
                code = (code << 4) | oodleReverse(try source.get(4), 4)
            }
            while ((high ^ low) & 0x40000000) == 0 {
                try budget.spend()
                low <<= 1; high = (high << 1) | 1
                code = (code << 1) | (try source.get(1))
            }
        }
        while (low & 0x20000000) != 0 && (high & 0x20000000) == 0 {
            try budget.spend()
            code ^= 0x20000000
            low = (low & 0x1fffffff) << 1
            high = (high << 1) | 0x40000001
            code = (code << 1) | (try source.get(1))
        }
        self.high = high & 0x7fffffff; self.low = low & 0x7fffffff; self.code = code & 0x7fffffff
    }
}

private func oodleBestShift(_ value: Int) -> (shift: Int, last: Int) {
    if value < 6 { return (15, 0) }
    var bestMax = Int.max, best = 0
    for index in 0..<16 {
        let size = 1 << index
        let bins = min((value + size - 1) / size, 16)
        let last = max(value - size * (bins - 1), size)
        if last < bestMax { best = index; bestMax = last }
        if size > value { break }
    }
    return (best, 15 * (1 << best))
}

private final class OodleModel {
    let unique: Int
    let budget: OodleWorkBudget
    var totals = [Int](repeating: 0, count: 16)
    var counts: [Int]
    var values: [Int]
    var number = 0
    var shift: Int
    var last: Int
    init(_ unique: Int, budget: OodleWorkBudget) throws {
        guard unique >= 0, unique <= 1 << 21 else { throw GRFError.invalid("Oodle-0 arithmetic alphabet exceeds the supported limit.") }
        self.unique = unique; self.budget = budget
        let size = (unique + 5) & ~3
        counts = [Int](repeating: 0, count: size); values = [Int](repeating: 0, count: size)
        (shift, last) = oodleBestShift(unique + 1)
        increment(0, 3)
    }
    func read(_ bits: OodleArithmeticBits, escapeScale: Int) throws -> Int {
        if totals[15] >= 16384 { try rescale() }
        let count = try bits.count(totals[15])
        let (position, start) = try find(count)
        let oldCount = counts[position]
        incrementTotals(position, 1)
        try bits.remove(start, oldCount, totals[15] - 1)
        counts[position] = (counts[position] + 1) & 0xffff
        if position == 0 {
            number += 1
            guard number < counts.count else { throw GRFError.invalid("Oodle-0 escape exceeded model capacity.") }
            increment(number, 2)
            if number == unique { decrement(0, counts[0]) }
            let escaped = try bits.value(escapeScale)
            values[number] = escaped & 0xffff
            return escaped
        }
        return values[position]
    }
    func find(_ count: Int) throws -> (Int, Int) {
        var lo = 0, hi = 16
        while lo < hi {
            let mid = (lo + hi) >> 1
            if count < totals[mid] { hi = mid } else { lo = mid + 1 }
        }
        let bin = lo
        var position = bin < 15 ? bin << shift : last
        let end = bin < 15 ? min(position + (1 << shift), counts.count) : counts.count
        var start = bin > 0 ? totals[min(bin - 1, 15)] : 0
        while position < end {
            try budget.spend()
            let entry = counts[position]
            if count < start + entry { return (position, start) }
            start += entry; position += 1
        }
        throw GRFError.invalid("Oodle-0 symbol lies outside its arithmetic model.")
    }
    func incrementTotals(_ value: Int, _ amount: Int) {
        if value >= last { totals[15] = (totals[15] + amount) & 0xffff; return }
        for i in (value >> shift)..<16 { totals[i] = (totals[i] + amount) & 0xffff }
    }
    func increment(_ value: Int, _ amount: Int) {
        incrementTotals(value, amount); counts[value] = (counts[value] + amount) & 0xffff
    }
    func decrement(_ value: Int, _ amount: Int) {
        counts[value] = (counts[value] - amount) & 0xffff
        incrementTotals(value, -amount)
    }
    func rescale() throws {
        (shift, last) = oodleBestShift(number + 1)
        var bins = [Int](repeating: 0, count: 16)
        counts[0] >>= 1; bins[last > 0 ? 0 : 15] += counts[0]
        var maxCount = 0, maxPosition = 0, index = 1, done = false
        while index <= number && !done {
            try budget.spend()
            while counts[index] <= 1 {
                try budget.spend()
                if index < number {
                    counts[index] = counts[number]; values[index] = values[number]
                    counts[number] = 0; number -= 1
                } else { counts[index] = 0; number -= 1; done = true; break }
            }
            if done { break }
            counts[index] >>= 1
            if counts[index] > maxCount { maxCount = counts[index]; maxPosition = index }
            bins[bucket(index)] += counts[index]; index += 1
        }
        if maxCount > 0 {
            var swapPosition = number < last ? (number >> shift) << shift : last
            if swapPosition == 0 { swapPosition = 1 }
            guard swapPosition < counts.count else { throw GRFError.invalid("Invalid Oodle-0 rescale position.") }
            if maxPosition != swapPosition {
                let oldCount = counts[swapPosition]
                counts[swapPosition] = counts[maxPosition]
                bins[bucket(swapPosition)] += -oldCount + counts[swapPosition]
                bins[bucket(maxPosition)] += oldCount - counts[swapPosition]
                counts[maxPosition] = oldCount
                values.swapAt(swapPosition, maxPosition)
            }
        }
        if number != unique && counts[0] == 0 {
            counts[0] = (counts[0] + 2) & 0xffff; bins[last > 0 ? 0 : 15] += 2
        }
        var running = 0
        for i in 0..<16 { running += bins[i]; totals[i] = running & 0xffff }
    }
    func bucket(_ value: Int) -> Int { value < last ? value >> shift : 15 }
}
