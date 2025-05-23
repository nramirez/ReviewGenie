import Foundation

// MARK: - Autocomplete API

/// Represents the top-level response from the Google Places Autocomplete API.
struct AutocompleteResponse: Codable {
    /// An array of `Prediction` objects, each representing a suggested place.
    let predictions: [Prediction]
    /// The status of the API request (e.g., "OK", "ZERO_RESULTS").
    let status: String
}

/// Represents a single place prediction from the Autocomplete API.
struct Prediction: Codable, Identifiable {
    /// Conforms to `Identifiable` using `placeId` for unique identification in SwiftUI lists.
    var id: String { placeId }
    /// A human-readable description of the predicted place (e.g., "Paris, France").
    let description: String
    /// The unique identifier for the place, used to fetch place details.
    let placeId: String
    /// Provides structured information about the prediction, separating main text from secondary text.
    let structuredFormatting: StructuredFormatting

    enum CodingKeys: String, CodingKey {
        case description
        case placeId = "place_id"
        case structuredFormatting = "structured_formatting"
    }
}

/// Contains the main text and secondary text of a place prediction.
/// This helps in displaying the prediction in a more structured format (e.g., bolding the main text).
struct StructuredFormatting: Codable {
    /// The main text of a prediction, usually the name of the place.
    let mainText: String
    /// The secondary text of a prediction, usually the location or address details.
    let secondaryText: String?

    enum CodingKeys: String, CodingKey {
        case mainText = "main_text"
        case secondaryText = "secondary_text"
    }
}

// MARK: - Place Details API

/// Represents the top-level response from the Google Places Details API.
struct PlaceDetailsResponse: Codable {
    /// The detailed information about the requested place. Can be `nil` if the place is not found or an error occurs.
    let result: PlaceDetailsResult?
    /// The status of the API request (e.g., "OK", "NOT_FOUND").
    let status: String
}

/// Contains detailed information about a specific place retrieved from the Place Details API.
struct PlaceDetailsResult: Codable {
    /// The unique identifier for the place.
    let placeId: String
    /// The human-readable name for the place.
    let name: String
    /// The place's address in a human-readable format.
    let formattedAddress: String?
    /// Contains the geographical location (latitude and longitude) of the place.
    let geometry: Geometry?
    /// An array of up to five reviews for the place.
    let reviews: [APIReview]?
    /// The place's overall rating, from 1.0 to 5.0, based on user reviews.
    let rating: Double?
    /// An array of photo objects, each containing a reference to an image.
    let photos: [Photo]?

    enum CodingKeys: String, CodingKey {
        case placeId = "place_id"
        case name
        case formattedAddress = "formatted_address"
        case geometry
        case reviews
        case rating
        case photos
    }
}

/// Represents the geometry information of a place, primarily its location.
struct Geometry: Codable {
    /// The geographical coordinates (latitude and longitude) of the place.
    let location: Location
}

/// Represents a geographical location with latitude and longitude.
struct Location: Codable {
    /// The latitude of the location.
    let lat: Double
    /// The longitude of the location.
    let lng: Double
}

/// Represents a photo associated with a place, as returned by the Place Details API.
struct Photo: Codable {
    /// A string identifier used to retrieve the actual photo image.
    /// This reference can be used with the Place Photos API.
    let photoReference: String
    // Other fields like height, width, html_attributions can be added if needed.
    // For example:
    // let height: Int
    // let width: Int
    // let htmlAttributions: [String]?

    enum CodingKeys: String, CodingKey {
        case photoReference = "photo_reference"
        // Add other coding keys if fields above are uncommented
    }
}

/// Represents a single review for a place, as returned by the Place Details API.
struct APIReview: Codable, Identifiable {
    /// A unique UUID generated locally for `Identifiable` conformance, useful for SwiftUI lists. This is not part of the API response.
    var id = UUID()
    /// The name of the author who wrote the review.
    let authorName: String
    /// The rating given by the author, typically an integer from 1 to 5.
    let rating: Int
    /// A string describing the time of the review relative to the current time (e.g., "a week ago").
    let relativeTimeDescription: String
    /// The text content of the review.
    let text: String
    /// The time the review was submitted, measured in seconds since Epoch.
    let time: Int
    // let profilePhotoUrl: String? // URL to the author's profile photo, if available.
    // let language: String? // The language of the review text, if detected.

    enum CodingKeys: String, CodingKey {
        case authorName = "author_name"
        case rating
        case relativeTimeDescription = "relative_time_description"
        case text
        case time
        // case profilePhotoUrl = "profile_photo_url" // Uncomment if using profilePhotoUrl
    }
}