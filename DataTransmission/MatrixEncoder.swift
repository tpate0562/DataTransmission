//
//  MatrixEncoder.swift
//  DataTransmission
//
//  Encodes arbitrary UTF-8 text into a 2D grid of 5-bit color indices
//  with alignment markers and a length header.
//

import Foundation

// MARK: - Data model

/// A 2D grid of color-palette indices (0–31) plus metadata.
struct ColorMatrix {
    let width: Int
    let height: Int
    /// Row-major: cells[row][col], each value 0–31.
    var cells: [[UInt8]]
    /// The number of payload bytes (so the decoder knows when to stop).
    let dataByteCount: Int
}

// MARK: - Encoder

struct MatrixEncoder {

    // Finder-pattern size (must be odd).  3 corners get 7×7, bottom-right gets 5×5.
    static let finderSize = 7
    static let orientSize = 5

    /// Encode a UTF-8 string into a `ColorMatrix`.
    static func encode(text: String) -> ColorMatrix {
        let data = Array(text.utf8)
        let byteCount = data.count

        // ---------- convert bytes → 5-bit symbols ----------
        var bits: [Bool] = []
        for byte in data {
            for shift in stride(from: 7, through: 0, by: -1) {
                bits.append((byte >> shift) & 1 == 1)
            }
        }
        // header: 32-bit big-endian byte count
        var headerBits: [Bool] = []
        let bc = UInt32(byteCount)
        for shift in stride(from: 31, through: 0, by: -1) {
            headerBits.append((bc >> shift) & 1 == 1)
        }

        let allBits = headerBits + bits

        // pack into 5-bit symbols, zero-pad the last symbol if needed
        var symbols: [UInt8] = []
        var idx = 0
        while idx < allBits.count {
            var val: UInt8 = 0
            for bit in 0..<5 {
                val <<= 1
                if idx + bit < allBits.count && allBits[idx + bit] {
                    val |= 1
                }
            }
            symbols.append(val)
            idx += 5
        }

        // ---------- compute grid dimensions ----------
        // We need room for:
        //   • 3 finder patterns (7×7) in TL, TR, BL corners
        //   • 1 orientation marker (5×5) in BR corner
        //   • 1 cell of quiet-zone padding around each marker  (so effectively 9×9 reserved in TL/TR/BL, 7×7 in BR)
        //   • The remaining cells hold data symbols
        //
        // Strategy: pick the smallest square grid where available cells ≥ symbols.count.

        let reservedCorner = finderSize + 2  // 9  (7 + 1-cell border each side)
        let reservedOrient = orientSize + 2  // 7
        let minDim = max(reservedCorner + reservedOrient, 21)  // at least 21×21

        var gridSize = minDim
        while true {
            let avail = availableCellCount(gridSize: gridSize,
                                           reservedCorner: reservedCorner,
                                           reservedOrient: reservedOrient)
            if avail >= symbols.count { break }
            gridSize += 1
        }

        // ---------- fill the grid ----------
        var cells = Array(repeating: Array(repeating: UInt8(0), count: gridSize), count: gridSize)

        // Place data symbols in row-major order, skipping reserved zones.
        var symIdx = 0
        for row in 0..<gridSize {
            for col in 0..<gridSize {
                if isReserved(row: row, col: col, gridSize: gridSize,
                              reservedCorner: reservedCorner, reservedOrient: reservedOrient) {
                    continue
                }
                if symIdx < symbols.count {
                    cells[row][col] = symbols[symIdx]
                    symIdx += 1
                }
                // else stays 0
            }
        }

        // ---------- stamp alignment markers ----------
        stampFinder(into: &cells, originRow: 1, originCol: 1)                            // TL
        stampFinder(into: &cells, originRow: 1, originCol: gridSize - finderSize - 1)     // TR
        stampFinder(into: &cells, originRow: gridSize - finderSize - 1, originCol: 1)     // BL
        stampOrientation(into: &cells,
                         originRow: gridSize - orientSize - 1,
                         originCol: gridSize - orientSize - 1)  // BR

        // ---------- white quiet zone around finders ----------
        // Reserved cells that weren't stamped (still 0) become white (201)
        // so the finder rings have clear contrast for detection.
        for row in 0..<gridSize {
            for col in 0..<gridSize {
                if isReserved(row: row, col: col, gridSize: gridSize,
                              reservedCorner: reservedCorner, reservedOrient: reservedOrient) {
                    if cells[row][col] == 0 {
                        cells[row][col] = 201  // white sentinel
                    }
                }
            }
        }

        return ColorMatrix(width: gridSize, height: gridSize, cells: cells, dataByteCount: byteCount)
    }

    // MARK: - Helpers

    /// How many non-reserved cells exist in a grid of the given size.
    private static func availableCellCount(gridSize: Int, reservedCorner: Int, reservedOrient: Int) -> Int {
        var count = 0
        for row in 0..<gridSize {
            for col in 0..<gridSize {
                if !isReserved(row: row, col: col, gridSize: gridSize,
                               reservedCorner: reservedCorner,
                               reservedOrient: reservedOrient) {
                    count += 1
                }
            }
        }
        return count
    }

    /// Returns `true` if this cell is inside one of the four reserved marker zones.
    static func isReserved(row: Int, col: Int, gridSize: Int,
                            reservedCorner: Int, reservedOrient: Int) -> Bool {
        // TL
        if row < reservedCorner && col < reservedCorner { return true }
        // TR
        if row < reservedCorner && col >= gridSize - reservedCorner { return true }
        // BL
        if row >= gridSize - reservedCorner && col < reservedCorner { return true }
        // BR (orientation)
        if row >= gridSize - reservedOrient && col >= gridSize - reservedOrient { return true }
        return false
    }

    /// Stamp a 7×7 finder pattern (concentric black/white rings) at `(originRow, originCol)`.
    private static func stampFinder(into cells: inout [[UInt8]], originRow: Int, originCol: Int) {
        // We draw the pattern using special sentinel values:
        //   200 = finderCenter (black)
        //   201 = finderMiddle (white)
        // The renderer knows to map these to the fixed finder colors.
        let pattern: [[UInt8]] = [
            [200,200,200,200,200,200,200],
            [200,201,201,201,201,201,200],
            [200,201,200,200,200,201,200],
            [200,201,200,200,200,201,200],
            [200,201,200,200,200,201,200],
            [200,201,201,201,201,201,200],
            [200,200,200,200,200,200,200],
        ]
        for dr in 0..<finderSize {
            for dc in 0..<finderSize {
                cells[originRow + dr][originCol + dc] = pattern[dr][dc]
            }
        }
    }

    /// Stamp a 5×5 orientation marker at `(originRow, originCol)`.
    private static func stampOrientation(into cells: inout [[UInt8]], originRow: Int, originCol: Int) {
        let pattern: [[UInt8]] = [
            [200,200,200,200,200],
            [200,201,201,201,200],
            [200,201,200,201,200],
            [200,201,201,201,200],
            [200,200,200,200,200],
        ]
        for dr in 0..<orientSize {
            for dc in 0..<orientSize {
                cells[originRow + dr][originCol + dc] = pattern[dr][dc]
            }
        }
    }
}
