//
//  ReceiverView.swift
//  DataTransmission
//
//  Camera-based receiver: capture a photo of a color matrix and decode it.
//  Also supports picking an image from the photo library.
//

import SwiftUI
import PhotosUI

struct ReceiverView: View {
    @StateObject private var camera = CameraManager()
    @State private var decodedText: String?
    @State private var statusMessage = ""
    @State private var isDecoding = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var capturedImage: UIImage?

    var body: some View {
        NavigationStack {
            ZStack {
                // ── Camera preview ──
                if camera.isAuthorized {
                    CameraPreview(session: camera.session)
                        .ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 16) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.gray)
                        Text(camera.error ?? "Requesting camera access…")
                            .foregroundStyle(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                // ── Controls overlay ──
                VStack {
                    Spacer()

                    // Result card
                    if let text = decodedText {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Decoded Message")
                                    .font(.headline)
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = text
                                    statusMessage = "Copied!"
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                            }
                            ScrollView {
                                Text(text)
                                    .font(.body)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 200)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                    }

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.footnote)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }

                    // Captured thumbnail
                    if let img = capturedImage {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white, lineWidth: 2)
                            )
                            .padding(.top, 4)
                    }

                    // Buttons
                    HStack(spacing: 24) {
                        // Photo library picker
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            VStack {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.title2)
                                Text("Library")
                                    .font(.caption)
                            }
                            .foregroundStyle(.white)
                        }
                        .onChange(of: selectedPhotoItem) { _, newItem in
                            loadFromLibrary(newItem)
                        }

                        // Capture button
                        Button {
                            captureAndDecode()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 72, height: 72)
                                Circle()
                                    .fill(isDecoding ? .gray : .blue)
                                    .frame(width: 64, height: 64)
                                if isDecoding {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "viewfinder")
                                        .font(.title)
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .disabled(!camera.isAuthorized || isDecoding)

                        // Placeholder for symmetry
                        VStack {
                            Image(systemName: "info.circle")
                                .font(.title2)
                            Text("Info")
                                .font(.caption)
                        }
                        .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Receive")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .onAppear {
                camera.requestAccess()
            }
            .onDisappear {
                camera.stop()
            }
        }
    }

    // MARK: - Actions

    private func captureAndDecode() {
        isDecoding = true
        statusMessage = "Capturing…"
        decodedText = nil

        Task {
            guard let image = await camera.capturePhoto() else {
                await MainActor.run {
                    statusMessage = "❌ Failed to capture photo"
                    isDecoding = false
                }
                return
            }
            await MainActor.run {
                capturedImage = image
                statusMessage = "Decoding…"
            }
            decodeImage(image)
        }
    }

    private func loadFromLibrary(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        isDecoding = true
        statusMessage = "Loading image…"
        decodedText = nil

        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                await MainActor.run {
                    statusMessage = "❌ Failed to load image"
                    isDecoding = false
                }
                return
            }
            await MainActor.run {
                capturedImage = image
                statusMessage = "Decoding…"
            }
            decodeImage(image)
        }
    }

    private func decodeImage(_ image: UIImage) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Try direct decode first (pixel-perfect images), then camera decode
            let result = MatrixDecoder.decodeAny(image: image)
            DispatchQueue.main.async {
                if let text = result {
                    decodedText = text
                    statusMessage = "✅ Decoded \(text.utf8.count) bytes"
                } else {
                    statusMessage = "❌ Could not decode — try holding camera closer or use a saved image"
                }
                isDecoding = false
            }
        }
    }
}

#Preview {
    ReceiverView()
}
