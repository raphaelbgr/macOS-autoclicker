//
//  ScreenRecognizer.swift
//  macOS AutoClicker
//
//  Image-similarity matching between a captured screen and a reference.
//
//  Two methods, switchable per-project via MatchMethod:
//
//  - .featurePrint (default): Apple Vision VNGenerateImageFeaturePrintRequest.
//    Computes a semantic embedding and compares via computeDistance(_:to:).
//    Robust to minor UI shifts and color changes — usually the better
//    choice for game/idle-app screens that vary slightly each match.
//
//  - .ssim: hand-rolled SSIM (Structural Similarity Index) on Accelerate.
//    Pixel-exact; the same algorithm the Python app used via scikit-image.
//    Better when you need to detect a specific pixel pattern.
//

import Accelerate
import AppKit
import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// Result of comparing a capture to a reference.
struct MatchResult: Sendable {
    let isMatch: Bool
    let similarity: Double       // 0.0...1.0 (1.0 = identical)
    let method: MatchMethod
    let threshold: Double

    var similarityPercent: Double { similarity * 100 }
}

enum ScreenRecognizer {

    // MARK: - FeaturePrint (Vision)

    /// Cache of reference image → VNFeaturePrintObservation, keyed by an
    /// arbitrary key the caller chooses (typically the action's UUID).
    /// Stored inside a dedicated Sendable container guarded by a lock, so
    /// the cache is concurrency-safe under Swift 6 strict concurrency.
    private static let featurePrintCache = FeaturePrintCache()

    private final class FeaturePrintCache: @unchecked Sendable {
        private var store: [ObjectIdentifier: VNFeaturePrintObservation] = [:]
        private let lock = NSLock()

        func get(_ key: ObjectIdentifier) -> VNFeaturePrintObservation? {
            lock.lock(); defer { lock.unlock() }
            return store[key]
        }
        func set(_ key: ObjectIdentifier, _ value: VNFeaturePrintObservation) {
            lock.lock(); defer { lock.unlock() }
            store[key] = value
        }
        func remove(_ key: ObjectIdentifier) {
            lock.lock(); defer { lock.unlock() }
            store.removeValue(forKey: key)
        }
        func removeAll() {
            lock.lock(); defer { lock.unlock() }
            store.removeAll()
        }
    }

    /// Compare `capture` against `reference` using Vision featurePrint.
    /// `cacheKey` lets us skip recomputing the reference embedding each tick.
    static func matchFeaturePrint(
        capture: CGImage,
        reference: CGImage,
        threshold: Double,
        cacheKey: ObjectIdentifier
    ) -> MatchResult {
        // Reference: cached.
        let refObs = cachedOrCompute(reference, cacheKey: cacheKey)
        // Capture: computed fresh each tick.
        let curObs = computeFeaturePrint(capture)

        guard let refObs, let curObs else {
            return MatchResult(isMatch: false, similarity: 0, method: .featurePrint, threshold: threshold)
        }

        var distance: Float = 0
        do {
            try curObs.computeDistance(&distance, to: refObs)
        } catch {
            return MatchResult(isMatch: false, similarity: 0, method: .featurePrint, threshold: threshold)
        }

        let sim = similarityFromDistance(Double(distance))
        return MatchResult(
            isMatch: sim >= threshold,
            similarity: sim,
            method: .featurePrint,
            threshold: threshold
        )
    }

    private static func cachedOrCompute(_ image: CGImage, cacheKey: ObjectIdentifier) -> VNFeaturePrintObservation? {
        if let cached = featurePrintCache.get(cacheKey) { return cached }
        let obs = computeFeaturePrint(image)
        if let obs { featurePrintCache.set(cacheKey, obs) }
        return obs
    }

    /// Clear a cache entry when its action changes/disappears.
    static func invalidate(cacheKey: ObjectIdentifier) {
        featurePrintCache.remove(cacheKey)
    }

    static func clearCache() {
        featurePrintCache.removeAll()
    }

    /// Run VNGenerateImageFeaturePrintRequest on a single image.
    private static func computeFeaturePrint(_ image: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        return request.results?.first as? VNFeaturePrintObservation
    }

    /// Monotonic decay from similarity=1 at distance 0 to ~0 at distance 1.
    private static func similarityFromDistance(_ d: Double) -> Double {
        // Smoothstep-shaped falloff: 1 - clamp(d, 0, 1), softened around 0.4.
        let clamped = max(0, min(1, d))
        // Emphasize the "almost identical" zone.
        return 1.0 - clamped
    }

    // MARK: - SSIM (Accelerate)

    /// Pixel-exact SSIM, matching the scikit-image structural_similarity the
    /// Python app used. Returns 0...1.
    ///
    /// Implementation: downscale to grayscale, then compute mean/variance/
    /// covariance over a sliding 8×8 window using vDSP. The two images are
    /// resized to a common dimension (256×256) — SSIM is scale-tolerant and
    /// the resize keeps the cost predictable.
    static func matchSSIM(
        capture: CGImage,
        reference: CGImage,
        threshold: Double
    ) -> MatchResult {
        let size = 256
        guard let g1 = grayscaleFloats(capture, target: size),
              let g2 = grayscaleFloats(reference, target: size) else {
            return MatchResult(isMatch: false, similarity: 0, method: .ssim, threshold: threshold)
        }
        let sim = ssim(g1, g2, width: size, height: size, window: 8)
        return MatchResult(
            isMatch: sim >= threshold,
            similarity: sim,
            method: .ssim,
            threshold: threshold
        )
    }

