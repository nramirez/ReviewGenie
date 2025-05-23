import Foundation

/// Represents a place, often derived from Google Places API results, adapted for use within the app.
/// This struct consolidates key information about a place, such as its name, address, location, and associated reviews.
struct PlaceResult: Identifiable {
    /// The unique identifier for the place, typically the Google Place ID. Conforms to `Identifiable`.
    let id: String
    /// The human-readable name of the place.
    var name: String
    /// The formatted address of the place.
    var address: String
    /// The geographical latitude of the place.
    var latitude: Double
    /// The geographical longitude of the place.
    var longitude: Double
    /// An optional reference string for a photo of the place. This can be used to fetch the actual image.
    var photoReference: String?
    /// An optional array of reviews fetched for this place.
    var fetchedReviews: [FetchedReview]?
    /// The overall rating of the place, typically on a scale (e.g., 1.0 to 5.0).
    var overallRating: Double?
    /// An optional array of strings describing the types of the place (e.g., "restaurant", "cafe").
    var types: [String]?
}

/// Represents a review fetched for a place, simplified for display or local use.
/// Conforms to `Identifiable` for use in SwiftUI lists and `Hashable` for use in collections requiring hashing.
struct FetchedReview: Identifiable, Hashable {
    /// A unique identifier generated locally for this review instance. Conforms to `Identifiable`.
    let id = UUID()
    /// The name of the author who wrote the review.
    let authorName: String
    /// The rating given by the author, typically an integer (e.g., 1 to 5).
    let rating: Int
    /// The text content of the review.
    let text: String
    /// A human-readable string describing when the review was posted relative to the current time (e.g., "a week ago").
    let relativeTimeDescription: String
}