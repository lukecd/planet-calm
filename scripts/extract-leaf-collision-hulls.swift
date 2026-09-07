// Read-only asset extraction. Run from the repository root; JSON is emitted to stdout.
// Source images are never modified. Commit the output through the normal edit workflow.
import Foundation
import CoreGraphics
import ImageIO
import CryptoKit

struct Point: Encodable {
    let x: Double
    let y: Double
}
struct Shape: Encodable {
    let assetID: String
    let sourceSHA256: String
    let sourcePixelWidth: Int
    let sourcePixelHeight: Int
    let hull: [Point]
}
struct Catalog: Encodable {
    let alphaThreshold = 128
    // Measured native solver separation, compensated in geometry, not sprite pose.
    let contactInsetPoints = 2.5
    let shapes: [Shape]
}
func cross(_ a: Point, _ b: Point, _ c: Point) -> Double {
    (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
}
func convexHull(_ points: [Point]) -> [Point] {
    let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
    func half(_ list: [Point]) -> [Point] {
        var result: [Point] = []
        for p in list {
            while result.count >= 2 && cross(result[result.count - 2], result.last!, p) <= 0 {
                result.removeLast()
            }
            result.append(p)
        }
        return Array(result.dropLast())
    }
    return half(sorted) + half(sorted.reversed())
}
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
var shapes: [Shape] = []
for color in ["red", "orange", "yellow", "olive"] {
    let id = "leaf-maple-\(color)"
    let url = root.appendingPathComponent("PlanetCalm/Assets/Stories/AutumnTree/SceneV1/\(id).png")
    let data = try Data(contentsOf: url)
    let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(data as CFData, nil)!, 0, nil)!
    let w = image.width, h = image.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    pixels.withUnsafeMutableBytes { bytes in
        let context = CGContext(data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    var extremes: [Point] = []
    // Every row's two opaque extremes preserve every directional support extreme.
    for y in 0..<h {
        let row = (0..<w).filter { pixels[(y * w + $0) * 4 + 3] >= 128 }
        guard let first = row.first, let last = row.last else { continue }
        for x in [first, last] {
            // Integer pixel coordinates keep collinearity exact during hull extraction.
            extremes.append(Point(x: Double(x), y: Double(h - 1 - y)))
        }
    }
    shapes.append(Shape(assetID: id, sourceSHA256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
        sourcePixelWidth: w, sourcePixelHeight: h, hull: convexHull(extremes).map {
            Point(x: ($0.x + 0.5) / Double(w) - 0.5, y: ($0.y + 0.5) / Double(h) - 0.5)
        }))
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
print(String(decoding: try encoder.encode(Catalog(shapes: shapes)), as: UTF8.self))
