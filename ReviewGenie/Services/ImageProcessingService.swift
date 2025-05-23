import Foundation
import Photos
import CoreLocation
import ImageIO // For CGImageSource
import UniformTypeIdentifiers // For UTType

enum ImageProcessingServiceError: Error {
    case assetDataMissing
    case imageSourceCreationFailed
    case optimizationFailed
    case saveFailed
    case originalSaveFailed
    // case metadataExtractionFailed // metadata extraction itself doesn't throw in FileUtils, it returns nil
}

class ImageProcessingService {

    static func processPHAsset(asset: PHAsset,
                               maxPixelSize: CGFloat = 2048,
                               compressionQuality: CGFloat = 0.75) async throws -> ProcessedPhoto {
        
        guard let assetInfo = await loadAssetData(asset: asset) else {
            print("Error: Could not load data and UTI for PHAsset \(asset.localIdentifier)")
            throw ImageProcessingServiceError.assetDataMissing
        }
        
        let originalData = assetInfo.data
        var originalFileExtension = "jpg"
        if let uttype = UTType(assetInfo.uti) {
            originalFileExtension = uttype.preferredFilenameExtension ?? "jpg"
        }
        let originalFileName = "original_\(UUID().uuidString).\(originalFileExtension)"

        guard let originalStorageDir = FileUtils.getOriginalImageStorageDirectory() else {
            print("Error: Could not get original image storage directory.")
            throw ImageProcessingServiceError.originalSaveFailed // Or a more specific error
        }
        guard FileUtils.saveImageData(data: originalData, fileName: originalFileName, inDirectory: originalStorageDir) else {
            print("Error: Failed to save original image data for asset \(asset.localIdentifier) as \(originalFileName)")
            throw ImageProcessingServiceError.originalSaveFailed
        }
        print("Saved original image as: \(originalFileName) to \(originalStorageDir.path)")

        guard let source = CGImageSourceCreateWithData(originalData as CFData, nil) else {
            print("Error: Could not create CGImageSource for PHAsset \(asset.localIdentifier) from original data")
            // Clean up saved original if optimization source fails?
            throw ImageProcessingServiceError.imageSourceCreationFailed
        }

        guard let optimizedData = FileUtils.createOptimizedImageData(
            from: source,
            maxPixelSize: maxPixelSize,
            compressionQuality: compressionQuality
        ) else {
            print("Warning: Failed to optimize image for asset \(asset.localIdentifier)")
            throw ImageProcessingServiceError.optimizationFailed
        }

        let metadataDict = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        let hashableMetadata = FileUtils.makeMetadataHashable(metadataDict)
        let coordinate = FileUtils.extractCoordinate(fromMetadata: metadataDict)

        // Use original extension for optimized version for simplicity or decide on a fixed one like jpg
        let optimizedFileName = "optimized_\(UUID().uuidString).\(originalFileExtension)"
        
        guard FileUtils.saveImageData(data: optimizedData, fileName: optimizedFileName) else {
            print("Error: Failed to save optimized image data for asset \(asset.localIdentifier) as \(optimizedFileName)")
            throw ImageProcessingServiceError.saveFailed
        }
        print("Saved optimized image as: \(optimizedFileName)")

        return ProcessedPhoto(
            originalItemIdentifier: asset.localIdentifier,
            optimizedFileName: optimizedFileName, // Corrected name
            originalFileName: originalFileName,   // New field
            metadata: hashableMetadata,
            coordinate: coordinate
        )
    }

    // Helper to load PHAsset data asynchronously
    public static func loadAssetData(asset: PHAsset) async -> (data: Data, uti: String)? {
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat
            // options.version = .current // or .original - .current is usually fine and faster if edits exist
            // options.progressHandler = { progress, error, stop, info in ... } // Optional progress

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, dataUTI, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    print("Error loading data for PHAsset \(asset.localIdentifier): \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                // Check if data is nil even if no error (e.g. user cancelled iCloud download?)
                guard let loadedData = data, let utiString = dataUTI else {
                    print("Data or dataUTI was nil for PHAsset \(asset.localIdentifier) despite no explicit error.")
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (data: loadedData, uti: utiString))
            }
        }
    }
}

// Helper extension for Data to get MIME type (simplistic)
extension Data {
    func mimeType() -> String {
        var b: UInt8 = 0
        self.copyBytes(to: &b, count: 1)
        switch b {
        case 0xFF: return "image/jpeg"
        case 0x89: return "image/png"
        case 0x47: return "image/gif"
        case 0x4D, 0x49: return "image/tiff"
        default: return "application/octet-stream"
        }
    }
}