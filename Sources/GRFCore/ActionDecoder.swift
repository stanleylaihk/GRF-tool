import Foundation

public struct ActionDocument: Sendable {
    /// Little-endian version number, e.g. 0x205 for ACT 2.5.
    public let version: Int
    public let actions: [SpriteAction]
    public let sounds: [String]
    /// Equipment ACTs often begin with empty directions/actions. Start on an image.
    public var firstDrawableActionIndex: Int? {
        actions.firstIndex { action in
            action.frames.contains { frame in
                frame.layers.contains { $0.spriteIndex >= 0 && $0.scaleX != 0 && $0.scaleY != 0 && $0.color.count == 4 && $0.color[3] > 0 }
            }
        }
    }
}

public struct SpriteAction: Sendable {
    public let frames: [ActionFrame]
    public let frameDuration: Double
}

public struct ActionFrame: Sendable {
    public let layers: [ActionLayer]
    public let anchors: [ActionAnchor]
    public let soundIndex: Int
}

public struct ActionAnchor: Sendable {
    public let x: Int
    public let y: Int
}

public struct ActionLayer: Sendable {
    public let offsetX: Int
    public let offsetY: Int
    public let spriteIndex: Int
    public let isTruecolor: Bool
    public let mirror: Bool
    public let scaleX: Double
    public let scaleY: Double
    public let rotation: Double
    public let color: [UInt8]
    public let width: Int
    public let height: Int
}

/// Format checked against the RoBrowser ACT loader and Ragnarok Research Lab.
/// Anchors and sound events are retained as metadata; they are not additional image layers.
public enum ActionDecoder {
    public static func decode(_ data: Data, encoding: FilenameEncoding = .korean) throws -> ActionDocument {
        var reader = BinaryReader(data)
        guard try reader.take(2) == [0x41, 0x43] else { throw GRFError.invalid("Invalid ACT signature.") }
        let minor = Int(try reader.u8()), major = Int(try reader.u8())
        let version = major * 256 + minor
        guard version == 0x101 || (0x200...0x205).contains(version) else {
            throw GRFError.invalid("Unsupported ACT version \(major).\(minor).")
        }
        let actionCount = try reader.u16()
        guard actionCount <= 4096 else { throw GRFError.invalid("ACT contains too many actions.") }
        _ = try reader.take(10)
        var decoded: [[ActionFrame]] = []
        var totalFrames = 0, totalLayers = 0
        for _ in 0..<actionCount {
            let count = try reader.u32()
            totalFrames += count
            guard count <= 10000, totalFrames <= 100000 else { throw GRFError.invalid("ACT contains too many frames.") }
            var frames: [ActionFrame] = []
            for _ in 0..<count {
                _ = try reader.take(32)
                let layerCount = try reader.u32()
                totalLayers += layerCount
                guard layerCount <= 4096, totalLayers <= 1_000_000 else { throw GRFError.invalid("ACT contains too many layers.") }
                var layers: [ActionLayer] = []
                for _ in 0..<layerCount {
                    let x = try signed(&reader), y = try signed(&reader), index = try signed(&reader)
                    let mirror = try reader.u32() != 0
                    var color: [UInt8] = [255, 255, 255, 255]
                    var sx = 1.0, sy = 1.0, rotation = 0.0, type = 0, width = 0, height = 0
                    if version >= 0x200 {
                        color = try reader.take(4)
                        sx = try float(&reader)
                        sy = version >= 0x204 ? try float(&reader) : sx
                        rotation = Double(try signed(&reader) % 360)
                        type = try reader.u32()
                        guard type == 0 || type == 1 else { throw GRFError.invalid("Unknown ACT sprite image type.") }
                        if version >= 0x205 {
                            width = try signed(&reader)
                            height = try signed(&reader)
                        }
                    }
                    guard sx.isFinite, sy.isFinite, abs(sx) <= 1000, abs(sy) <= 1000 else {
                        throw GRFError.invalid("Invalid ACT layer scale.")
                    }
                    layers.append(ActionLayer(offsetX: x, offsetY: y, spriteIndex: index,
                                              isTruecolor: type == 1, mirror: mirror, scaleX: sx, scaleY: sy,
                                              rotation: rotation, color: color, width: width, height: height))
                }
                let sound = version >= 0x200 ? try signed(&reader) : -1
                var anchors: [ActionAnchor] = []
                if version >= 0x203 {
                    let count = try reader.u32()
                    guard count <= 4096 else { throw GRFError.invalid("ACT contains too many anchors.") }
                    for _ in 0..<count {
                        _ = try reader.take(4)
                        anchors.append(ActionAnchor(x: try signed(&reader), y: try signed(&reader)))
                        _ = try reader.take(4)
                    }
                }
                frames.append(ActionFrame(layers: layers, anchors: anchors, soundIndex: sound))
            }
            decoded.append(frames)
        }
        var sounds: [String] = []
        if version >= 0x201 {
            let count = try reader.u32()
            guard count <= 10000 else { throw GRFError.invalid("ACT contains too many sound events.") }
            for _ in 0..<count {
                let name = Data(try reader.take(40).prefix(while: { $0 != 0 }))
                sounds.append((try? encoding.decode(name)) ?? String(decoding: name, as: UTF8.self))
            }
        }
        var actions: [SpriteAction] = []
        for frames in decoded {
            var duration = 0.15
            if version >= 0x202 {
                let ticks = try float(&reader)
                guard ticks.isFinite, ticks > 0, ticks <= 25000 else { throw GRFError.invalid("Invalid ACT frame timing.") }
                duration = ticks * 0.024
            }
            actions.append(SpriteAction(frames: frames, frameDuration: duration))
        }
        return ActionDocument(version: version, actions: actions, sounds: sounds)
    }

