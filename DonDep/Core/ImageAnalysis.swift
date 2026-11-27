import Foundation
import CoreGraphics
import Vision
import Photos
import UIKit

/// Các thuật toán phân tích ảnh chạy hoàn toàn trên máy.
enum ImageAnalysis {

    struct Metrics {
        var hash: [UInt64]      // 256-bit dHash (4 x UInt64)
        var blur: Float         // phương sai Laplacian, càng thấp càng mờ
        var brightness: Float   // 0...255
    }

    // MARK: Tải ảnh thu nhỏ đồng bộ (gọi trên luồng nền)

    static func loadCGImage(_ asset: PHAsset, side: CGFloat, allowNetwork: Bool) -> CGImage? {
        let opts = PHImageRequestOptions()
        opts.isSynchronous = true
        opts.deliveryMode = .highQualityFormat
        opts.resizeMode = .fast
        opts.isNetworkAccessAllowed = allowNetwork
        opts.version = .current
        var result: CGImage?
        PHImageManager.default().requestImage(for: asset,
                                              targetSize: CGSize(width: side, height: side),
                                              contentMode: .aspectFit,
                                              options: opts) { image, _ in
            if let cg = image?.cgImage { result = cg }
        }
        return result
    }

    // MARK: Pixel xám

    static func grayPixels(_ image: CGImage, width: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let cs = CGColorSpaceCreateDeviceGray()
        pixels.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(data: ptr.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return pixels
    }

    // MARK: Chỉ số

    static func metrics(_ image: CGImage) -> Metrics {
        // dHash 256 bit: lưới 17x16, so sánh pixel kề nhau theo hàng.
        let hp = grayPixels(image, width: 17, height: 16)
        var words = [UInt64](repeating: 0, count: 4)
        var bit = 0
        for row in 0..<16 {
            for col in 0..<16 {
                if hp[row * 17 + col] > hp[row * 17 + col + 1] {
                    words[bit >> 6] |= (UInt64(1) << UInt64(bit & 63))
                }
                bit += 1
            }
        }

        // Độ nét: phương sai Laplacian trên ảnh xám cạnh dài 360px.
        let maxSide = 360.0
        let w0 = Double(image.width), h0 = Double(image.height)
        let scale = min(1.0, maxSide / max(w0, h0))
        let w = max(8, Int(w0 * scale)), h = max(8, Int(h0 * scale))
        let p = grayPixels(image, width: w, height: h)

        var sum = 0.0, sumSq = 0.0, bright = 0.0
        var n = 0.0
        p.withUnsafeBufferPointer { b in
            for v in b { bright += Double(v) }
            for y in 1..<(h - 1) {
                let base = y * w
                for x in 1..<(w - 1) {
                    let i = base + x
                    let lap = Int(b[i - 1]) + Int(b[i + 1]) + Int(b[i - w]) + Int(b[i + w]) - 4 * Int(b[i])
                    let d = Double(lap)
                    sum += d
                    sumSq += d * d
                    n += 1
                }
            }
        }
        let mean = n > 0 ? sum / n : 0
        let variance = n > 0 ? sumSq / n - mean * mean : 0
        return Metrics(hash: words,
                       blur: Float(variance),
                       brightness: Float(bright / Double(max(1, p.count))))
    }

    // MARK: Vision feature print (AI so sánh độ giống nhau)

    static func featurePrint(_ image: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        return request.results?.first
    }

    static func archive(_ obs: VNFeaturePrintObservation) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: obs, requiringSecureCoding: true)
    }

    static func unarchive(_ data: Data) -> VNFeaturePrintObservation? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }

    static func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float? {
        var d: Float = 0
        do {
            try a.computeDistance(&d, to: b)
            return d
        } catch {
            return nil
        }
    }

    // MARK: Hash helpers

    static func hamming(_ a: [UInt64], _ b: [UInt64]) -> Int {
        var d = 0
        for i in 0..<min(a.count, b.count) { d += (a[i] ^ b[i]).nonzeroBitCount }
        return d
    }

    static func hashToData(_ h: [UInt64]) -> Data {
        h.withUnsafeBytes { Data($0) }
    }

    static func dataToHash(_ d: Data) -> [UInt64] {
        guard d.count == 32 else { return [] }
        var out = [UInt64](repeating: 0, count: 4)
        _ = out.withUnsafeMutableBytes { d.copyBytes(to: $0) }
        return out
    }

    // MARK: Dung lượng file

    static func fileSize(of asset: PHAsset) -> Int64 {
        PHAssetResource.assetResources(for: asset).reduce(Int64(0)) { sum, res in
            sum + ((res.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0)
        }
    }
}

// MARK: - Union-Find

struct UnionFind {
    private var parent: [Int]
    init(_ n: Int) { parent = Array(0..<n) }
    mutating func find(_ x: Int) -> Int {
        var r = x
        while parent[r] != r { r = parent[r] }
        var c = x
        while parent[c] != r { let next = parent[c]; parent[c] = r; c = next }
        return r
    }
    mutating func union(_ a: Int, _ b: Int) {
        let ra = find(a), rb = find(b)
        if ra != rb { parent[rb] = ra }
    }
    mutating func groups(minSize: Int = 2) -> [[Int]] {
        var dict: [Int: [Int]] = [:]
        for i in 0..<parent.count { dict[find(i), default: []].append(i) }
        return dict.values.filter { $0.count >= minSize }.map { $0.sorted() }
    }
}
