import Foundation

public struct ScriptPreview: Sendable {
    public let format: String
    public let text: String
}

/// Reads source or lists Lua bytecode. It never loads a Lua runtime or executes code.
public enum LuaPreviewer {
    public static func preview(_ data: Data, encoding: FilenameEncoding = .korean) throws -> ScriptPreview {
        if data.starts(with: [0x1b, 0x4c, 0x75, 0x61]) {
            guard data.count >= 12 else { throw GRFError.invalid("Truncated Lua bytecode header.") }
            let version = data[4]
            if version != 0x51 {
                return ScriptPreview(format: "Lua bytecode", text: "Compiled Lua \(version >> 4).\(version & 15) bytecode\nThis version is not supported by the Lua 5.1 disassembler.\n\n" + hex(data))
            }
            guard data.count <= 16 * 1024 * 1024 else { throw GRFError.invalid("Lua bytecode exceeds the 16 MiB preview limit.") }
            var parser = Lua51Listing(data: data, encoding: encoding)
            return ScriptPreview(format: "Lua 5.1 bytecode", text: try parser.listing())
        }
        if data.starts(with: [0x1b, 0x4c, 0x4a]) {
            return ScriptPreview(format: "LuaJIT bytecode", text: "Compiled LuaJIT bytecode (not Lua 5.1 format).\n\n" + hex(data))
        }
        let limit = 512 * 1024
        let sample = Data(data.prefix(limit))
        let truncated = data.count > sample.count
        var decoded: String?
        if sample.starts(with: [0xff, 0xfe]) || sample.starts(with: [0xfe, 0xff]) {
            decoded = String(data: sample, encoding: .utf16)
        } else {
            // A bounded prefix can end in the middle of a multibyte character.
            for trim in 0...(truncated ? min(3, sample.count) : 0) {
                if let text = String(data: sample.dropLast(trim), encoding: .utf8) { decoded = text; break }
            }
            if decoded == nil {
                for legacy in [encoding, .traditionalChinese] {
                    for trim in 0...(truncated ? min(1, sample.count) : 0) {
                        if let text = try? legacy.decode(Data(sample.dropLast(trim))) { decoded = text; break }
                    }
                    if decoded != nil { break }
                }
            }
        }
        guard let text = decoded, !text.unicodeScalars.contains(where: { $0.value < 32 && ![9, 10, 13].contains($0.value) }) else {
            return ScriptPreview(format: "Binary script", text: "This file is binary or uses an unsupported text encoding.\n\n" + hex(data))
        }
        return ScriptPreview(format: "Lua source", text: text + (truncated ? "\n\n-- Preview truncated at 512 KiB. Extract the file to view the complete source." : ""))
    }

    private static func hex(_ data: Data) -> String {
        let b = Array(data.prefix(512))
        return stride(from: 0, to: b.count, by: 16).map { offset in
            String(format: "%08X  ", offset) + b[offset..<min(offset + 16, b.count)].map { String(format: "%02X", $0) }.joined(separator: " ")
        }.joined(separator: "\n")
    }
}

private struct LuaFunctionListing {
    let source: String
    let firstLine: Int
    let lastLine: Int
    let parameters: Int
    let upvalues: Int
    let stack: Int
    let instructions: [UInt32]
    let constants: [String]
    let children: [LuaFunctionListing]
    let lines: [Int]
}

private struct Lua51Listing {
    var reader: BinaryReader
    let encoding: FilenameEncoding
    var littleEndian = true
    var integerSize = 4
    var stringSize = 4
    var numberSize = 8
    var integralNumbers = false
    var itemBudget = 1_000_000
    var functionBudget = 4096
    init(data: Data, encoding: FilenameEncoding) { reader = BinaryReader(data); self.encoding = encoding }

