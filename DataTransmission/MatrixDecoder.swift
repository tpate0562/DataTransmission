//
//  MatrixDecoder.swift
//  DataTransmission
//
//  Decodes a color matrix image back into UTF-8 text.
//  Two paths:
//    1. decodeDirect  — pixel-perfect rendered images (exact cell alignment)
//    2. decode        — screenshots / camera captures (finder-based perspective sampling)
//

import UIKit
import CoreGraphics

struct MatrixDecoder {

    // Finder target colors (from ColorPalette)
    private static let fcR = ColorPalette.finderCenter.r
    private static let fcG = ColorPalette.finderCenter.g
    private static let fcB = ColorPalette.finderCenter.b
    private static let fmR = ColorPalette.finderMiddle.r
    private static let fmG = ColorPalette.finderMiddle.g
    private static let fmB = ColorPalette.finderMiddle.b

    // MARK: - Public entry point

    /// Try pixel-perfect first, then fall back to finder-based decode.
    static func decodeAny(image: UIImage) -> String? {
        if let direct = decodeDirect(image: image) { return direct }
        return decode(image: image)
    }

    // MARK: - Direct decode (pixel-perfect images)

    static func decodeDirect(image: UIImage) -> String? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        guard w >= 21, h >= 21 else { return nil }
        guard let px = pixBuf(cg, w, h) else { return nil }

