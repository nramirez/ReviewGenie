import Foundation
import SwiftData
import CoreLocation

/// Represents references to original and optimized image files associated with a visit.
/// This struct is `Codable` for potential storage/transfer and `Hashable` & `Identifiable` for UI purposes.
struct ImageFileReference: Codable, Hashable, Identifiable {
    /// A unique identifier for the image file reference, primarily for `Identifiable` conformance.
    let id: UUID
    /// The file name of the original, full-resolution image.
    let originalFileName: String
    /// The file name of the optimized or thumbnail version of the image.
    let optimizedFileName: String

    /// Initializes a new `ImageFileReference`.
    /// - Parameters:
    ///   - id: A unique identifier. Defaults to a new `UUID`.
    ///   - originalFileName: The name of the original image file.
    ///   - optimizedFileName: The name of the optimized image file.
    init(id: UUID = UUID(), originalFileName: String, optimizedFileName: String) {
        self.id = id
        self.originalFileName = originalFileName
        self.optimizedFileName = optimizedFileName
    }
}

/// Represents a user's visit to a place, intended for storage using SwiftData.
/// This class captures details about the visit, the place, associated photos, and review drafts.
@Model
final class VisitRecord {
    /// A unique identifier for the visit record, ensuring each record is distinct.
    @Attribute(.unique) var id: UUID
    /// The date and time of the visit.
    var date: Date
    /// The Google Place ID for the visited location, if available.
    var placeID: String?
    /// The name of the visited place.
    var placeName: String
    /// The address of the visited place.
    var address: String
    /// The geographical latitude of the visited place.
    var latitude: Double
    /// The geographical longitude of the visited place.
    var longitude: Double
    /// The user's overall rating for the experience at this place (e.g., on a 0-5 scale).
    var overallExperienceRating: Double = 0.0
    /// The number of photos used to document or generate a review for this visit.
    var numberOfPhotosUsed: Int
    /// An array of AI-generated review draft texts.
    var generatedDrafts: [String]
    /// The final review text selected or manually entered by the user.
    var selectedReview: String?
    /// An array of `ImageFileReference` objects, linking to stored images associated with this visit.
    var imageReferences: [ImageFileReference]?
    
    /// The origin of this review record (e.g., "imported", "created_in_app"). Stored as a raw string value of `ReviewOrigin`.
    var origin: String = ReviewOrigin.createdInApp.rawValue
    /// A unique identifier for the place, potentially derived from its Google Maps URL, especially for imported reviews.
    var urlBasedPlaceId: String?
    /// `Data` representation of sub-ratings (e.g., for food, service, ambiance). This is typically a JSON-encoded array of `QuestionRating`.
    var subRatingsData: Data?
    /// The URL of the place on Google Maps, if available.
    var googleMapsURL: String?
    
    /// Initializes a new `VisitRecord`.
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new `UUID`.
    ///   - date: Date of the visit. Defaults to the current date and time.
    ///   - placeID: Google Place ID. Defaults to `nil`.
    ///   - placeName: Name of the place.
    ///   - address: Address of the place.
    ///   - latitude: Latitude of the place.
    ///   - longitude: Longitude of the place.
    ///   - overallExperienceRating: Overall rating. Defaults to `0.0`.
    ///   - numberOfPhotosUsed: Number of photos used. Defaults to `0`.
    ///   - generatedDrafts: Array of generated review drafts. Defaults to an empty array.
    ///   - selectedReview: The user's selected review text. Defaults to `nil`.
    ///   - imageReferences: References to associated image files. Defaults to `nil`.
    ///   - origin: The origin of the review. Defaults to `.createdInApp`.
    ///   - urlBasedPlaceId: URL-based place identifier. Defaults to `nil`.
    ///   - subRatingsData: Serialized sub-ratings. Defaults to `nil`.
    ///   - googleMapsURL: Google Maps URL for the place. Defaults to `nil`.
    init(
        id: UUID = UUID(),
        date: Date = .now,
        placeID: String? = nil,
        placeName: String,
        address: String,
        latitude: Double,
        longitude: Double,
        overallExperienceRating: Double = 0.0,
        numberOfPhotosUsed: Int = 0,
        generatedDrafts: [String] = [],
        selectedReview: String? = nil,
        imageReferences: [ImageFileReference]? = nil,
        origin: ReviewOrigin = .createdInApp,
        urlBasedPlaceId: String? = nil,
        subRatingsData: Data? = nil,
        googleMapsURL: String? = nil
    ) {
        self.id = id
        self.date = date
        self.placeID = placeID
        self.placeName = placeName
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.overallExperienceRating = overallExperienceRating
        self.numberOfPhotosUsed = numberOfPhotosUsed
        self.generatedDrafts = generatedDrafts
        self.selectedReview = selectedReview
        self.imageReferences = imageReferences
        self.origin = origin.rawValue
        self.urlBasedPlaceId = urlBasedPlaceId
        self.subRatingsData = subRatingsData
        self.googleMapsURL = googleMapsURL
    }
    
    /// Computed property to get the `ReviewOrigin` enum from the stored `origin` string.
    /// Defaults to `.createdInApp` if the string is invalid or cannot be parsed.
    var reviewOrigin: ReviewOrigin {
        ReviewOrigin(rawValue: origin) ?? .createdInApp
    }
    
    /// Computed property to deserialize `subRatingsData` into an array of `QuestionRating` objects.
    /// Returns `nil` if `subRatingsData` is `nil` or if deserialization fails.
    var subRatings: [QuestionRating]? {
        guard let data = subRatingsData else { return nil }
        return try? JSONDecoder().decode([QuestionRating].self, from: data)
    }
    
    /// Computed property to get the geographical location as a `CLLocationCoordinate2D` object.
    var location: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
