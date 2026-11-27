import Foundation
import Photos
import Vision

struct ScanParams {
    var similarThreshold: Float
    var blurThreshold: Float
    var largeVideoBytes: Int64
    var allowNetwork: Bool
}

final class CancelToken {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

/// Toàn bộ thuật toán quét, chạy trên luồng nền.
enum ScanWorker {

    static let darkThreshold: Float = 18
    static let similarTimeGap: TimeInterval = 90
    static let similarNeighbors = 8

    static func run(params: ScanParams, token: CancelToken,
                    progress: @escaping (Double, String) -> Void) -> ScanResult? {
        progress(0, "Đang đọc thư viện ảnh…")
        let cache = ScanCache.load()

        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let fetch = PHAsset.fetchAssets(with: opts)
        var all: [PHAsset] = []
        all.reserveCapacity(fetch.count)
        fetch.enumerateObjects { a, _, _ in all.append(a) }

        let images = all.filter { $0.mediaType == .image }
        let videos = all.filter { $0.mediaType == .video }
        let normalPhotos = images.filter { !$0.mediaSubtypes.contains(.photoScreenshot) }

        // 1. Cụm theo thời gian chụp (ứng viên ảnh tương tự)
        var clusters: [[PHAsset]] = []
        var current: [PHAsset] = []
        var lastDate: Date?
        for a in normalPhotos {
            guard let d = a.creationDate else { continue }
            if let l = lastDate, d.timeIntervalSince(l) <= similarTimeGap {
                current.append(a)
            } else {
                if current.count >= 2 { clusters.append(current) }
                current = [a]
            }
            lastDate = d
        }
        if current.count >= 2 { clusters.append(current) }
        var candidates = Set<String>()
        for c in clusters { for a in c { candidates.insert(a.localIdentifier) } }

        // 2. Phân tích từng ảnh (song song)
        final class Accumulator {
            let lock = NSLock()
            var entries: [String: ScanEntry] = [:]
            var newPrints: [String: PrintEntry] = [:]
            var livePrints: [String: VNFeaturePrintObservation] = [:]
            var cloudSizes: [String: Int64] = [:]
            var skipped = 0
            var done = 0
        }
        let acc = Accumulator()
        let total = all.count
        let cachedEntries = cache.entries
        let cachedPrints = cache.prints
        let candidateSet = candidates
        let assetsToScan = all

        DispatchQueue.concurrentPerform(iterations: total) { i in
            if token.isCancelled { return }
            autoreleasepool {
                let a = assetsToScan[i]
                let id = a.localIdentifier
                let mod = a.modificationDate?.timeIntervalSince1970 ?? 0
                var entry: ScanEntry? = nil
                if let e = cachedEntries[id], e.mod == mod { entry = e }
                let needPrint = candidateSet.contains(id) && cachedPrints[id]?.mod != mod
                var printObs: VNFeaturePrintObservation?
                var printEntry: PrintEntry?
                var cloudSize: Int64?

                if entry == nil || needPrint {
                    let size = entry?.size ?? ImageAnalysis.fileSize(of: a)
                    if a.mediaType == .image {
                        if let cg = ImageAnalysis.loadCGImage(a, side: 512, allowNetwork: params.allowNetwork) {
                            if entry == nil {
                                let m = ImageAnalysis.metrics(cg)
                                entry = ScanEntry(mod: mod, hash: ImageAnalysis.hashToData(m.hash),
                                                  blur: m.blur, brightness: m.brightness, size: size)
                            }
                            if needPrint, let fp = ImageAnalysis.featurePrint(cg) {
                                printObs = fp
                                if let data = ImageAnalysis.archive(fp) {
                                    printEntry = PrintEntry(mod: mod, data: data)
                                }
                            }
                        } else if entry == nil {
                            cloudSize = size
                        }
                    } else if entry == nil {
                        entry = ScanEntry(mod: mod, hash: Data(), blur: -1, brightness: -1, size: size)
                    }
                }

                acc.lock.lock()
                if let entry { acc.entries[id] = entry }
                if let printObs { acc.livePrints[id] = printObs }
                if let printEntry { acc.newPrints[id] = printEntry }
                if let cloudSize { acc.cloudSizes[id] = cloudSize; acc.skipped += 1 }
                acc.done += 1
                let d = acc.done
                acc.lock.unlock()
                if d % 40 == 0 || d == total {
                    progress(Double(d) / Double(max(total, 1)) * 0.9, "Đang phân tích \(d)/\(total)")
                }
            }
        }
        if token.isCancelled { return nil }

        let entries = acc.entries
        let newPrints = acc.newPrints
        var livePrints = acc.livePrints
        let cloudSizes = acc.cloudSizes
        let skipped = acc.skipped

        progress(0.92, "Đang so sánh ảnh…")

        // Nạp feature print từ cache cho các ứng viên còn thiếu
        for id in candidates where livePrints[id] == nil {
            if let p = newPrints[id] ?? cachedPrints[id], let obs = ImageAnalysis.unarchive(p.data) {
                livePrints[id] = obs
            }
        }

        var sizes: [String: Int64] = cloudSizes
        var blurScores: [String: Float] = [:]
        for (id, e) in entries {
            sizes[id] = e.size
            if e.blur >= 0 { blurScores[id] = e.blur }
        }

        // 3. Ảnh trùng lặp: LSH 8 dải x 32 bit, ngưỡng Hamming <= 6/256
        var dupGroupsIdx: [[Int]] = []
        var hashes: [[UInt64]] = []
        var hashAssets: [PHAsset] = []
        for a in images {
            if let e = entries[a.localIdentifier], e.hash.count == 32 {
                hashes.append(ImageAnalysis.dataToHash(e.hash))
                hashAssets.append(a)
            }
        }
        var uf = UnionFind(hashAssets.count)
        for band in 0..<8 {
            var buckets: [UInt32: [Int]] = [:]
            for (i, h) in hashes.enumerated() {
                let word = h[band / 2]
                let key = UInt32(truncatingIfNeeded: band % 2 == 0 ? word : word >> 32)
                buckets[key, default: []].append(i)
            }
            for (_, list) in buckets where list.count >= 2 && list.count <= 300 {
                for x in 0..<list.count {
                    for y in (x + 1)..<list.count {
                        let i = list[x], j = list[y]
                        guard ImageAnalysis.hamming(hashes[i], hashes[j]) <= 6 else { continue }
                        let a = hashAssets[i], b = hashAssets[j]
                        let ra = Double(a.pixelWidth) / Double(max(1, a.pixelHeight))
                        let rb = Double(b.pixelWidth) / Double(max(1, b.pixelHeight))
                        if abs(ra - rb) < 0.02 { uf.union(i, j) }
                    }
                }
            }
        }
        dupGroupsIdx = uf.groups()
        var dupIDs = Set<String>()
        var duplicateGroups: [AssetGroup] = []
        for g in dupGroupsIdx {
            let assets = g.map { hashAssets[$0] }
            assets.forEach { dupIDs.insert($0.localIdentifier) }
            duplicateGroups.append(AssetGroup(sortBest(assets, sizes: sizes, blur: blurScores, preferSharp: false)))
        }
        duplicateGroups.sort { groupSize($0, sizes) > groupSize($1, sizes) }

        // 4. Ảnh tương tự: so sánh feature print trong cùng cụm thời gian
        var similarGroups: [AssetGroup] = []
        for c in clusters {
            var cuf = UnionFind(c.count)
            for i in 0..<c.count {
                guard let pi = livePrints[c[i].localIdentifier] else { continue }
                let end = min(c.count, i + 1 + similarNeighbors)
                for j in (i + 1)..<end {
                    guard let pj = livePrints[c[j].localIdentifier],
                          let d = ImageAnalysis.distance(pi, pj) else { continue }
                    if d < params.similarThreshold { cuf.union(i, j) }
                }
            }
            for g in cuf.groups() {
                let assets = g.map { c[$0] }.filter { !dupIDs.contains($0.localIdentifier) }
                if assets.count >= 2 {
                    similarGroups.append(AssetGroup(sortBest(assets, sizes: sizes, blur: blurScores, preferSharp: true)))
                }
            }
        }
        similarGroups.sort { ($0.assets.first?.creationDate ?? .distantPast) > ($1.assets.first?.creationDate ?? .distantPast) }

        // 5. Ảnh burst
        progress(0.96, "Đang kiểm tra ảnh chụp liên tiếp…")
        var burstGroups: [AssetGroup] = []
        var seenBursts = Set<String>()
        for a in images {
            guard let bid = a.burstIdentifier, seenBursts.insert(bid).inserted else { continue }
            let bo = PHFetchOptions()
            bo.includeAllBurstAssets = true
            let r = PHAsset.fetchAssets(withBurstIdentifier: bid, options: bo)
            var arr: [PHAsset] = []
            r.enumerateObjects { x, _, _ in arr.append(x) }
            guard arr.count >= 2 else { continue }
            for x in arr where sizes[x.localIdentifier] == nil {
                sizes[x.localIdentifier] = ImageAnalysis.fileSize(of: x)
            }
            arr.sort { burstRank($0) > burstRank($1) }
            burstGroups.append(AssetGroup(arr))
        }

        // 6. Danh mục đơn giản
        let screenshots = images.filter { $0.mediaSubtypes.contains(.photoScreenshot) }.reversed()
        let livePhotos = images.filter { $0.mediaSubtypes.contains(.photoLive) }.reversed()
        let blurry = normalPhotos.filter { a in
            guard let e = entries[a.localIdentifier], e.blur >= 0 else { return false }
            return e.blur < params.blurThreshold || e.brightness < darkThreshold
        }.sorted { (blurScores[$0.localIdentifier] ?? 0) < (blurScores[$1.localIdentifier] ?? 0) }
        let videosBySize = videos.sorted { (sizes[$0.localIdentifier] ?? 0) > (sizes[$1.localIdentifier] ?? 0) }
        let largeVideos = videosBySize.filter { (sizes[$0.localIdentifier] ?? 0) >= params.largeVideoBytes }

        // 7. Lưu cache (chỉ giữ ảnh còn tồn tại)
        var newCache = CacheFile()
        newCache.entries = entries
        var mergedPrints: [String: PrintEntry] = [:]
        for id in candidates {
            if let p = newPrints[id] { mergedPrints[id] = p }
            else if let p = cachedPrints[id], p.mod == (entries[id]?.mod ?? p.mod) { mergedPrints[id] = p }
        }
        newCache.prints = mergedPrints
        ScanCache.save(newCache)

        var result = ScanResult()
        result.duplicateGroups = duplicateGroups
        result.similarGroups = similarGroups
        result.burstGroups = burstGroups
        result.screenshots = Array(screenshots)
        result.livePhotos = Array(livePhotos)
        result.blurry = blurry
        result.largeVideos = largeVideos
        result.allVideos = videosBySize
        result.sizes = sizes
        result.blurScores = blurScores
        result.totalPhotos = images.count
        result.totalVideos = videos.count
        result.totalBytes = all.reduce(Int64(0)) { $0 + (sizes[$1.localIdentifier] ?? 0) }
        result.skippedCloud = skipped
        result.date = Date()
        progress(1, "Hoàn tất")
        return result
    }

