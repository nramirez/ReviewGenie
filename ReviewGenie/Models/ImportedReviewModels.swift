import Foundation
import CoreLocation // For coordinates

// --- GeoJSON Structures ---
// These structures are designed to decode review data from a GeoJSON file,
// commonly used for representing geographic data along with associated attributes.

/// Represents the top-level structure of a GeoJSON file containing a collection of review features.
/// Conforms to `Codable` for easy parsing from JSON.
struct ReviewFeatureCollection: Codable {
    /// The type of GeoJSON object, expected to be "FeatureCollection".
    let type: String
    /// An array of `ReviewFeature` objects, each representing a single review.
    let features: [ReviewFeature]
}

/// Represents a single review entry (a "feature") within the GeoJSON structure.
/// Each feature typically has a geometry (location) and properties (review details).
struct ReviewFeature: Codable {
    /// The type of GeoJSON object, expected to be "Feature".
    let type: String
    /// The geographical information (e.g., coordinates) for the review.
    let geometry: GeoJSONGeometry
    /// The detailed attributes of the review (e.g., text, rating, date).
    let properties: ReviewProperties
}

/// Represents the geographical point (geometry) associated with a review.
/// Renamed to `GeoJSONGeometry` to avoid potential naming conflicts with CoreLocation's `CLLocationCoordinate2D` or similar.
struct GeoJSONGeometry: Codable {
    /// The type of geometry, expected to be "Point" for a single location.
    let type: String
    /// An array of `Double` values representing the coordinates.
    /// In GeoJSON, coordinates are typically ordered as [longitude, latitude].
    let coordinates: [Double]
}

// --- Nested Structures from Properties ---
// These structures represent parts of the `properties` field within a `ReviewFeature`.

/// Holds location-specific details extracted from the review properties.
struct LocationProperties: Codable {
    /// The street address of the reviewed location, if available.
    let address: String?
    /// The country code (e.g., "US", "GB") for the location. This was a new field identified from the JSON structure.
    let countryCode: String?
    /// The name of the reviewed place or establishment, if available.
    let name: String?
    
    // Example of using CodingKeys if JSON keys differ from struct property names.
    // This section is commented out as current property names match common camelCase conventions
    // or are handled by the default Codable synthesis if JSON keys are also camelCase.
    // If JSON used snake_case (e.g., "country_code"), uncommenting and adjusting this would be necessary.
    // enum CodingKeys: String, CodingKey {
    //     case address
    //     case countryCode = "country_code" // Maps "country_code" from JSON to `countryCode`
    //     case name
    // }
}

/// Represents a specific question and its corresponding rating, often used for sub-ratings (e.g., "Food: 4 stars").
struct QuestionRating: Codable {
    /// The text of the question (e.g., "Food", "Service").
    let question: String?
    /// The rating given for this specific question, typically an integer.
    let rating: Int?
}

// --- Review Properties Structure (Updated based on actual JSON) ---

/// Contains the detailed attributes and content of a single review.
/// This structure is nested within `ReviewFeature`'s `properties` field.
struct ReviewProperties: Codable {
    /// The timestamp of when the review was published, typically in ISO 8601 format.
    let date: String?
    /// The overall rating given in the review, usually on a 1-5 star scale.
    let fiveStarRatingPublished: Int?
    /// A URL pointing to the reviewed place on Google Maps, if available.
    let googleMapsURL: String?
    /// Nested structure containing location details like address and name.
    let location: LocationProperties?
    /// An array of `QuestionRating` objects, representing sub-ratings for different aspects (e.g., food, service).
    let questions: [QuestionRating]?
    /// The textual content of the review.
    let reviewTextPublished: String?
    
    /// Maps JSON keys (often snake_case) to the struct's camelCase property names.
    /// This is crucial for `Codable` to correctly parse JSON data where key names don't match property names directly.
    enum CodingKeys: String, CodingKey {
        case date
        case fiveStarRatingPublished = "five_star_rating_published"
        case googleMapsURL = "google_maps_url"
        case location
        case questions
        case reviewTextPublished = "review_text_published"
    }
    
    /// A computed property that attempts to parse the `date` string into a `Date` object.
    /// Returns `nil` if the `date` string is missing or cannot be parsed.
    var reviewDate: Date? {
        guard let publishedString = date else { return nil }
        let formatter = ISO8601DateFormatter()
        // Common ISO 8601 format options. Adjust if the source JSON uses a slightly different variant.
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: publishedString)
    }
    
    /// A computed property to extract `CLLocationCoordinate2D` from the `GeoJSONGeometry`.
    /// Note: This property is declared but its implementation to fetch from `ReviewFeature.geometry.coordinates`
    /// would typically reside in a higher-level struct or a processing function that has access to both
    /// `ReviewProperties` and its parent `ReviewFeature`'s `geometry`.
    /// For this model, it's a placeholder; the actual coordinate extraction logic will be elsewhere.
    var coordinate: CLLocationCoordinate2D?
    // Example of how it might be populated if geometry were directly accessible:
    // var coordinate: CLLocationCoordinate2D? {
    //     guard let geometry = associatedGeometry, geometry.coordinates.count == 2 else { return nil }
    //     return CLLocationCoordinate2D(latitude: geometry.coordinates[1], longitude: geometry.coordinates[0])
    // }
}

// --- Review Origin Enum (Simplified) ---

/// An enumeration to specify the source or origin of a review.
/// Renamed from `ReviewSource` for clarity. Conforms to `Codable` and `String` raw value for easy storage/retrieval.
enum ReviewOrigin: String, Codable {
    /// Indicates a review imported from an external source (e.g., Google Takeout).
    case imported       = "imported"
    /// Indicates a review created directly within this application.
    case createdInApp   = "created_in_app"
}

// --- Local Storage Model (Placeholder) ---

/// Represents a processed review, adapted for local storage (e.g., in CoreData or SwiftData).
/// This struct defines the schema for how review data, once parsed and processed from GeoJSON or other sources,
/// will be structured for use within the app's database.
struct ImportedReview {
    /// A unique identifier (UUID) for the review, serving as a primary key in a local database.
    let id: UUID
    /// The origin of the review (e.g., imported, created in-app).
    let origin: ReviewOrigin // Updated from 'source: ReviewSource'
    /// A unique identifier for the place, potentially extracted or derived from the `googleMapsURL`.
    /// This helps in uniquely identifying places across different reviews.
    let urlBasedPlaceId: String
    /// The parsed `Date` object representing when the review was made.
    let timestamp: Date
    /// The name of the reviewed place.
    let placeName: String?
    /// The address of the reviewed place.
    let address: String?
    /// The textual content of the review.
    let reviewText: String?
    /// The overall rating, typically an integer (e.g., 1-5). Renamed from `fiveStarRatingPublished` for local model clarity.
    let overallRating: Int?
    /// An array of `QuestionRating` objects, storing any sub-ratings associated with the review.
    let subRatings: [QuestionRating]?
    /// The latitude of the reviewed place's location.
    let latitude: Double?
    /// The longitude of the reviewed place's location.
    let longitude: Double?
    /// The original Google Maps URL, stored for reference or future use.
    let originalGoogleMapsURL: String?
}