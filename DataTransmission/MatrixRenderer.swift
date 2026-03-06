//
//  MatrixRenderer.swift
//  DataTransmission
//
//  Renders a ColorMatrix into a UIImage with a white border.
//

import UIKit

struct MatrixRenderer {

    /// Pixels per logical cell.
    static let defaultCellSize = 4

    /// Number of cells of white padding on each side of the grid.
    /// This provides a clean frame so finder patterns are always detectable
    /// even when the image is embedded in a screenshot or other context.
    static let borderCells = 3

    /// Render the matrix to a `UIImage`.
    static func render(matrix: ColorMatrix, cellSize: Int = defaultCellSize) -> UIImage? {
        let border = borderCells * cellSize
        let gridW = matrix.width  * cellSize
        let gridH = matrix.height * cellSize
        let totalW = gridW + 2 * border
        let totalH = gridH + 2 * border

        UIGraphicsBeginImageContextWithOptions(CGSize(width: totalW, height: totalH), true, 1.0)
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }

        // White background (fills border area)
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: totalW, height: totalH))

        for row in 0..<matrix.height {
            for col in 0..<matrix.width {
                let value = matrix.cells[row][col]
                let color: UIColor
                switch value {
                case 200:
                    color = UIColor(
                        red:   CGFloat(ColorPalette.finderCenter.r) / 255,
                        green: CGFloat(ColorPalette.finderCenter.g) / 255,
                        blue:  CGFloat(ColorPalette.finderCenter.b) / 255,
                        alpha: 1
                    )
                case 201:
                    color = UIColor(
                        red:   CGFloat(ColorPalette.finderMiddle.r) / 255,
                        green: CGFloat(ColorPalette.finderMiddle.g) / 255,
                        blue:  CGFloat(ColorPalette.finderMiddle.b) / 255,
                        alpha: 1
                    )
                default:
                    color = ColorPalette.color(for: value)
                }

                ctx.setFillColor(color.cgColor)
                ctx.fill(CGRect(x: border + col * cellSize,
                                y: border + row * cellSize,
                                width: cellSize, height: cellSize))
            }
        }

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
}