        // Find top-left-most finderCenter pixel
        var firstX = -1, firstY = -1
        outer: for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                if sqD(px[i], px[i+1], px[i+2], fcR, fcG, fcB) < 6000 {
                    firstX = x; firstY = y
                    break outer
                }
            }
        }
        guard firstX >= 0 else { return nil }

        // Discover cellSize by scanning diagonally for finderMiddle.
        var cs = 0
        for d in 1..<min(w - firstX, h - firstY) {
            let i = ((firstY + d) * w + (firstX + d)) * 4
            if sqD(px[i], px[i+1], px[i+2], fmR, fmG, fmB) < 6000 {
                cs = d; break
            }
        }
        guard cs >= 1 else { return nil }

        let borderPx = firstX - cs
        guard borderPx >= 0 else { return nil }

        let gs = (w - 2 * borderPx) / cs
        guard gs >= 21 else { return nil }

        // Validate: TL finder center at grid (4,4)
        let ctrX = borderPx + 4 * cs + cs / 2
        let ctrY = borderPx + 4 * cs + cs / 2
        let ci = (ctrY * w + ctrX) * 4
        guard ci + 2 < px.count,
              sqD(px[ci], px[ci+1], px[ci+2], fcR, fcG, fcB) < 6000 else { return nil }

        print("[DecodeDirect] cs=\(cs) gs=\(gs) border=\(borderPx)")
        return sampleGrid(px, w, gs, cs, borderPx)
    }

    // MARK: - Screenshot / Camera decode (adaptive threshold, finder-based)

    /// Robust decode from any image. Uses adaptive thresholds to find finders
    /// without being flooded by false positives from palette colors.
    static func decode(image: UIImage) -> String? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        guard w >= 30, h >= 30 else { return nil }
        guard let px = pixBuf(cg, w, h) else { return nil }

        // Try progressively looser thresholds.
        // Start tight (catches exact/near-exact matches only),
        // widen to handle color-space shifts in screenshots/photos.
        for threshold in [2000, 4000, 6000, 9000, 13000] {
            print("[Decode] ── trying threshold=\(threshold) ──")
            if let result = tryDecode(px, w, h, threshold: threshold) {
                return result
            }
        }
        print("[Decode] FAILED: all thresholds exhausted")
        return nil
    }

    /// Single decode attempt at a given color-distance threshold.
    private static func tryDecode(_ px: [UInt8], _ w: Int, _ h: Int, threshold: Int) -> String? {

        // ── Step 1: Scan for finderCenter-colored pixels ──
        var pts: [(x: Int, y: Int)] = []
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                if sqD(px[i], px[i+1], px[i+2], fcR, fcG, fcB) < threshold {
                    pts.append((x, y))
                }
            }
        }
        print("[Decode]   \(pts.count) candidate pixels")
        guard pts.count >= 10 else { return nil }

        // ── Step 2: Cluster via spatial bucketing + flood fill ──
        // Use fine buckets (1/150 of image dim) so nearby noise doesn't
        // get merged with real finder clusters.
        let bSz = max(3, min(w, h) / 150)
        var buckets: [Int64: [(x: Int, y: Int)]] = [:]
        for p in pts {
            let key = Int64(p.y / bSz) * 100000 + Int64(p.x / bSz)
            buckets[key, default: []].append(p)
        }

        var visited = Set<Int64>()
        var clusters: [[(x: Int, y: Int)]] = []
        for key in buckets.keys {
            if visited.contains(key) { continue }
            var cl: [(x: Int, y: Int)] = []
            var queue = [key]
            while !queue.isEmpty {
                let k = queue.removeFirst()
                if visited.contains(k) { continue }
                visited.insert(k)
                guard let bpts = buckets[k] else { continue }
                cl.append(contentsOf: bpts)
                let by = Int(k / 100000), bx = Int(k % 100000)
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nk = Int64(by + dy) * 100000 + Int64(bx + dx)
                        if buckets[nk] != nil && !visited.contains(nk) {
                            queue.append(nk)
                        }
                    }
                }
            }
            if cl.count >= 3 { clusters.append(cl) }
        }
        clusters.sort { $0.count > $1.count }
        print("[Decode]   \(clusters.count) clusters, top sizes: \(clusters.prefix(8).map(\.count))")
        guard clusters.count >= 3 else { return nil }

        // ── Step 3: Compute bounding-box geometry + validate ring structure ──
        struct FinderInfo {
            var cx: Double
            var cy: Double
            var extent: Double
            var pixelCount: Int
        }

        var validated: [FinderInfo] = []

        for (ci, cl) in clusters.prefix(20).enumerated() {
            let xs = cl.map(\.x)
            let ys = cl.map(\.y)
            let minX = xs.min()!, maxX = xs.max()!
            let minY = ys.min()!, maxY = ys.max()!
            let cx = Double(minX + maxX) / 2.0
            let cy = Double(minY + maxY) / 2.0
            let extW = maxX - minX + 1
            let extH = maxY - minY + 1
            let ext = Double(max(extW, extH))

            // Filter by aspect ratio: real finders are roughly square
            let aspect = Double(max(extW, extH)) / Double(max(1, min(extW, extH)))
            if aspect > 2.0 {
                print("[Decode]   cluster \(ci): skip — bad aspect \(String(format:"%.1f", aspect))")
                continue
            }

            // Filter by fill density: a finder's finderCenter pixels fill ~70% of the bbox
            let bboxArea = extW * extH
            let fillRatio = Double(cl.count) / Double(max(1, bboxArea))
            if fillRatio < 0.15 {
                print("[Decode]   cluster \(ci): skip — low fill \(String(format:"%.2f", fillRatio))")
                continue
            }

            let half = ext / 2.0

            // Check the middle ring (finderMiddle) at the correct radial distance.
            // Middle ring is at 2/3.5 ≈ 0.57 of half-extent from center.
            // Sample at multiple ratios for robustness.
            var middleRingHits = 0
            for ratio in [0.45, 0.50, 0.57, 0.64, 0.70] {
                let r = half * ratio
                let samples: [(Double, Double)] = [
                    (cx, cy - r), (cx, cy + r),
                    (cx - r, cy), (cx + r, cy),
                ]
                for (sx, sy) in samples {
                    let ix = Int(sx), iy = Int(sy)
                    guard ix >= 0, ix < w, iy >= 0, iy < h else { continue }
                    let si = (iy * w + ix) * 4
                    if sqD(px[si], px[si+1], px[si+2], fmR, fmG, fmB) < max(threshold, 8000) {
                        middleRingHits += 1
                    }
                }
            }

            // Verify center pixel is finderCenter
            let cix = Int(cx), ciy = Int(cy)
            var centerDist = Int.max
            if cix >= 0, cix < w, ciy >= 0, ciy < h {
                let idx = (ciy * w + cix) * 4
                centerDist = sqD(px[idx], px[idx+1], px[idx+2], fcR, fcG, fcB)
            }
            let centerOK = centerDist < threshold

            print("[Decode]   cluster \(ci): center=(\(String(format:"%.0f",cx)),\(String(format:"%.0f",cy))) ext=\(String(format:"%.0f",ext)) aspect=\(String(format:"%.1f",aspect)) fill=\(String(format:"%.2f",fillRatio)) middleHits=\(middleRingHits) centerDist=\(centerDist) centerOK=\(centerOK)")

            // Accept if: center is finderCenter AND has concentric ring structure
            if centerOK && middleRingHits >= 3 {
                validated.append(FinderInfo(cx: cx, cy: cy, extent: ext, pixelCount: cl.count))
            }
        }

        print("[Decode]   \(validated.count) validated finders")
        guard validated.count >= 3 else { return nil }

        // ── Step 4: Select 4 markers (3 finders + 1 orient) ──
        // The orient marker (5x5) has a smaller extent than the 3 finders (7x7).
        // Sort by extent descending to easily distinguish them if needed.
        validated.sort { $0.extent > $1.extent }
        let markers = Array(validated.prefix(4))
        print("[Decode]   Selected \(markers.count) top markers: exts=\(markers.map { String(format:"%.0f", $0.extent) })")
        guard markers.count >= 3 else {
            print("[Decode]   FAILED: need at least 3 markers, got \(markers.count)")
            return nil
        }

        // ── Step 5: Assign to TL, TR, BL, BR corners ──
        let meanX = markers.map(\.cx).reduce(0, +) / Double(markers.count)
        let meanY = markers.map(\.cy).reduce(0, +) / Double(markers.count)

        var tl: FinderInfo?, tr: FinderInfo?, bl: FinderInfo?, br: FinderInfo?
        for f in markers {
            switch (f.cx < meanX, f.cy < meanY) {
            case (true, true):   tl = tl ?? f   // top-left
            case (false, true):  tr = tr ?? f   // top-right
            case (true, false):  bl = bl ?? f   // bottom-left
            case (false, false): br = br ?? f   // bottom-right
            }
        }

        guard let tlF = tl, let trF = tr, let blF = bl else {
            print("[Decode]   Corner assignment failed: tl=\(tl != nil) tr=\(tr != nil) bl=\(bl != nil)")
            return nil
        }

        let isTrueBR = (br != nil)
        let brCx = br?.cx ?? (trF.cx + blF.cx - tlF.cx)
        let brCy = br?.cy ?? (trF.cy + blF.cy - tlF.cy)

        print("[Decode]   TL=(\(String(format:"%.0f",tlF.cx)),\(String(format:"%.0f",tlF.cy))) " +
              "TR=(\(String(format:"%.0f",trF.cx)),\(String(format:"%.0f",trF.cy))) " +
              "BL=(\(String(format:"%.0f",blF.cx)),\(String(format:"%.0f",blF.cy))) " +
              "BR=(\(String(format:"%.0f",brCx)),\(String(format:"%.0f",brCy))) [trueBR=\(isTrueBR)]")

        // ── Step 6: Compute cell size and grid size ──
        // Use the 3 main finders for extent/count estimation.
        let mainFinders = [tlF, trF, blF]
        let topDist = hypot(trF.cx - tlF.cx, trF.cy - tlF.cy)
        let leftDist = hypot(blF.cx - tlF.cx, blF.cy - tlF.cy)
        let avgDist = (topDist + leftDist) / 2.0

        // Estimate 1: from extent (biased high when rotated)
        let cellPxFromExtent = mainFinders.reduce(0) { $0 + $1.extent } / 3.0 / 7.0

        // Estimate 2: from cluster pixel count (rotation-invariant)
        // A 7×7 finder has 33 finderCenter cells, so count ≈ 33 × cellPx²
        let avgCount = Double(mainFinders.reduce(0) { $0 + $1.pixelCount }) / 3.0
        let cellPxFromCount = sqrt(avgCount / 33.0)
        
        // Estimate 3: average of the two (often closest to reality)
        let cellPxAvg = (cellPxFromExtent + cellPxFromCount) / 2.0

        // Generate candidate grid sizes from estimates
        let gs1 = Int(round(avgDist / cellPxFromExtent)) + 9
        let gs2 = Int(round(avgDist / cellPxFromCount)) + 9
        let gs3 = Int(round(avgDist / cellPxAvg)) + 9

        // Collect unique candidates: wide net (±8) around estimates
        // since rotation/perspective can skew bounding boxes by 10-15%.
        var candidates = Set<Int>()
        for base in [gs1, gs2, gs3] {
            for delta in -8...8 {
                let gs = base + delta
                if gs >= 21 { candidates.insert(gs) }
            }
        }
        let sortedCandidates = candidates.sorted()

        print("[Decode]   cellPx estimates: ext=\(String(format:"%.2f",cellPxFromExtent)) count=\(String(format:"%.2f",cellPxFromCount)) avg=\(String(format:"%.2f",cellPxAvg))")
        print("[Decode]   grid candidates: \(sortedCandidates)")

        // ── Step 7: True Perspective (Homography) ──
        // Calculate the projective transform mapping (u,v) in [0,1]x[0,1]
        // to the 4 physical corners.
        let dx1 = trF.cx - brCx
        let dx2 = blF.cx - brCx
        let dx3 = tlF.cx - trF.cx + brCx - blF.cx
        let dy1 = trF.cy - brCy
        let dy2 = blF.cy - brCy
        let dy3 = tlF.cy - trF.cy + brCy - blF.cy

        let det = dx1 * dy2 - dx2 * dy1
        let hg = det == 0 ? 0 : (dx3 * dy2 - dx2 * dy3) / det
        let hh = det == 0 ? 0 : (dx1 * dy3 - dx3 * dy1) / det

        let a = trF.cx - tlF.cx + hg * trF.cx
        let b = blF.cx - tlF.cx + hh * blF.cx
        let c = tlF.cx
        let d = trF.cy - tlF.cy + hg * trF.cy
        let e = blF.cy - tlF.cy + hh * blF.cy
        let f = tlF.cy

        let rC = MatrixEncoder.finderSize + 2
        let rO = MatrixEncoder.orientSize + 2

        for gridSize in sortedCandidates {
            let span = Double(gridSize - 9)
            guard span > 0 else { continue }
            var syms: [UInt8] = []

            for row in 0..<gridSize {
                let v = Double(row - 4) / span
                for col in 0..<gridSize {
                    if MatrixEncoder.isReserved(row: row, col: col, gridSize: gridSize,
                                                reservedCorner: rC, reservedOrient: rO) {
                        continue
                    }
                    let u = Double(col - 4) / span

                    // True perspective projection
                    let denom = hg * u + hh * v + 1.0
                    let sampleX = (a * u + b * v + c) / denom
                    let sampleY = (d * u + e * v + f) / denom

                    let cxInt = Int(sampleX.rounded())
                    let cyInt = Int(sampleY.rounded())
                    let ix = max(0, min(cxInt, w - 1))
                    let iy = max(0, min(cyInt, h - 1))
                    let idx = (iy * w + ix) * 4
                    syms.append(ColorPalette.closestIndex(r: px[idx], g: px[idx+1], b: px[idx+2]))
                }
            }

            print("[Decode]   trying gridSize=\(gridSize) (\(syms.count) symbols)")
            if let result = reassemble(syms) {
                return result
            }
        }

        return nil
    }

    // MARK: - Helpers

    private static func sampleGrid(_ px: [UInt8], _ w: Int, _ gs: Int, _ cs: Int, _ bp: Int) -> String? {
        let rC = MatrixEncoder.finderSize + 2, rO = MatrixEncoder.orientSize + 2
        var syms: [UInt8] = []
        for row in 0..<gs {
            for col in 0..<gs {
                if MatrixEncoder.isReserved(row: row, col: col, gridSize: gs,
                                            reservedCorner: rC, reservedOrient: rO) {
                    continue
                }
                let x = bp + col * cs + cs / 2
                let y = bp + row * cs + cs / 2
                let i = (y * w + x) * 4
                guard i + 2 < px.count else { continue }
                syms.append(ColorPalette.closestIndex(r: px[i], g: px[i+1], b: px[i+2]))
            }
        }
        return reassemble(syms)
    }

    private static func reassemble(_ s: [UInt8]) -> String? {
        var bits: [Bool] = []
        for v in s {
            for sh in stride(from: 4, through: 0, by: -1) {
                bits.append((v >> sh) & 1 == 1)
            }
        }
        guard bits.count >= 32 else {
            print("[Reassemble] FAILED: not enough bits (\(bits.count) < 32)")
            return nil
        }
        var bc: UInt32 = 0
        for i in 0..<32 { bc <<= 1; if bits[i] { bc |= 1 } }
        print("[Reassemble] byteCount=\(bc) from \(s.count) symbols (\(bits.count) bits), first8syms=\(Array(s.prefix(8)))")
        guard bc > 0, bc < 10_000_000 else {
            print("[Reassemble] FAILED: bad byte count \(bc)")
            return nil
        }
        let d = Array(bits.dropFirst(32))
        guard d.count >= Int(bc) * 8 else {
            print("[Reassemble] FAILED: not enough data bits (\(d.count) < \(Int(bc)*8))")
            return nil
        }
        var bytes: [UInt8] = []
        for i in 0..<Int(bc) {
            var b: UInt8 = 0
            for bit in 0..<8 { b <<= 1; if d[i * 8 + bit] { b |= 1 } }
            bytes.append(b)
        }
        let result = String(bytes: bytes, encoding: .utf8)
        if result == nil {
            print("[Reassemble] FAILED: invalid UTF-8 (\(bc) bytes, first 20: \(Array(bytes.prefix(20))))")
        } else {
            print("[Reassemble] OK: \(bc) bytes decoded")
        }
        return result
    }

    private static func pixBuf(_ cg: CGImage, _ w: Int, _ h: Int) -> [UInt8]? {
        var d = [UInt8](repeating: 0, count: h * w * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &d, width: w, height: h,
                                   bitsPerComponent: 8, bytesPerRow: w * 4,
                                   space: cs,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return d
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private static func sqD(_ r1: UInt8, _ g1: UInt8, _ b1: UInt8,
                             _ r2: UInt8, _ g2: UInt8, _ b2: UInt8) -> Int {
        let dr = Int(r1) - Int(r2)
        let dg = Int(g1) - Int(g2)
        let db = Int(b1) - Int(b2)
        return dr * dr + dg * dg + db * db
    }
}
