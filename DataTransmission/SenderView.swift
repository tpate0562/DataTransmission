//
//  SenderView.swift
//  DataTransmission
//
//  Text input → encode → display colored matrix image.
//

import SwiftUI

struct SenderView: View {
    @State private var inputText = ""
    @State private var encodedImage: UIImage?
    @State private var statusMessage = ""
    @State private var isEncoding = false
    @State private var matrixInfo = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // ── Text input ──
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Message to encode")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $inputText)
                            .frame(minHeight: 120, maxHeight: 200)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )

                        Text("\(inputText.utf8.count) bytes")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    // ── Encode button ──
                    Button {
                        encodeText()
                    } label: {
                        HStack {
                            if isEncoding {
                                ProgressView()
                                    .tint(.white)
                            }
                            Image(systemName: "square.grid.3x3.fill")
                            Text("Encode")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(inputText.isEmpty ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(inputText.isEmpty || isEncoding)

                    // ── Status ──
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                    if !matrixInfo.isEmpty {
                        Text(matrixInfo)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // ── Encoded image ──
                    if let img = encodedImage {
                        VStack(spacing: 12) {
                            Image(uiImage: img)
                                .resizable()
                                .interpolation(.none) // crisp pixels
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 400)
                                .border(Color.gray.opacity(0.3), width: 1)

                            // Share / save
                            ShareLink(item: Image(uiImage: img),
                                      preview: SharePreview("DataMatrix", image: Image(uiImage: img))) {
                                Label("Share Image", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(.systemGray5))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }

                            // Quick self-test: decode the image right back
                            Button {
                                selfTest(img)
                            } label: {
                                Label("Self-Test Decode", systemImage: "checkmark.circle")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(.systemGray5))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Send")
        }
    }

    // MARK: - Actions

    private func encodeText() {
        guard !inputText.isEmpty else { return }
        isEncoding = true
        statusMessage = ""
        matrixInfo = ""

        DispatchQueue.global(qos: .userInitiated).async {
            let matrix = MatrixEncoder.encode(text: inputText)
            let image = MatrixRenderer.render(matrix: matrix)
            DispatchQueue.main.async {
                encodedImage = image
                isEncoding = false
                statusMessage = "Encoded \(inputText.utf8.count) bytes"
                matrixInfo = "Grid: \(matrix.width)×\(matrix.height) cells  •  Image: \(image?.cgImage?.width ?? 0)×\(image?.cgImage?.height ?? 0) px"
            }
        }
    }

    private func selfTest(_ image: UIImage) {
        DispatchQueue.global(qos: .userInitiated).async {
            let decoded = MatrixDecoder.decodeAny(image: image)
            DispatchQueue.main.async {
                if let decoded = decoded {
                    if decoded == inputText {
                        statusMessage = "✅ Self-test PASSED — decoded \(decoded.count) chars"
                    } else {
                        statusMessage = "⚠️ Mismatch! Decoded \(decoded.count) chars"
                    }
                } else {
                    statusMessage = "❌ Self-test FAILED — could not decode"
                }
            }
        }
    }
}

#Preview {
    SenderView()
}
