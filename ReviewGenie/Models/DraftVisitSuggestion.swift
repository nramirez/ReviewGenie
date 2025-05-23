import SwiftUI
import CoreLocation
import Photos

/// Represents a potential visit to a place, generated from a cluster of photos.
/// This struct holds information about the suggested place, associated photos,
/// and the status of its identification process.
struct DraftVisitSuggestion: Identifiable, Hashable {
    /// A unique identifier for this draft suggestion.
    let id = UUID()
    
    /// The name of the place suggested by initial clustering or simple logic (e.g., from photo metadata).
    var suggestedPlaceName: String?
    /// The address of the place suggested by initial clustering or simple logic.
    var suggestedPlaceAddress: String?
    /// The Google Places ID for the initially suggested place, if available.
    var suggestedPlaceID: String? // From Google Places
    
    /// The average geographical coordinate of all photos in the cluster.
    var averageCoordinate: CLLocationCoordinate2D
    /// The date range (start and end) covering all photos in the cluster.
    var dateRange: (start: Date, end: Date)
    
    /// The local identifier of a representative photo asset for this cluster.
    var representativePhotoAssetIdentifier: String? // PHAsset.localIdentifier for one key photo
    /// An array of local identifiers for all photo assets included in this cluster.
    var allPhotoAssetIdentifiersInCluster: [String] // PHAsset.localIdentifiers for all photos in the cluster
    
    // MARK: - Gemini Vision and Google Places API Results
    
    /// Details of the top place identified by the Gemini Vision service.
    var geminiSuggestedTopPick: GeminiVisionService.IdentifiedPlaceDetails?
    /// A list of nearby place candidates retrieved from Google Places API, potentially based on Vision results or location.
    var nearbyPlaceCandidates: [GooglePlacesAPIService.NearbyPlaceInternal]?
    
    /// The current processing status of this suggestion.
    var status: SuggestionStatus = .pendingPhotoProcessing // Default status

    // MARK: - Hashable Conformance