    // MARK: Chọn ảnh tốt nhất (đứng đầu nhóm)

    static func sortBest(_ assets: [PHAsset], sizes: [String: Int64], blur: [String: Float], preferSharp: Bool) -> [PHAsset] {
        assets.sorted { a, b in
            if a.isFavorite != b.isFavorite { return a.isFavorite }
            if preferSharp {
                let ba = blur[a.localIdentifier] ?? 0, bb = blur[b.localIdentifier] ?? 0
                if abs(ba - bb) > 5 { return ba > bb }
            }
            let pa = a.pixelWidth * a.pixelHeight, pb = b.pixelWidth * b.pixelHeight
            if pa != pb { return pa > pb }
            let sa = sizes[a.localIdentifier] ?? 0, sb = sizes[b.localIdentifier] ?? 0
            if sa != sb { return sa > sb }
            return (a.creationDate ?? .distantFuture) < (b.creationDate ?? .distantFuture)
        }
    }

    static func burstRank(_ a: PHAsset) -> Int {
        var r = 0
        if a.burstSelectionTypes.contains(.userPick) { r += 4 }
        if a.isFavorite { r += 3 }
        if a.representsBurst { r += 2 }
        if a.burstSelectionTypes.contains(.autoPick) { r += 1 }
        return r
    }

    static func groupSize(_ g: AssetGroup, _ sizes: [String: Int64]) -> Int64 {
        g.assets.reduce(Int64(0)) { $0 + (sizes[$1.localIdentifier] ?? 0) }
    }
}
