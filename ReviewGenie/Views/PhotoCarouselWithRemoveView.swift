import SwiftUI
import UniformTypeIdentifiers // Add this import for URL transferable conformance

// Helper struct to associate an ID with an Image for the carousel
private struct IdentifiableImageDisplay: Identifiable { // Renamed to avoid potential future global conflicts
    let id: ProcessedPhoto.ID
    let image: Image // This image is generated from the OPTIMIZED version for display
    let originalFileNameForDrag: String // Keep original filename for drag operation
}

// New private struct for the carousel item view
private struct PhotoCarouselItemView: View {
    let identifiableImageDisplay: IdentifiableImageDisplay
    let originalPhoto: ProcessedPhoto? // To find the exact ProcessedPhoto for removal callback
    let processedPhotosCount: Int
    let originalImagesDirectoryURL: URL?
    var onRemovePhoto: ((ProcessedPhoto) -> Void)?

    private func getDraggableURL() -> URL? {
        guard let dirURL = originalImagesDirectoryURL, 
              let oPhoto = originalPhoto, // Ensure originalPhoto is not nil for consistency with remove button
              oPhoto.id == identifiableImageDisplay.id // Double check we have the right mapping
        else { return nil }
        
        let fileURL = dirURL.appendingPathComponent(identifiableImageDisplay.originalFileNameForDrag)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    var body: some View {
        identifiableImageDisplay.image
            .resizable()
            .scaledToFill()
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if onRemovePhoto != nil && processedPhotosCount > 1 && originalPhoto != nil {
                    Button {
                        if let photoToRemove = originalPhoto {
                            onRemovePhoto?(photoToRemove)
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 22))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
            // Corrected: .draggable takes the Transferable item directly.
            // The ?? URL(fileURLWithPath: "") is your addition to prevent nil if you prefer.
            .draggable(getDraggableURL() ?? URL(fileURLWithPath: "")) 
    }
}

struct PhotoCarouselWithRemoveView: View {
    let processedPhotos: [ProcessedPhoto] // Should contain originalFileName
    var onRemovePhoto: ((ProcessedPhoto) -> Void)?
    let originalImagesDirectoryURL: URL? // URL to the directory of STICKER_LINE_STICKER_LINEoriginal, non-optimized images

    @State private var displayImages: [IdentifiableImageDisplay] = []

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(displayImages) { identifiableImageDisplayItem in
                    let correspondingProcessedPhoto = processedPhotos.first { $0.id == identifiableImageDisplayItem.id }
                    
                    PhotoCarouselItemView(
                        identifiableImageDisplay: identifiableImageDisplayItem,
                        originalPhoto: correspondingProcessedPhoto,
                        processedPhotosCount: processedPhotos.count,
                        originalImagesDirectoryURL: originalImagesDirectoryURL,
                        onRemovePhoto: onRemovePhoto
                    )
                }
            }
            .padding(.horizontal) 
        }
        .frame(height: 110) 
        .onAppear {
            loadImagesForDisplay()
        }
        .onChange(of: processedPhotos) {
            loadImagesForDisplay()
        }
    }

    // This loads OPTIMIZED images for display in the carousel
    private func loadImagesForDisplay() {
        Task(priority: .userInitiated) { @MainActor in
            var loadedUiImages: [IdentifiableImageDisplay] = []
            for photoData in processedPhotos {
                var imageToDisplay: Image? = nil
                var loadedImageTypeForPrint = "PLACEHOLDER" // For logging

                // 1. Try to load the OPTIMIZED image for display
                if let optimizedDir = FileUtils.getImagesDirectory(), // Optimized images directory
                   let optimizedImgData = FileUtils.loadImageData(fileName: photoData.optimizedFileName, fromDirectory: optimizedDir),
                   let nsImg = NSImage(data: optimizedImgData) {
                    imageToDisplay = Image(nsImage: nsImg)
                    loadedImageTypeForPrint = "OPTIMIZED"
                }
                
                // 2. If OPTIMIZED fails, try to load ORIGINAL image for display (as fallback)
                if imageToDisplay == nil {
                    if let originalDir = FileUtils.getOriginalImageStorageDirectory(),
                       let originalImgData = FileUtils.loadImageData(fileName: photoData.originalFileName, fromDirectory: originalDir),
                       let nsImg = NSImage(data: originalImgData) {
                        imageToDisplay = Image(nsImage: nsImg)
                        loadedImageTypeForPrint = "ORIGINAL (fallback)"
                    } else {
                        // 3. If both fail, use a system placeholder
                        imageToDisplay = Image(systemName: "photo.fill") 
                        // loadedImageTypeForPrint remains "PLACEHOLDER"
                    }
                }
                
                print("Carousel: Displaying \(loadedImageTypeForPrint) for photo ID \(photoData.id) (opt: \(photoData.optimizedFileName), orig: \(photoData.originalFileName))")
                loadedUiImages.append(IdentifiableImageDisplay(id: photoData.id, image: imageToDisplay!, originalFileNameForDrag: photoData.originalFileName))
            }
            self.displayImages = loadedUiImages
        }
    }
}