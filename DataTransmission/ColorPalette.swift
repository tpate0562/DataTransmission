//
//  ColorPalette.swift
//  DataTransmission
//
//  8 maximally-distinct colors for 3-bit-per-cell encoding.
//

import UIKit

struct ColorPalette {

    /// RGBA tuples for 8 colors chosen for absolute maximum perceptual distance
    /// (> 65,000 Euclidean distance squared between ANY two colors).
    /// Used to encode 3-bit chunks into 1 symbol.
    static let colors: [(r: UInt8, g: UInt8, b: UInt8)] = [
        // ── Extreme Corners (Max Contrast) ──
        (  0,   0,   0),   //  0  black
        (255, 255, 255),   //  1  white
        (255,   0,   0),   //  2  red
        (  0, 255,   0),   //  3  green
        (  0,   0, 255),   //  4  blue
        (255, 255,   0),   //  5  yellow
        (  0, 255, 255),   //  6  cyan
        (255,   0, 255),   //  7  magenta
    ]

    /// Return the UIColor for a given index (0–7).
    static func color(for index: UInt8) -> UIColor {
        let maxIdx = UInt8(colors.count - 1)
        let safeIdx = index > maxIdx ? maxIdx : index
        let c = colors[Int(safeIdx)]
        return UIColor(
            red:   CGFloat(c.r) / 255.0,
            green: CGFloat(c.g) / 255.0,
            blue:  CGFloat(c.b) / 255.0,
            alpha: 1.0
        )
    }

    /// Find the palette index whose color is closest (Euclidean RGB) to the
    /// given sample.  This is the core of the decoder's color classifier.
    static func closestIndex(r: UInt8, g: UInt8, b: UInt8) -> UInt8 {
        var bestIdx: UInt8 = 0
        var bestDist = Int.max
        for (i, c) in colors.enumerated() {
            let dr = Int(r) - Int(c.r)
            let dg = Int(g) - Int(c.g)
            let db = Int(b) - Int(c.b)
            let d  = dr*dr + dg*dg + db*db
            if d < bestDist {
                bestDist = d
                bestIdx  = UInt8(i)
            }
        }
        return bestIdx
    }

    // MARK: - Alignment-marker colors
    //
    // These colors are chosen to be maximally distinct from:
    //   • all 32 data palette colors
    //   • iOS dark-mode and light-mode UI backgrounds
    // This lets the decoder find finders by scanning for these specific colors.

    /// Finder primary color (outer ring + inner 3×3): deep pink
    static let finderCenter: (r: UInt8, g: UInt8, b: UInt8) = (230, 30, 140)
    /// Finder secondary color (middle ring): teal-green
    static let finderMiddle: (r: UInt8, g: UInt8, b: UInt8) = (30, 200, 140)

    /// Orientation marker uses the same color scheme
    static let orientationCenter: (r: UInt8, g: UInt8, b: UInt8) = (230, 30, 140)
    static let orientationMiddle: (r: UInt8, g: UInt8, b: UInt8) = (30, 200, 140)
}
