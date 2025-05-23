import SwiftUI
import PhotosUI
import ImageIO // For CGImageSource
import UniformTypeIdentifiers // For UTType

// Note: This view relies on ProcessedPhoto and FileUtils.
// Ensure ProcessedPhoto is defined (e.g., in Models folder)
// and FileUtils is defined (e.g., in Utils folder) and accessible.

struct PhotoPickerView: View {
    @Binding var selectedPhotosFromPicker: [PhotosPickerItem]
    @Binding var processedPhotos: [ProcessedPhoto]

    @State private var displayedPhotoPreviews: [Image] = []

    var body: some View {
        VStack {
            Text("Select Photos")
                .font(.title2)
                .padding()

            PhotosPicker(
                selection: $selectedPhotosFromPicker,
                maxSelectionCount: 10,
                matching: .images
            ) {
                Label("Choose Photos", systemImage: "photo.on.rectangle.angled")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(white: 0.3))
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }

            if !processedPhotos.isEmpty {
                Text("\(processedPhotos.count) photos selected")
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(displayedPhotoPreviews.indices, id: \.self) { index in
                            displayedPhotoPreviews[index]
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .cornerRadius(8)
                                .clipped()
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 5)
                }
                .frame(height: 90)
            }
        }
        .onChange(of: selectedPhotosFromPicker) {
             processSelectedPhotos(items: selectedPhotosFromPicker)
        }
        .onChange(of: processedPhotos) {
            updatePreviews(from: processedPhotos)
        }
    }

    private func processSelectedPhotos(items: [PhotosPickerItem]) {
        guard !items.isEmpty else {
            processedPhotos = []
            return
        }

        Task(priority: .userInitiated) {
            var newlyProcessedPhotos: [ProcessedPhoto] = []
            let maxPixelSize: CGFloat = 2048
            let compressionQuality: CGFloat = 0.75

            for item in items {
                do {
                    guard let rawData = try await item.loadTransferable(type: Data.self) else { continue }
                    guard let source = CGImageSourceCreateWithData(rawData as CFData, nil) else { continue }

                    var originalFileExtension = "jpg"
                    if let utTypeIdentifier = CGImageSourceGetType(source) as String?,
                       let utType = UTType(utTypeIdentifier) {
                        originalFileExtension = utType.preferredFilenameExtension ?? "jpg"
                    }

                    let originalFileName = "original_\(UUID().uuidString).\(originalFileExtension)"
                    guard let originalStorageDir = FileUtils.getOriginalImageStorageDirectory() else {
                        print("Error: Could not get original image storage directory for item \(item.itemIdentifier ?? "unknown")")
                        continue
                    }
                    if !FileUtils.saveImageData(data: rawData, fileName: originalFileName, inDirectory: originalStorageDir) {
                        print("Error: Failed to save original image data for item \(item.itemIdentifier ?? "unknown")")
                        continue
                    }
                    print("Saved original from picker as: \(originalFileName)")

                    guard let optimizedData = FileUtils.createOptimizedImageData(from: source, maxPixelSize: maxPixelSize, compressionQuality: compressionQuality) else {
                        print("Warning: Failed to optimize image for item \(item.itemIdentifier ?? "unknown")")
                        continue
                    }

                    let metadataDict = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
                    let hashableMetadata = FileUtils.makeMetadataHashable(metadataDict)
                    let coordinate = FileUtils.extractCoordinate(fromMetadata: metadataDict)

                    let optimizedFileName = "optimized_\(UUID().uuidString).\(originalFileExtension)"

                    if FileUtils.saveImageData(data: optimizedData, fileName: optimizedFileName) {
                        let processed = ProcessedPhoto(
                            originalItemIdentifier: item.itemIdentifier,
                            optimizedFileName: optimizedFileName,
                            originalFileName: originalFileName,
                            metadata: hashableMetadata,
                            coordinate: coordinate
                        )
                        newlyProcessedPhotos.append(processed)
                        print("Saved optimized from picker as: \(optimizedFileName)")
                    } else {
                        print("Error: Failed to save optimized image data for item \(item.itemIdentifier ?? "unknown")")
                    }

                } catch {
                    print("Error processing photo item \(item.itemIdentifier ?? "unknown"): \(error)")
                }
            }

            await MainActor.run {
                self.processedPhotos = newlyProcessedPhotos
            }
        }
    }

    private func updatePreviews(from currentProcessedPhotos: [ProcessedPhoto]) {
        Task {
             var images: [Image] = []
             for photo in currentProcessedPhotos {
                 if let img = photo.getSwiftUIImage() {
                     images.append(img)
                 } else {
                     images.append(Image(systemName: "photo.fill")) // Fallback placeholder
                 }
             }
             await MainActor.run {
                 self.displayedPhotoPreviews = images
             }
        }
    }
}