    mutating func listing() throws -> String {
        _ = try reader.take(5)
        guard try reader.u8() == 0 else { throw GRFError.invalid("Unsupported Lua bytecode format.") }
        let endian = try reader.u8()
        guard endian <= 1 else { throw GRFError.invalid("Invalid Lua byte order.") }
        littleEndian = endian == 1
        integerSize = Int(try reader.u8()); stringSize = Int(try reader.u8())
        let instructionSize = try reader.u8()
        numberSize = Int(try reader.u8())
        let integral = try reader.u8()
        guard [4, 8].contains(integerSize), [4, 8].contains(stringSize), instructionSize == 4,
              [4, 8].contains(numberSize), integral <= 1 else { throw GRFError.invalid("Unsupported Lua bytecode numeric layout.") }
        integralNumbers = integral == 1
        let function = try parseFunction(parent: "(chunk)", depth: 0)
        guard reader.remaining == 0 else { throw GRFError.invalid("Unexpected trailing Lua bytecode data.") }
        var writer = LuaListingWriter()
        writer.add("-- Compiled Lua 5.1 bytecode · disassembly, not recovered source")
        writer.add("-- \(littleEndian ? "Little" : "Big") endian · \(integerSize * 8)-bit integers · \(stringSize * 8)-bit string sizes")
        writer.write(function, name: "main")
        if writer.truncated { writer.lines.append("\n-- Listing truncated. Extract the file for a complete external analysis.") }
        return writer.lines.joined(separator: "\n")
    }

    mutating func uint(_ size: Int) throws -> UInt64 {
        let bytes = try reader.take(size)
        let ordered = littleEndian ? bytes : bytes.reversed().map { $0 }
        return ordered.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << ($1.offset * 8) }
    }
    mutating func count() throws -> Int {
        let n = try uint(integerSize)
        guard n <= 1_000_000, n <= itemBudget else { throw GRFError.invalid("Lua bytecode exceeds the preview item limit.") }
        itemBudget -= Int(n)
        return Int(n)
    }
    mutating func string() throws -> String? {
        let length = try uint(stringSize)
        if length == 0 { return nil }
        guard length <= reader.remaining else { throw GRFError.invalid("Truncated Lua string.") }
        let bytes = try reader.take(Int(length))
        guard bytes.last == 0 else { throw GRFError.invalid("Lua string is missing its terminator.") }
        let content = Data(bytes.dropLast().prefix(512))
        var decoded = String(data: content, encoding: .utf8)
        if decoded == nil, bytes.count > 513 {
            for trim in 1...min(3, content.count) {
                if let text = String(data: content.dropLast(trim), encoding: .utf8) { decoded = text; break }
            }
        }
        decoded = decoded ?? (try? encoding.decode(content)) ?? (try? FilenameEncoding.traditionalChinese.decode(content))
        return (decoded ?? content.map { String(format: "\\x%02X", $0) }.joined()) + (bytes.count > 513 ? "…" : "")
    }
    mutating func number() throws -> String {
        let bits = try uint(numberSize)
        if integralNumbers { return numberSize == 8 ? String(Int64(bitPattern: bits)) : String(Int32(bitPattern: UInt32(bits))) }
        return numberSize == 8 ? String(Double(bitPattern: bits)) : String(Float(bitPattern: UInt32(bits)))
    }
    mutating func parseFunction(parent: String, depth: Int) throws -> LuaFunctionListing {
        guard depth < 64, functionBudget > 0 else { throw GRFError.invalid("Lua function nesting exceeds the preview limit.") }
        functionBudget -= 1
        let source = try string() ?? parent
        let first = try uint(integerSize), last = try uint(integerSize)
        guard first <= Int32.max, last <= Int32.max else { throw GRFError.invalid("Invalid Lua source line numbers.") }
        let upvalues = Int(try reader.u8()), parameters = Int(try reader.u8())
        _ = try reader.u8() // vararg flags
        let stack = Int(try reader.u8())
        let instructionCount = try count()
        guard instructionCount <= reader.remaining / 4 else { throw GRFError.invalid("Truncated Lua instructions.") }
        var instructions: [UInt32] = []
        for _ in 0..<instructionCount { instructions.append(UInt32(try uint(4))) }
        let constantCount = try count()
        var constants: [String] = []
        for _ in 0..<constantCount {
            switch try reader.u8() {
            case 0: constants.append("nil")
            case 1: constants.append(try reader.u8() == 0 ? "false" : "true")
            case 3: constants.append(try number())
            case 4: constants.append(String(reflecting: try string() ?? ""))
            default: throw GRFError.invalid("Unknown Lua constant type.")
            }
        }
        let childCount = try count()
        var children: [LuaFunctionListing] = []
        for _ in 0..<childCount { children.append(try parseFunction(parent: source, depth: depth + 1)) }
        let lineCount = try count()
        guard lineCount == 0 || lineCount == instructionCount else { throw GRFError.invalid("Invalid Lua line table.") }
        var lines: [Int] = []
        for _ in 0..<lineCount {
            let line = try uint(integerSize)
            guard line <= Int32.max else { throw GRFError.invalid("Invalid Lua line number.") }
            lines.append(Int(line))
        }
        let localCount = try count()
        for _ in 0..<localCount { _ = try string(); _ = try uint(integerSize); _ = try uint(integerSize) }
        let upvalueCount = try count()
        for _ in 0..<upvalueCount { _ = try string() }
        return LuaFunctionListing(source: source, firstLine: Int(first), lastLine: Int(last), parameters: parameters,
                                  upvalues: upvalues, stack: stack, instructions: instructions, constants: constants, children: children, lines: lines)
    }
}

