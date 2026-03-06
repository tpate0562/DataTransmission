//
//  ColorPalette.swift
//  DataTransmission
//
//  32 maximally-distinct colors for 5-bit-per-cell encoding.
//

import UIKit

struct ColorPalette {

    /// RGBA tuples for 32 colors chosen for maximum perceptual spread.
    /// Indices 0–31 each map to a unique 5-bit value.
    static let colors: [(r: UInt8, g: UInt8, b: UInt8)] = [
        // ── Row 0: dark / low-saturation anchors ──
        (  0,   0,   0),   //  0  black
        (255, 255, 255),   //  1  white
        (128, 128, 128),   //  2  mid-gray

        // ── Row 1: pure primaries / secondaries ──
        (255,   0,   0),   //  3  red
        (  0, 255,   0),   //  4  green
        (  0,   0, 255),   //  5  blue
        (255, 255,   0),   //  6  yellow
        (  0, 255, 255),   //  7  cyan
        (255,   0, 255),   //  8  magenta

        // ── Row 2: dark primaries ──
        (128,   0,   0),   //  9  dark red / maroon
        (  0, 128,   0),   // 10  dark green
        (  0,   0, 128),   // 11  navy
        (128, 128,   0),   // 12  olive
        (  0, 128, 128),   // 13  teal
        (128,   0, 128),   // 14  purple

        // ── Row 3: warm tones ──
        (255, 128,   0),   // 15  orange
        (255, 128, 128),   // 16  salmon
        (255, 200,   0),   // 17  gold
        (200, 100,  50),   // 18  brown / sienna

        // ── Row 4: cool mid-tones ──
        (  0, 128, 255),   // 19  sky blue
        (128,   0, 255),   // 20  violet
        (  0, 255, 128),   // 21  spring green
        (128, 255,   0),   // 22  chartreuse

        // ── Row 5: pastels & lights ──
        (255, 180, 200),   // 23  pink
        (180, 220, 255),   // 24  light blue
        (200, 255, 200),   // 25  light green
        (255, 255, 180),   // 26  cream

        // ── Row 6: remaining fills ──
        (100,  50,   0),   // 27  dark brown
        ( 50, 50,  50),    // 28  charcoal
        (200, 200, 200),   // 29  silver
        (255, 100, 255),   // 30  hot pink
        (100, 200, 100),   // 31  medium green
    ]

    /// Return the UIColor for a given 5-bit index (0–31).
    static func color(for index: UInt8) -> UIColor {
        let c = colors[Int(index & 0x1F)]
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
