import Foundation
import CoreLocation

// Assume StorageManager is your interface to CoreData/SwiftData/etc.
/// Protocol defining the contract for a storage manager responsible for handling review data.
protocol StorageManagerProtocol {
    /// Deletes all reviews associated with a specific origin (e.g., imported, user-created).
    func deleteAllReviews(fromOrigin origin: ReviewOrigin) async
    /// Saves an imported review record to the persistent store.
    func saveImportedReview(_ review: VisitRecord) async throws
    /// Checks if there are any imported reviews currently in the store.
    func hasImportedReviews() async -> Bool
    // Add other necessary storage methods...
}

/// Enumerates potential errors that can occur during the review import process.
enum ImportError: Error {
    case invalidData // Indicates that the input data format is not as expected.
    case parsingFailed(Error) // Encapsulates an error that occurred during JSON parsing.
    case missingRequiredData(featureIndex: Int, field: String) // Indicates a required field was missing for a specific feature.
    case storageError(Error) // Encapsulates an error from the storage manager during save operations.
    case placeIdExtractionFailed(url: String?) // Indicates failure to extract a Place ID from a Google Maps URL.
    case urlIdExtractionFailed(url: String?) // Indicates failure to extract a URL-based ID from a Google Maps URL.
}

/// Represents the result of an import operation, summarizing successes, failures, and any errors encountered.
struct ImportResult {
    let importedCount: Int // The number of reviews successfully imported.
    let failedCount: Int // The number of reviews that failed to import.
    let errors: [Error] // A collection of specific errors encountered during the import.
}

/// Service responsible for importing reviews from external data sources (e.g., Google Takeout JSON).
class ReviewImporterService {
    
    private let storageManager: StorageManagerProtocol // The storage manager instance for data persistence.
    
    /// Initializes the service with a concrete implementation of `StorageManagerProtocol`.
    /// - Parameter storageManager: The storage manager to use for saving imported reviews.
    init(storageManager: StorageManagerProtocol) {
        self.storageManager = storageManager
    }
    
    /// Imports reviews from the provided `Data` object, typically a JSON file.
    /// - Parameter data: The raw data containing the reviews to be imported.
    /// - Returns: An `ImportResult` summarizing the outcome of the import process.
    func importReviews(from data: Data) async -> ImportResult {
        var importedCount = 0
        var failedCount = 0
        var errors: [Error] = []
        
        let decoder = JSONDecoder() // For decoding JSON data.
        let encoder = JSONEncoder() // For encoding sub-ratings data.
        let featureCollection: ReviewFeatureCollection // Holds the parsed GeoJSON feature collection.
        
        // Before importing new reviews, delete any existing reviews marked as 'imported'.
        // This prevents duplicates if the same file is imported multiple times.
        // Errors during deletion are typically logged by the storage manager itself.
        await storageManager.deleteAllReviews(fromOrigin: .imported)
        
        // Attempt to decode the top-level GeoJSON structure.
        do {
            featureCollection = try decoder.decode(ReviewFeatureCollection.self, from: data)
        } catch let error {
            // If the main JSON structure cannot be parsed, it's a fatal error for this import.
            errors.append(ImportError.parsingFailed(error))
            return ImportResult(importedCount: 0, failedCount: 1, errors: errors) // Indicate 1 failed item (the file itself).
        }
        
        // Iterate over each feature (review) in the collection.
        for (index, feature) in featureCollection.features.enumerated() {
            // Ensure the 'properties' object, which contains review details, exists.
            guard let properties = Optional(feature.properties) else {
                // This case should ideally not be hit if the initial parsing was successful
                // and the GeoJSON structure is valid, but it's a good safeguard.
                failedCount += 1
                errors.append(ImportError.missingRequiredData(featureIndex: index, field: "properties"))
                continue // Skip to the next feature.
            }
            
            // --- Extract Key Data ---
            // The review date is essential.
            guard let timestamp = properties.reviewDate else {
                failedCount += 1
                errors.append(ImportError.missingRequiredData(featureIndex: index, field: "date (parsable date)"))
                continue
            }
            
            // Attempt to extract a unique identifier from the Google Maps URL.
            // This ID helps in uniquely identifying the place, especially when a canonical Google Place ID isn't available.
            guard let urlString = properties.googleMapsURL,
                  let urlBasedId = extractUrlBasedId(from: urlString) else {
                failedCount += 1
                errors.append(ImportError.urlIdExtractionFailed(url: properties.googleMapsURL))
                continue
            }
            
            // --- Extract Coordinates (Provide default 0.0 if missing) ---
            var latitude: Double = 0.0
            var longitude: Double = 0.0
            // GeoJSON coordinates are typically [longitude, latitude].
            if feature.geometry.coordinates.count == 2 {
                longitude = feature.geometry.coordinates[0]
                latitude = feature.geometry.coordinates[1]
            }
            
            // --- Encode sub-ratings (e.g., Food, Service, Atmosphere) ---
            // If 'questions' (sub-ratings) are present, encode them into Data for storage.
            var encodedSubRatings: Data? = nil
            if let questions = properties.questions, !questions.isEmpty {
                 encodedSubRatings = try? encoder.encode(questions) // Errors during encoding are ignored for now, resulting in nil.
            }

            // --- Extract specific sub-ratings if available ---
            // The following code block was removed as sub-ratings are now stored as encoded `Data`.
            // Individual sub-rating properties (foodRating, serviceRating, atmosphereRating)
            // on VisitRecord are intended for user-inputted or AI-generated reviews, not directly from this import.
            // var importedFoodRating: Double = 0 // Removed
            // var importedServiceRating: Double = 0 // Removed
            // var importedAtmosphereRating: Double = 0 // Removed
            // if let questions = properties.questions { // Removed
            //     for q in questions { // Removed
            //         if q.question == "Food" { importedFoodRating = Double(q.rating ?? 0) } // Removed
            //         if q.question == "Service" { importedServiceRating = Double(q.rating ?? 0) } // Removed
            //         if q.question == "Atmosphere" { importedAtmosphereRating = Double(q.rating ?? 0) } // Removed
            //     } // Removed
            // } // Removed

            // --- Prepare VisitRecord ---
            // Populate a VisitRecord object with the extracted and processed data.
            // Use default values for non-optional fields if data is missing from the import.
            let placeName = properties.location?.name ?? "Unknown Place"
            let address = properties.location?.address ?? "No Address Provided"
            let overallRating = Double(properties.fiveStarRatingPublished ?? 0)
            
            let visitRecord = VisitRecord(
                id: UUID(), // Generate a new unique ID for this record in our system.
                date: timestamp,
                // placeID (canonical Google Place ID) is left nil as it's typically not available in Takeout data.
                placeName: placeName,
                address: address,
                latitude: latitude,
                longitude: longitude,
                // foodRating, serviceRating, atmosphereRating are not directly set from imported sub-ratings here.
                // They default to 0.0 in VisitRecord and are meant for user input or AI generation.
                overallExperienceRating: overallRating,
                // numberOfPhotosUsed cannot be determined from this import format.
                // generatedDrafts are not relevant for reviews that are already published/imported.
                selectedReview: properties.reviewTextPublished, // Store the main imported review text.
                origin: .imported, // Mark this record as originating from an import.
                urlBasedPlaceId: urlBasedId, // Store the extracted URL-based identifier.
                subRatingsData: encodedSubRatings, // Store the encoded sub-ratings.
                googleMapsURL: properties.googleMapsURL // Store the original Google Maps URL.
            )
            
            // --- Save to Storage ---
            // Attempt to save the newly created VisitRecord.
            do {
                try await storageManager.saveImportedReview(visitRecord)
                importedCount += 1
            } catch let error {
                failedCount += 1
                errors.append(ImportError.storageError(error))
                // Log an error if saving this specific review fails.
                print("Error saving review for URL ID \(urlBasedId) at \(timestamp): \(error)")
            }
        }
        
        // Return the overall result of the import operation.
        return ImportResult(importedCount: importedCount, failedCount: failedCount, errors: errors)
    }
    