private struct LuaListingWriter {
    var lines: [String] = []
    var characters = 0
    var truncated = false
    mutating func add(_ text: String) {
        guard lines.count < 10000, characters + text.count < 750000 else { truncated = true; return }
        lines.append(text); characters += text.count
    }
    mutating func write(_ function: LuaFunctionListing, name: String) {
        guard !truncated else { return }
        add("\nfunction \(name) · \(String(reflecting: function.source)):\(function.firstLine)-\(function.lastLine)")
        add("  \(function.parameters) parameters · \(function.upvalues) upvalues · \(function.stack) registers · \(function.instructions.count) instructions")
        for (index, value) in function.constants.enumerated() { add("  K[\(index)] = \(value)"); if truncated { return } }
        let opcodes = ["MOVE", "LOADK", "LOADBOOL", "LOADNIL", "GETUPVAL", "GETGLOBAL", "GETTABLE", "SETGLOBAL", "SETUPVAL", "SETTABLE", "NEWTABLE", "SELF", "ADD", "SUB", "MUL", "DIV", "MOD", "POW", "UNM", "NOT", "LEN", "CONCAT", "JMP", "EQ", "LT", "LE", "TEST", "TESTSET", "CALL", "TAILCALL", "RETURN", "FORLOOP", "FORPREP", "TFORLOOP", "SETLIST", "CLOSE", "CLOSURE", "VARARG"]
        var extraArgument = false
        for (pc, instruction) in function.instructions.enumerated() {
            if extraArgument { add("  \(pc + 1) EXTRAARG \(instruction)"); extraArgument = false; continue }
            let op = Int(instruction & 63), a = (instruction >> 6) & 255
            let c = (instruction >> 14) & 511, b = (instruction >> 23) & 511, bx = Int(instruction >> 14)
            let opcode = op < opcodes.count ? opcodes[op] : "UNKNOWN_\(op)"
            let args: String
            if [1, 5, 7, 36].contains(op) { args = "A=\(a) Bx=\(bx)" }
            else if [22, 31, 32].contains(op) { args = "A=\(a) sBx=\(bx - 131071) → \(pc + 2 + bx - 131071)" }
            else { args = "A=\(a) B=\(b) C=\(c)" }
            let constant = [1, 5, 7].contains(op) && function.constants.indices.contains(bx) ? " ; \(function.constants[bx])" : ""
            let line = function.lines.indices.contains(pc) ? String(function.lines[pc]) : "-"
            add(String(format: "  %05d", pc + 1) + " [\(line)] " + opcode.padding(toLength: 12, withPad: " ", startingAt: 0) + args + constant)
            extraArgument = op == 34 && c == 0
            if truncated { return }
        }
        for (index, child) in function.children.enumerated() { write(child, name: name + ".\(index)") }
    }
}
