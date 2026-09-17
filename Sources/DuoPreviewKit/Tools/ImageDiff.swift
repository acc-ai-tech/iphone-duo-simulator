import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Pixel difference between two screenshots.
struct ImageDiffResult {
    var changedPixels: Int
    var totalPixels: Int
    /// Dimmed current image with changed pixels painted red; `nil` when nothing changed.
    var highlight: UIImage?

    var changedFraction: Double { totalPixels == 0 ? 0 : Double(changedPixels) / Double(totalPixels) }
}

enum ImageDiff {

    /// Blacks out `rects` (in points) in an image.
    static func masking(_ image: UIImage, rects: [CGRect]) -> UIImage {
        guard !rects.isEmpty else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            image.draw(at: .zero)
            UIColor.black.setFill()
            rects.forEach { context.fill($0) }
        }
    }

    /// Compares images with `CIDifferenceBlendMode` and counts pixels whose max channel delta exceeds `threshold` (0–255).
    static func compare(_ reference: UIImage, _ current: UIImage, threshold: Int) -> ImageDiffResult {
        guard let refCG = reference.cgImage, let curCG = current.cgImage else {
            return ImageDiffResult(changedPixels: 0, totalPixels: 0, highlight: nil)
        }
        guard refCG.width == curCG.width, refCG.height == curCG.height else {
            let total = curCG.width * curCG.height
            return ImageDiffResult(changedPixels: total, totalPixels: total, highlight: current)
        }

        let filter = CIFilter.differenceBlendMode()
        filter.inputImage = CIImage(cgImage: curCG)
        filter.backgroundImage = CIImage(cgImage: refCG)
        let width = curCG.width, height = curCG.height
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        // A fresh context without intermediate caching: a shared context returned stale (all-zero) results
        // for renderer-produced CGImages compared one after another.
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let output = filter.outputImage,
              let diffCG = context.createCGImage(output, from: CGRect(x: 0, y: 0, width: width, height: height),
                                                 format: .RGBA8, colorSpace: sRGB) else {
            return ImageDiffResult(changedPixels: 0, totalPixels: 0, highlight: nil)
        }

        // Draw into a buffer with a known layout (RGBA8, top row first) to count pixels.
        var diff = [UInt8](repeating: 0, count: width * height * 4)
        diff.withUnsafeMutableBytes { buffer in
            let bitmap = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: width * 4, space: sRGB,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            bitmap?.draw(diffCG, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        var changedIndices: [Int] = []
        var changed = 0
        for pixel in 0..<(width * height) {
            let o = pixel * 4
            if Int(max(diff[o], diff[o + 1], diff[o + 2])) > threshold {
                changed += 1
                if changedIndices.count < 2_000_000 { changedIndices.append(pixel) }
            }
        }
        guard changed > 0 else {
            return ImageDiffResult(changedPixels: 0, totalPixels: width * height, highlight: nil)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let highlight = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIImage(cgImage: curCG).draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.black.withAlphaComponent(0.6).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.systemRed.setFill()
            for pixel in changedIndices {
                let x = pixel % width
                let y = pixel / width
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return ImageDiffResult(changedPixels: changed, totalPixels: width * height, highlight: highlight)
    }
}
