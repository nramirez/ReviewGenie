import Foundation
import Photos
// import UIKit // No longer needed as we are dealing with Data for macOS compatibility
import AppKit // If NSImage specific operations were ever needed, but currently not used directly.
             // For now, keeping AppKit import in case any PHImageManager details rely on it implicitly for macOS context,
             // but primarily we aim to pass Data or CGImageRef out of services.

class PhotoLibraryService {

    func requestAuthorization() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return newStatus == .authorized || newStatus == .limited
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func fetchPhotoAssets(forMonth month: Int, year: Int) async -> [PHAsset] {
        // Ensure authorization before fetching
        guard await requestAuthorization() else {
            print("Photo library access not granted.")
            return []
        }

        var assets: [PHAsset] = []
        
        let fetchOptions = PHFetchOptions()
        
        // Create date components for the start and end of the month
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        guard let startDate = Calendar.current.date(from: components) else {
            print("Error: Could not create start date for month \(month), year \(year).")
            return []
        }
        
        var endComponents = DateComponents()
        endComponents.month = 1 // Prepare to calculate the start of the next month
        endComponents.day = -1 // Then subtract one day to get the end of the current month
        guard let monthEndDate = Calendar.current.date(byAdding: endComponents, to: startDate, wrappingComponents: false),
              // The predicate uses '< actualEndDate', so actualEndDate should be the very start of the day *after* the desired range.
              let actualEndDate = Calendar.current.date(byAdding: .day, value: 1, to: monthEndDate) 
        else {
            print("Error: Could not create end date for month \(month), year \(year).")
            return []
        }
        
        // Predicate filters by image media type, presence of location data, and creation date within the specified month.
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d AND location != NIL AND creationDate >= %@ AND creationDate < %@", 
                                             PHAssetMediaType.image.rawValue, 
                                             startDate as NSDate, 
                                             actualEndDate as NSDate)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        // fetchOptions.fetchLimit = 100 // Example limit, can be removed or made configurable

        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        fetchResult.enumerateObjects { (asset, _, _) in
            assets.append(asset)
        }
        
        print("Fetched \(assets.count) assets with location for \(month)/\(year).")
        return assets
    }
    
    // New method to fetch assets based on a DateInterval
    func fetchPhotoAssets(dateInterval: DateInterval) async -> [PHAsset] {
        guard await requestAuthorization() else {
            print("Photo library access not granted.")
            return []
        }

        var assets: [PHAsset] = []
        let fetchOptions = PHFetchOptions()

        // Use the provided dateInterval for the predicate.
        // Note: This predicate fetches all images within the date range; 
        // location data is checked separately after this initial fetch.
        fetchOptions.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate >= %@ AND creationDate < %@",
            PHAssetMediaType.image.rawValue,
            dateInterval.start as NSDate,
            dateInterval.end as NSDate
        )
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        fetchResult.enumerateObjects { (asset, _, _) in
            // Manually filter for assets with location data, as the fetch predicate above does not include this criterion.
            if asset.location != nil {
                assets.append(asset)
            }
        }

        print("Fetched \(assets.count) assets with location from \(dateInterval.start) to \(dateInterval.end).")
        return assets
    }
    
    // Helper to get image data from a PHAsset
    func getImageData(for asset: PHAsset, targetSize: CGSize = PHImageManagerMaximumSize, deliveryMode: PHImageRequestOptionsDeliveryMode = .highQualityFormat, completion: @escaping (Data?) -> Void) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true // Allow downloading from iCloud if necessary
        options.isSynchronous = false // Perform asynchronously to avoid blocking UI
        options.deliveryMode = deliveryMode // .opportunistic, .highQualityFormat, .fastFormat
        options.resizeMode = (targetSize == PHImageManagerMaximumSize) ? .none : .fast // Use .exact for precise targetSize, .fast for performance
        
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { (data, _, _, info) in
            // Check if data is degraded (e.g. a thumbnail when high quality was requested but not yet available)
            // let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            // if isDegraded && deliveryMode == .highQualityFormat { /* Potentially wait or re-request */ }
            completion(data)
        }
    }
}