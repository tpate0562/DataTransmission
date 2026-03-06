//
//  MatrixDecoder.swift
//  DataTransmission
//
//  Decodes a 3-bit color matrix image back into UTF-8 text.
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
        }

        var validated: [FinderInfo] = []

        for (ci, cl) in clusters.prefix(20).enumerated() {
            let xs = cl.map { Double($0.x) }
            let ys = cl.map { Double($0.y) }
            let minX = xs.min()!, maxX = xs.max()!
            let minY = ys.min()!, maxY = ys.max()!
            
            // Center of mass for sub-pixel precision (robust to rotation)
            let cx = xs.reduce(0, +) / Double(cl.count)
            let cy = ys.reduce(0, +) / Double(cl.count)
            let extW = maxX - minX + 1.0
            let extH = maxY - minY + 1.0
            let ext = max(extW, extH)

            // Filter by aspect ratio: real finders are roughly square
            // (Increased tolerance to 5.0 to handle severe perspective skew and rotation)
            let aspect = Double(max(extW, extH)) / Double(max(1, min(extW, extH)))
            if aspect > 5.0 {
                print("[Decode]   cluster \(ci): skip — bad aspect \(String(format:"%.1f", aspect))")
                continue
            }

            // Filter by fill density: a finder's finderCenter pixels fill ~70% of the bbox
            let bboxArea = extW * extH
            let fillRatio = Double(cl.count) / Double(max(1, bboxArea))
            if fillRatio < 0.05 {
                print("[Decode]   cluster \(ci): skip — low fill \(String(format:"%.2f", fillRatio))")
                continue
            }

            // Check the middle ring (finderMiddle) using radial sweeps
            // This is completely robust to rotation and distortion
            var bestMiddleRingHits = 0
            for rRatio in stride(from: 0.15, through: 0.8, by: 0.05) {
                let r = ext * rRatio
                var hits = 0
                for i in 0..<16 { // 16 samples around the circle
                    let angle = Double(i) * .pi / 8.0
                    let sx = cx + cos(angle) * r
                    let sy = cy + sin(angle) * r
                    let ix = Int(sx), iy = Int(sy)
                    if ix >= 0, ix < w, iy >= 0, iy < h {
                        let si = (iy * w + ix) * 4
                        if sqD(px[si], px[si+1], px[si+2], fmR, fmG, fmB) < max(threshold, 8000) {
                            hits += 1
                        }
                    }
                }
                if hits > bestMiddleRingHits { bestMiddleRingHits = hits }
            }

            // Verify center pixel is finderCenter
            let cix = Int(cx), ciy = Int(cy)
            var centerDist = Int.max
            if cix >= 0, cix < w, ciy >= 0, ciy < h {
                let idx = (ciy * w + cix) * 4
                centerDist = sqD(px[idx], px[idx+1], px[idx+2], fcR, fcG, fcB)
            }
            let centerOK = centerDist < threshold

            print("[Decode]   cluster \(ci): center=(\(String(format:"%.0f",cx)),\(String(format:"%.0f",cy))) ext=\(String(format:"%.0f",ext)) aspect=\(String(format:"%.1f",aspect)) fill=\(String(format:"%.2f",fillRatio)) ringHits=\(bestMiddleRingHits)/16 centerDist=\(centerDist) centerOK=\(centerOK)")

            // Accept if: center is finderCenter AND has concentric ring structure
            if centerOK && bestMiddleRingHits >= 3 {
                validated.append(FinderInfo(cx: cx, cy: cy, extent: ext))
            }
        }

        print("[Decode]   \(validated.count) validated finders")
        guard validated.count >= 3 else { return nil }

        // ── Step 4: Find the 3 main finders and 1 orient marker ──
        validated.sort { $0.extent > $1.extent }

        var mainFinders: [FinderInfo] = []
        for v in validated {
            if mainFinders.isEmpty { mainFinders.append(v); continue }
            if v.extent / mainFinders[0].extent > 0.65 {
                mainFinders.append(v)
            }
        }
        guard mainFinders.count >= 3 else {
            print("[Decode]   FAILED: need >= 3 main finders, got \(mainFinders.count)")
            return nil
        }
        let top3 = Array(mainFinders.prefix(3))

        // Look for the orient marker (smaller extent, roughly 5/7 ≈ 0.71 of main finders)
        var orientMarker: FinderInfo?
        for v in validated {
            if !top3.contains(where: { $0.cx == v.cx && $0.cy == v.cy }) {
                let ratio = v.extent / top3[0].extent
                if ratio > 0.4 && ratio < 0.9 {
                    orientMarker = v
                    break
                }
            }
        }

        // ── Step 5: Rotation-Invariant Corner Assignment ──
        // Distances between the 3 main finders
        let d01 = hypot(top3[0].cx - top3[1].cx, top3[0].cy - top3[1].cy)
        let d12 = hypot(top3[1].cx - top3[2].cx, top3[1].cy - top3[2].cy)
        let d02 = hypot(top3[0].cx - top3[2].cx, top3[0].cy - top3[2].cy)

        // The longest distance is the hypotenuse, meaning the opposite vertex is the right angle (TL)
        var tlIdx = 0, p1Idx = 1, p2Idx = 2
        let maxD = max(d01, max(d12, d02))
        if maxD == d12 { tlIdx = 0; p1Idx = 1; p2Idx = 2 }
        else if maxD == d02 { tlIdx = 1; p1Idx = 0; p2Idx = 2 }
        else { tlIdx = 2; p1Idx = 0; p2Idx = 1 }

        let tlF = top3[tlIdx]
        let p1 = top3[p1Idx]
        let p2 = top3[p2Idx]

        // Use 2D cross product to distinguish TR from BL.
        // cross( TL->p1, TL->p2 ) = dx1*dy2 - dy1*dx2
        // If positive (in image coords where y goes down), p1 is TR and p2 is BL.
        let cross = (p1.cx - tlF.cx) * (p2.cy - tlF.cy) - (p1.cy - tlF.cy) * (p2.cx - tlF.cx)
        let trF = cross > 0 ? p1 : p2
        let blF = cross > 0 ? p2 : p1
        
        // If orient marker is not found, infer BR from parallelogram
        let brF = orientMarker ?? FinderInfo(
            cx: trF.cx + blF.cx - tlF.cx,
            cy: trF.cy + blF.cy - tlF.cy,
            extent: tlF.extent * (5.0/7.0)
        )

        print("[Decode]   TL=(\(String(format:"%.0f",tlF.cx)),\(String(format:"%.0f",tlF.cy))) " +
              "TR=(\(String(format:"%.0f",trF.cx)),\(String(format:"%.0f",trF.cy))) " +
              "BL=(\(String(format:"%.0f",blF.cx)),\(String(format:"%.0f",blF.cy))) " +
              "BR=(\(String(format:"%.0f",brF.cx)),\(String(format:"%.0f",brF.cy))) [inferred=\(orientMarker == nil)]")

        // ── Step 6: Compute cell size and grid size ──
        let topDist = hypot(trF.cx - tlF.cx, trF.cy - tlF.cy)
        let leftDist = hypot(blF.cx - tlF.cx, blF.cy - tlF.cy)
        let avgDist = (topDist + leftDist) / 2.0

        let cellPxFromExtent = (tlF.extent + trF.extent + blF.extent) / 3.0 / 7.0
        let baseGridSize = Int(round(avgDist / cellPxFromExtent)) + 9

        print("[Decode]   baseGridSize=\(baseGridSize)")

        // ── Step 7: True Perspective Homography & Grid Search ──
        let rC = MatrixEncoder.finderSize + 2
        let rO = MatrixEncoder.orientSize + 2

        // Search for the exact grid size by partially decoding the byte count
        let searchStart = max(21, Int(Double(baseGridSize) * 0.3))
        let searchEnd = Int(Double(baseGridSize) * 2.5) + 20

        var bestMatch: (gs: Int, transform: PerspectiveTransform, bc: UInt32)?

        for gs in searchStart...searchEnd {
            let trDst = Double(gs - 5)
            let brDst = orientMarker != nil ? Double(gs - 4) : Double(gs - 5)
            let blDst = Double(gs - 5)

            guard let transform = PerspectiveTransform.quadToQuad(
                x0: 4.0,  y0: 4.0,
                x1: trDst, y1: 4.0,
                x2: brDst, y2: brDst,
                x3: 4.0,  y3: blDst,
                x0p: tlF.cx, y0p: tlF.cy,
                x1p: trF.cx, y1p: trF.cy,
                x2p: brF.cx, y2p: brF.cy,
                x3p: blF.cx, y3p: blF.cy) else { continue }

            // 32 bits requires ceil(32 / 3) = 11 symbols
            var peekSyms: [UInt8] = []
            peekSyms.reserveCapacity(11)

            outerFast: for row in 0..<gs {
                for col in 0..<gs {
                    if MatrixEncoder.isReserved(row: row, col: col, gridSize: gs,
                                                reservedCorner: rC, reservedOrient: rO) { continue }
                    let (sx, sy) = transform.transform(Double(col), Double(row))
                    let ix = min(max(Int(round(sx)), 0), w - 1)
                    let iy = min(max(Int(round(sy)), 0), h - 1)
                    let idx = (iy * w + ix) * 4
                    peekSyms.append(ColorPalette.closestIndex(r: px[idx], g: px[idx+1], b: px[idx+2]))
                    if peekSyms.count == 11 { break outerFast }
                }
            }
            if peekSyms.count < 11 { continue }

            var bits: [Bool] = []
            for v in peekSyms {
                for sh in stride(from: 2, through: 0, by: -1) {
                    bits.append((v >> sh) & 1 == 1)
                }
            }
            var bc: UInt32 = 0
            for i in 0..<32 { bc <<= 1; if bits[i] { bc |= 1 } }

            let reqSymbols = (Int(bc) * 8 + 32 + 2) / 3
            if bc > 0 && bc < 10_000_000 && reqSymbols > 0 {
                var expectedSize = 21
                while expectedSize * expectedSize - 292 < reqSymbols {
                    expectedSize += 1
                }
                if expectedSize == gs {
                    bestMatch = (gs, transform, bc)
                    break // exact match found!
                }
            }
        }
        
        if bestMatch == nil && baseGridSize >= 21 {
            // Fallback: If no exact byteCount match was found, try decodiing baseGridSize anyway
            // This prevents regression if the byteCount logic has subtle edge cases.
            let gs = baseGridSize
            let trDst = Double(gs - 5)
            let brDst = orientMarker != nil ? Double(gs - 4) : Double(gs - 5)
            let blDst = Double(gs - 5)
            if let transform = PerspectiveTransform.quadToQuad(
                x0: 4.0,  y0: 4.0,
                x1: trDst, y1: 4.0,
                x2: brDst, y2: brDst,
                x3: 4.0,  y3: blDst,
                x0p: tlF.cx, y0p: tlF.cy,
                x1p: trF.cx, y1p: trF.cy,
                x2p: brF.cx, y2p: brF.cy,
                x3p: blF.cx, y3p: blF.cy) {
                bestMatch = (gs, transform, 0)
                print("[Decode]   FAILED to find exact grid size, falling back to baseGridSize=\(gs)")
            }
        }

        guard let match = bestMatch else {
            print("[Decode]   FAILED: No valid grid size found in range \(searchStart)...\(searchEnd)")
            return nil
        }

        print("[Decode]   FOUND grid=\(match.gs) matching byteCount=\(match.bc)")

        var syms: [UInt8] = []
        for row in 0..<match.gs {
            for col in 0..<match.gs {
                if MatrixEncoder.isReserved(row: row, col: col, gridSize: match.gs,
                                            reservedCorner: rC, reservedOrient: rO) { continue }
                let (sx, sy) = match.transform.transform(Double(col), Double(row))
                let ix = min(max(Int(round(sx)), 0), w - 1)
                let iy = min(max(Int(round(sy)), 0), h - 1)
                let idx = (iy * w + ix) * 4
                syms.append(ColorPalette.closestIndex(r: px[idx], g: px[idx+1], b: px[idx+2]))
            }
        }

        return reassemble(syms)
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
            for sh in stride(from: 2, through: 0, by: -1) {
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
        let result = String(decoding: bytes, as: UTF8.self)
        if result.contains("\u{FFFD}") {
            print("[Reassemble] OK: \(bc) bytes decoded (with some invalid UTF-8 sequences)")
        } else {
            print("[Reassemble] OK: \(bc) bytes decoded perfectly")
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

    // MARK: - Homography Engine

    struct PerspectiveTransform {
        let a11, a12, a13, a21, a22, a23, a31, a32, a33: Double
        
        func transform(_ x: Double, _ y: Double) -> (Double, Double) {
            var denominator = a31 * x + a32 * y + a33
            if denominator == 0 { denominator = 1.0 }
            return ((a11 * x + a12 * y + a13) / denominator,
                    (a21 * x + a22 * y + a23) / denominator)
        }
        
        static func quadToQuad(x0: Double, y0: Double,
                               x1: Double, y1: Double,
                               x2: Double, y2: Double,
                               x3: Double, y3: Double,
                               x0p: Double, y0p: Double,
                               x1p: Double, y1p: Double,
                               x2p: Double, y2p: Double,
                               x3p: Double, y3p: Double) -> PerspectiveTransform? {
            guard let sq = squareToQuad(x0: x0p, y0: y0p, x1: x1p, y1: y1p, x2: x2p, y2: y2p, x3: x3p, y3: y3p),
                  let qs = squareToQuad(x0: x0, y0: y0, x1: x1, y1: y1, x2: x2, y2: y2, x3: x3, y3: y3)?.adjoint() else {
                return nil
            }
            return sq.multiply(qs)
        }
        
        private static func squareToQuad(x0: Double, y0: Double,
                                         x1: Double, y1: Double,
                                         x2: Double, y2: Double,
                                         x3: Double, y3: Double) -> PerspectiveTransform? {
            let dx3 = x0 - x1 + x2 - x3
            let dy3 = y0 - y1 + y2 - y3
            
            if dx3 == 0.0 && dy3 == 0.0 {
                return PerspectiveTransform(a11: x1 - x0, a12: x3 - x0, a13: x0,
                                            a21: y1 - y0, a22: y3 - y0, a23: y0,
                                            a31: 0.0, a32: 0.0, a33: 1.0)
            } else {
                let dx1 = x1 - x2
                let dx2 = x3 - x2
                let dy1 = y1 - y2
                let dy2 = y3 - y2
                
                let denominator = dx1 * dy2 - dx2 * dy1
                if denominator == 0.0 { return nil }
                
                let a31 = (dx3 * dy2 - dx2 * dy3) / denominator
                let a32 = (dx1 * dy3 - dx3 * dy1) / denominator
                return PerspectiveTransform(
                    a11: x1 - x0 + a31 * x1,
                    a12: x3 - x0 + a32 * x3,
                    a13: x0,
                    a21: y1 - y0 + a31 * y1,
                    a22: y3 - y0 + a32 * y3,
                    a23: y0,
                    a31: a31,
                    a32: a32,
                    a33: 1.0)
            }
        }
        
        private func adjoint() -> PerspectiveTransform {
            return PerspectiveTransform(
                a11: a22 * a33 - a23 * a32, a12: a13 * a32 - a12 * a33, a13: a12 * a23 - a13 * a22,
                a21: a23 * a31 - a21 * a33, a22: a11 * a33 - a13 * a31, a23: a13 * a21 - a11 * a23,
                a31: a21 * a32 - a22 * a31, a32: a12 * a31 - a11 * a32, a33: a11 * a22 - a12 * a21)
        }
        
        private func multiply(_ other: PerspectiveTransform) -> PerspectiveTransform {
            return PerspectiveTransform(
                a11: a11 * other.a11 + a12 * other.a21 + a13 * other.a31,
                a12: a11 * other.a12 + a12 * other.a22 + a13 * other.a32,
                a13: a11 * other.a13 + a12 * other.a23 + a13 * other.a33,
                a21: a21 * other.a11 + a22 * other.a21 + a23 * other.a31,
                a22: a21 * other.a12 + a22 * other.a22 + a23 * other.a32,
                a23: a21 * other.a13 + a22 * other.a23 + a23 * other.a33,
                a31: a31 * other.a11 + a32 * other.a21 + a33 * other.a31,
                a32: a31 * other.a12 + a32 * other.a22 + a33 * other.a32,
                a33: a31 * other.a13 + a32 * other.a23 + a33 * other.a33)
        }
    }
}