    private static func signed(_ reader: inout BinaryReader) throws -> Int {
        Int(Int32(bitPattern: UInt32(try reader.u32())))
    }
    private static func float(_ reader: inout BinaryReader) throws -> Double {
        Double(Float(bitPattern: UInt32(try reader.u32())))
    }
}

/// CPU renderer with straight-alpha output, nearest-neighbor sampling and a fixed canvas
/// for the entire action. ACT coordinates use positive Y downward and clockwise degrees.
public enum ActionRenderer {
    private struct Placement {
        let layer: ActionLayer
        let sprite: SpriteFrame
        let sx: Double
        let sy: Double
        let cosine: Double
        let sine: Double
        let minX: Double
        let minY: Double
        let maxX: Double
        let maxY: Double
    }

    public static func render(action: SpriteAction, sprites: [SpriteFrame], indexedCount: Int) throws -> [SpriteFrame] {
        guard indexedCount >= 0, indexedCount <= sprites.count else { throw GRFError.invalid("Invalid SPR indexed-image count.") }
        guard action.frames.count <= 10000 else { throw GRFError.invalid("Too many ACT frames to render.") }
        var placements: [[Placement]] = []
        var drawingBudget = 0.0
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for frame in action.frames {
            var list: [Placement] = []
            for layer in frame.layers where layer.spriteIndex >= 0 && layer.scaleX != 0 && layer.scaleY != 0 {
                let index = layer.spriteIndex + (layer.isTruecolor ? indexedCount : 0)
                guard index < sprites.count, layer.isTruecolor || index < indexedCount else {
                    throw GRFError.invalid("ACT references missing SPR image \(layer.spriteIndex). Choose its matching SPR file.")
                }
                let sprite = sprites[index]
                guard sprite.width > 0, sprite.height > 0, sprite.rgba.count == sprite.width * sprite.height * 4,
                      layer.color.count == 4 else { throw GRFError.invalid("Invalid sprite image data.") }
                let sx = layer.scaleX * (layer.mirror ? -1 : 1), sy = layer.scaleY
                let cosine = cos(layer.rotation * .pi / 180), sine = sin(layer.rotation * .pi / 180)
                var xs: [Double] = [], ys: [Double] = []
                for x in [-Double(sprite.width) / 2, Double(sprite.width) / 2] {
                    for y in [-Double(sprite.height) / 2, Double(sprite.height) / 2] {
                        xs.append(Double(layer.offsetX) + x * sx * cosine - y * sy * sine)
                        ys.append(Double(layer.offsetY) + x * sx * sine + y * sy * cosine)
                    }
                }
                let p = Placement(layer: layer, sprite: sprite, sx: sx, sy: sy, cosine: cosine, sine: sine,
                                  minX: xs.min()!, minY: ys.min()!, maxX: xs.max()!, maxY: ys.max()!)
                guard [p.minX, p.minY, p.maxX, p.maxY].allSatisfy({ $0.isFinite && abs($0) <= 10_000_000 }) else {
                    throw GRFError.invalid("ACT layer bounds are invalid.")
                }
                drawingBudget += (ceil(p.maxX) - floor(p.minX)) * (ceil(p.maxY) - floor(p.minY))
                guard drawingBudget <= 128 * 1024 * 1024 else {
                    throw GRFError.invalid("ACT action contains too many pixels across its layers to preview.")
                }
                minX = min(minX, p.minX); minY = min(minY, p.minY)
                maxX = max(maxX, p.maxX); maxY = max(maxY, p.maxY)
                list.append(p)
            }
            placements.append(list)
        }
        if !minX.isFinite { return action.frames.map { _ in SpriteFrame(width: 1, height: 1, rgba: Data(repeating: 0, count: 4)) } }
        let originX = floor(minX), originY = floor(minY)
        let width = max(1, Int(ceil(maxX) - originX)), height = max(1, Int(ceil(maxY) - originY))
        guard width <= 4096, height <= 4096,
              width * height * 4 * max(1, action.frames.count) <= 256 * 1024 * 1024 else {
            throw GRFError.invalid("Rendered ACT action exceeds the 4096px / 256 MiB preview limit.")
        }
        return placements.map { layers in
            var output = [UInt8](repeating: 0, count: width * height * 4)
            for p in layers {
                let source = [UInt8](p.sprite.rgba)
                let x0 = max(0, Int(floor(p.minX - originX))), x1 = min(width, Int(ceil(p.maxX - originX)))
                let y0 = max(0, Int(floor(p.minY - originY))), y1 = min(height, Int(ceil(p.maxY - originY)))
                guard x1 > x0, y1 > y0 else { continue }
                for y in y0..<y1 {
                    for x in x0..<x1 {
                        let dx = originX + Double(x) + 0.5 - Double(p.layer.offsetX)
                        let dy = originY + Double(y) + 0.5 - Double(p.layer.offsetY)
                        let u = (dx * p.cosine + dy * p.sine) / p.sx + Double(p.sprite.width) / 2
                        let v = (-dx * p.sine + dy * p.cosine) / p.sy + Double(p.sprite.height) / 2
                        guard u >= 0, v >= 0, u < Double(p.sprite.width), v < Double(p.sprite.height) else { continue }
                        let src = (Int(v) * p.sprite.width + Int(u)) * 4, dst = (y * width + x) * 4
                        let alpha = Double(source[src + 3]) / 255 * Double(p.layer.color[3]) / 255
                        guard alpha > 0 else { continue }
                        let oldAlpha = Double(output[dst + 3]) / 255
                        let resultAlpha = alpha + oldAlpha * (1 - alpha)
                        for channel in 0..<3 {
                            let value = Double(source[src + channel]) * Double(p.layer.color[channel]) / 255
                            let blended = (value * alpha + Double(output[dst + channel]) * oldAlpha * (1 - alpha)) / resultAlpha
                            output[dst + channel] = UInt8(clamping: Int(blended.rounded()))
                        }
                        output[dst + 3] = UInt8(clamping: Int((resultAlpha * 255).rounded()))
                    }
                }
            }
            return SpriteFrame(width: width, height: height, rgba: Data(output))
        }
    }
}