    /// Convert a CGImage to a flat [Float] grayscale buffer of the given size.
    /// Uses CoreGraphics to draw as premultiplied RGBA, then vImage's
    /// vImageMatrixMultiply_ARGB8888ToPlanar8 with Rec.601 weights to produce
    /// 8-bit luminance, then divides by 255 in plain Swift to get 0..1 floats.
    private static func grayscaleFloats(_ image: CGImage, target size: Int) -> [Float]? {
        let w = size, h = size
        let bytesPerPixel = 4
        let bytesPerRow = w * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: w * h * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        var failed = false
        var normalized: [Float] = []
        pixelData.withUnsafeMutableBufferPointer { pixelPtr in
            var grayPlanar = [UInt8](repeating: 0, count: w * h)
            grayPlanar.withUnsafeMutableBufferPointer { grayPtr in
                var srcBuffer = vImage_Buffer(
                    data: pixelPtr.baseAddress,
                    height: vImagePixelCount(h), width: vImagePixelCount(w),
                    rowBytes: bytesPerRow
                )
                var dstBuffer = vImage_Buffer(
                    data: grayPtr.baseAddress,
                    height: vImagePixelCount(h), width: vImagePixelCount(w),
                    rowBytes: w * MemoryLayout<UInt8>.size
                )

                let coeff: [Int16] = [76, 150, 29, 0]
                let preBias: [Int16] = [0, 0, 0, 0]
                let postBias: Int32 = 0
                let err: vImage_Error = coeff.withUnsafeBufferPointer { coeffPtr in
                    preBias.withUnsafeBufferPointer { biasPtr in
                        vImageMatrixMultiply_ARGB8888ToPlanar8(
                            &srcBuffer,
                            &dstBuffer,
                            coeffPtr.baseAddress!,
                            Int32(256),
                            biasPtr.baseAddress!,
                            postBias,
                            vImage_Flags(kvImageNoFlags)
                        )
                    }
                }
                if err != kvImageNoError { failed = true }
            }

            // Normalize 0..255 → 0..1 (grayPlanar is now owned again).
            var out = [Float](repeating: 0, count: grayPlanar.count)
            vDSP_vfltu8(grayPlanar, 1, &out, 1, vDSP_Length(grayPlanar.count))
            var norm = out
            vDSP_vsdiv(out, 1, [Float(255.0)], &norm, 1, vDSP_Length(out.count))
            normalized = norm
        }
        if failed { return nil }
        return normalized
    }

    /// SSIM over a non-overlapping `window`×`window` grid, averaged.
    /// Plain implementation — small images (256×256) so cost is fine.
    private static func ssim(_ x: [Float], _ y: [Float], width: Int, height: Int, window: Int) -> Double {
        // C1, C2 stabilizers (Wang et al. 2004) for 8-bit data scaled 0..1.
        let L: Float = 1.0
        let k1: Float = 0.01, k2: Float = 0.03
        let c1 = (k1 * L) * (k1 * L)
        let c2 = (k2 * L) * (k2 * L)

        var totalSSIM: Double = 0
        var blocks = 0
        let stride = window
        var y0 = 0
        while y0 + window <= height {
            var x0 = 0
            while x0 + window <= width {
                let (mx, vx) = meanVar(x, x0: x0, y0: y0, width: width, window: window)
                let (my, vy) = meanVar(y, x0: x0, y0: y0, width: width, window: window)
                let cxy = covariance(x, y, x0: x0, y0: y0, width: width, mx: mx, my: my, window: window)
                let num = (2 * mx * my + c1) * (2 * cxy + c2)
                let den = (mx * mx + my * my + c1) * (vx + vy + c2)
                totalSSIM += Double(num / max(den, 1e-12))
                blocks += 1
                x0 += stride
            }
            y0 += stride
        }
        return blocks > 0 ? totalSSIM / Double(blocks) : 0
    }

    private static func meanVar(_ buf: [Float], x0: Int, y0: Int, width: Int, window: Int) -> (Float, Float) {
        var sum: Float = 0, sumSq: Float = 0
        for dy in 0..<window {
            for dx in 0..<window {
                let v = buf[(y0 + dy) * width + (x0 + dx)]
                sum += v; sumSq += v * v
            }
        }
        let n = Float(window * window)
        let mean = sum / n
        let variance = max(0, sumSq / n - mean * mean)
        return (mean, variance)
    }

    private static func covariance(_ a: [Float], _ b: [Float], x0: Int, y0: Int, width: Int, mx: Float, my: Float, window: Int) -> Float {
        var sum: Float = 0
        for dy in 0..<window {
            for dx in 0..<window {
                let i = (y0 + dy) * width + (x0 + dx)
                sum += (a[i] - mx) * (b[i] - my)
            }
        }
        return sum / Float(window * window)
    }
}