    /// Helper function to attempt extracting a unique identifier from a Google Maps URL's 'data' parameter.
    /// This ID is often a hex string (e.g., "0x...") and can serve as a pseudo-unique place identifier.
    /// Example URL: `https://www.google.com/maps/place//data=!4m2!3m1!1s0x0:0x534dad4f615c592`
    /// The goal is to extract the '0x...' part (e.g., "0x534dad4f615c592").
    /// - Parameter urlString: The Google Maps URL string.
    /// - Returns: The extracted identifier string, or `nil` if extraction fails.
    private func extractUrlBasedId(from urlString: String?) -> String? {
        guard let urlString = urlString,
              let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil // Invalid URL string or components.
        }

        // The ID is often embedded within the 'data' parameter in the URL path.
        // It typically follows a segment starting with "!1s".
        // Example structure: /data=!4m2!3m1!1s<ID_HERE>
        // 1. Split the path by "/data=" to isolate the data parameter string.
        // 2. Split the data string by "!" to get individual data segments.
        // 3. Find the last segment that starts with "1s".
        // 4. Split that segment by "1s" and take the last part, which should be the ID.
        if let dataString = components.percentEncodedPath.components(separatedBy: "/data=").last,
           let lastPart = dataString.components(separatedBy: "!").last(where: { $0.hasPrefix("1s") }),
           let identifier = lastPart.components(separatedBy: "1s").last, !identifier.isEmpty {
            // The identifier is often a hex string like '0x.....' or other unique strings.
            return identifier
        }

        // Fallback strategy: If the primary method fails, try a simpler approach.
        // This is less robust and more speculative, based on observing some URL patterns
        // where the ID might be the last path component and contain a colon.
        // Example: .../0x534dad4f615c592 (if this were the last path component directly)
        let lastSegment = url.lastPathComponent // Get the last part of the URL path.
        if lastSegment.contains(":") { // Check if it contains a colon, a common characteristic of these IDs.
             return lastSegment
        }
        
        return nil // If both methods fail, no ID could be extracted.
    }
}