    /// Provides a hash value for the suggestion, enabling it to be used in hash-based collections.
    /// Note: `averageCoordinate` is hashed by its `latitude` and `longitude` components.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(suggestedPlaceName)
        hasher.combine(suggestedPlaceAddress)
        hasher.combine(suggestedPlaceID)
        hasher.combine(averageCoordinate.latitude)
        hasher.combine(averageCoordinate.longitude)
        hasher.combine(dateRange.start)
        hasher.combine(dateRange.end)
        hasher.combine(representativePhotoAssetIdentifier)
        hasher.combine(allPhotoAssetIdentifiersInCluster)
        hasher.combine(geminiSuggestedTopPick)
        hasher.combine(nearbyPlaceCandidates)
        hasher.combine(status)
    }

    // MARK: - Equatable Conformance

    /// Determines if two `DraftVisitSuggestion` instances are equal based on their `id`.
    static func == (lhs: DraftVisitSuggestion, rhs: DraftVisitSuggestion) -> Bool {
        lhs.id == rhs.id
    }
    
    /// Enum representing the various states a `DraftVisitSuggestion` can be in during its lifecycle.
    enum SuggestionStatus: Hashable {
        /// Initial state: The photo cluster has been identified, but no further processing (like Vision API calls) has started.
        case pendingPhotoProcessing
        /// Actively querying the Gemini Vision service to identify the place from photos.
        case identifyingWithVisionService
        /// The Gemini Vision service call completed successfully. This doesn't guarantee a place was identified, just that the call succeeded.
        case visionServiceSucceeded
        /// The Gemini Vision service call failed. The associated value contains an optional error message.
        case visionServiceFailed(error: String?)
        
        // case pendingIdentification // Potentially redundant, consider removal.
        // case identifyingPlace // Potentially redundant, consider removal.
        
        /// The place has been identified, either through fallback mechanisms (e.g., Google Places API directly) or manual user selection.
        /// Contains the name, optional address, and optional place ID of the identified place.
        case identified(placeName: String, placeAddress: String?, placeID: String?)
        /// A general identification failure occurred, possibly after Vision service failure or if other identification methods also failed.
        /// The associated value contains an optional error message.
        case identificationFailed(error: String?)
        
        /// The user has confirmed this suggestion and intends to create a review for it.
        case userConfirmed
        /// The user has dismissed or ignored this suggestion.
        case userIgnored
    }
    
    // MARK: - Thumbnail Generation

    /// Asynchronously fetches a thumbnail `Image` for the representative photo of this suggestion.
    ///
    /// This function attempts to load the image from the Photo Library. It handles cases where the
    /// image might be in iCloud, degraded, or if an error occurs during fetching.
    /// - Parameter targetSize: The desired size of the thumbnail. Defaults to 100x100 points.
    /// - Returns: An optional `Image`. Returns `nil` or a placeholder system image if the asset ID is missing,
    ///            the asset cannot be fetched, or an error occurs.
    /// - Note: This is a simplified version. For more robust image loading, especially with caching
    ///         and advanced error handling, consider using a dedicated `ImageLoader` service.
    @MainActor
    func getRepresentativeThumbnail(targetSize: CGSize = CGSize(width: 100, height: 100)) async -> Image? {
        guard let assetID = representativePhotoAssetIdentifier else {
            // No representative photo asset ID available.
            return Image(systemName: "photo.fill")
        }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
            // The asset could not be fetched using the provided ID.
            return Image(systemName: "photo.fill")
        }

        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true // Allow downloading from iCloud if necessary.
        options.deliveryMode = .opportunistic // Request a lower-quality image quickly, then a higher-quality one.
        options.resizeMode = .fast // Prioritize speed over exact size matching for resizing.
        options.isSynchronous = false // Perform the request asynchronously.

        return await withCheckedContinuation { continuation in
            var didResume = false // Flag to ensure the continuation is resumed only once.

            manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, info in
                // If continuation has already been resumed (e.g., by a degraded image callback followed by a full quality one), ignore further callbacks.
                guard !didResume else { return }

                let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false

                // Prioritize handling errors.
                if let error = info?[PHImageErrorKey] as? Error {
                    print("Error loading thumbnail for asset ID \(assetID): \(error.localizedDescription)")
                    continuation.resume(returning: Image(systemName: "exclamationmark.triangle.fill"))
                    didResume = true
                    return
                }

                // If a non-nil image is received and it's not degraded, this is the desired full-quality image.
                if let nsImage = image, !isDegraded {
                    continuation.resume(returning: Image(nsImage: nsImage))
                    didResume = true
                    return
                }
                
                // Handle cases for the final callback (not degraded) if the image is still nil or is in iCloud.
                if !isDegraded { // This block executes when the current callback is for the final image result.
                    if let isCloud = info?[PHImageResultIsInCloudKey] as? Bool, isCloud, image == nil {
                        // Image is in iCloud and not yet downloaded, and no placeholder/degraded image was provided.
                        print("Thumbnail for asset ID \(assetID) is in iCloud (and no image yet), placeholder returned.")
                        continuation.resume(returning: Image(systemName: "icloud.fill"))
                        didResume = true
                        return
                    } else if image == nil {
                        // Final callback, but image is nil for an unknown reason (not explicitly an error or iCloud).
                        print("Failed to load thumbnail (final callback, image nil). Asset ID \(assetID). Info: \(String(describing: info))")
                        continuation.resume(returning: Image(systemName: "photo.fill")) // Generic placeholder
                        didResume = true
                        return
                    }
                    // If 'image' is not nil here but was degraded, the earlier 'if let nsImage = image, !isDegraded' block would have been skipped.
                    // If 'image' is not nil AND not degraded, it's caught by the block above this one.
                }
                // If 'isDegraded' is true and we haven't resumed, it means we've received a temporary, lower-quality image.
                // We wait for another callback which should provide the non-degraded image or an error.
                // If 'options.deliveryMode' was '.highQualityFormat', we might only get one callback.
            }
        }
    }
}