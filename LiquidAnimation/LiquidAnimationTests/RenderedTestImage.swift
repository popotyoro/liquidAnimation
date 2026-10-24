import CoreGraphics
import Foundation
import Testing
import UIKit

/// 各テストが所有する画像。画像はテスト結果へ添付し、共有ファイルへ書き出さない。
@MainActor
struct RenderedTestImage {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init(_ image: UIImage, name: String) throws {
        let cgImage = try #require(image.cgImage)
        width = cgImage.width
        height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: cgImage.width,
                                                height: cgImage.height, bitsPerComponent: 8,
                                                bytesPerRow: cgImage.width * 4,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        bytes = pixels
        Attachment.record(try #require(image.pngData()), named: "\(name).png")
    }

    func countPixels(in region: CGRect? = nil, matching predicate: (Int, Int, Int) -> Bool) -> Int {
        let area = (region ?? CGRect(x: 0, y: 0, width: width, height: height))
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !area.isEmpty else { return 0 }
        var count = 0
        for y in Int(area.minY)..<Int(area.maxY) {
            for x in Int(area.minX)..<Int(area.maxX) {
                let offset = (y * width + x) * 4
                if predicate(Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2])) {
                    count += 1
                }
            }
        }
        return count
    }

    var cyanPixelCount: Int {
        countPixels { red, green, blue in green - red > 15 && blue - red > 15 }
    }

    var darkPixelCount: Int {
        countPixels { red, green, blue in max(red, green, blue) < 90 }
    }

    func differingPixelCount(from other: Self) throws -> Int {
        try #require(width == other.width && height == other.height)
        return stride(from: 0, to: bytes.count, by: 4).filter { offset in
            (0..<3).contains { channel in
                abs(Int(bytes[offset + channel]) - Int(other.bytes[offset + channel])) > 3
            }
        }.count
    }

    /// 液体を描いた最初の行を列ごとに探し、水面の高低差をピクセルで返す。
    var surfaceHeightDifference: Int {
        var heights: [Int] = []
        for x in (width / 4)..<(width * 3 / 4) {
            for y in 0..<height {
                let offset = (y * width + x) * 4
                let red = Int(bytes[offset])
                if Int(bytes[offset + 1]) - red > 15 && Int(bytes[offset + 2]) - red > 15 {
                    heights.append(y)
                    break
                }
            }
        }
        return (heights.max() ?? 0) - (heights.min() ?? 0)
    }
}
