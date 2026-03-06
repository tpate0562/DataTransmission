//
//  DataTransmissionTests.swift
//  DataTransmissionTests
//
//  Created by Tejas Patel on 3/5/26.
//

import Testing
import UIKit
@testable import DataTransmission

@MainActor
struct DataTransmissionTests {

    @Test func roundTripDirect() async throws {
        let text = "Hello, World!"
        let matrix = MatrixEncoder.encode(text: text)
        let image = MatrixRenderer.render(matrix: matrix)
        #expect(image != nil, "Render should produce an image")
        let decoded = MatrixDecoder.decodeAny(image: image!)
        #expect(decoded == text, "Decoded text should match original. Got: \(decoded ?? "nil")")
    }

    @Test func roundTripEmoji() async throws {
        let text = "🌍🎉 Data Transmission Test! 🚀"
        let matrix = MatrixEncoder.encode(text: text)
        let image = MatrixRenderer.render(matrix: matrix)
        #expect(image != nil)
        let decoded = MatrixDecoder.decodeAny(image: image!)
        #expect(decoded == text, "Emoji text mismatch. Got: \(decoded ?? "nil")")
    }

    @Test func roundTripLongerText() async throws {
        let text = "The quick brown fox jumps over the lazy dog. 0123456789 !@#$%^&*()"
        let matrix = MatrixEncoder.encode(text: text)
        let image = MatrixRenderer.render(matrix: matrix)
        #expect(image != nil)
        let decoded = MatrixDecoder.decodeAny(image: image!)
        #expect(decoded == text, "Longer text mismatch. Got: \(decoded ?? "nil")")
    }

    /// Simulates a screenshot by embedding the rendered image in a larger canvas
    /// with a gray background. Uses CGContext directly to avoid UIGraphics threading issues.
    @Test(.serialized) func screenshotRoundTrip() async throws {
        let text = "Screenshot test 123"
        let matrix = MatrixEncoder.encode(text: text)
        guard let original = MatrixRenderer.render(matrix: matrix),
              let originalCG = original.cgImage else {
            Issue.record("Render failed"); return
        }

        // Embed in a larger "screenshot" canvas with padding
        let padding = 80
        let totalW = originalCG.width + 2 * padding
        let totalH = originalCG.height + 2 * padding

        // Use CGContext directly for thread safety
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: totalW, height: totalH,
                                   bitsPerComponent: 8, bytesPerRow: totalW * 4,
                                   space: colorSpace,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            Issue.record("CGContext creation failed"); return
        }

        // Gray background
        ctx.setFillColor(red: 0.56, green: 0.56, blue: 0.58, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: totalW, height: totalH))

        // Draw the matrix image in the center
        ctx.draw(originalCG, in: CGRect(x: padding, y: padding,
                                         width: originalCG.width,
                                         height: originalCG.height))

        guard let screenshotCG = ctx.makeImage() else {
            Issue.record("makeImage failed"); return
        }
        let screenshot = UIImage(cgImage: screenshotCG)

        let decoded = MatrixDecoder.decodeAny(image: screenshot)
        #expect(decoded == text, "Screenshot decode failed. Got: \(decoded ?? "nil")")
    }
}
