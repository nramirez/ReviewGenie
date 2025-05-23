import Foundation
import CoreLocation

/// Defines the contract for a service that interacts with the Google Places API.
/// This protocol outlines methods for searching places, fetching place details,
/// retrieving photo URLs, and performing nearby searches using different versions of the API.
protocol GooglePlacesServiceProtocol {
    /// Searches for places based on a query string.
    /// - Parameter query: The text string to search for (e.g., "restaurants in New York").
    /// - Returns: An array of `PlaceResult` objects matching the query.
    /// - Throws: An error if the search fails or the API returns an error.
    func searchPlaces(query: String) async throws -> [PlaceResult] // Existing method

    /// Fetches detailed information for a specific place using its Place ID.
    /// - Parameter placeID: The unique identifier for the place.
    /// - Returns: A `PlaceResult` object containing detailed information about the place.
    /// - Throws: An error if fetching details fails or the API returns an error.
    func fetchPlaceDetails(placeID: String) async throws -> PlaceResult // Existing method

    /// Constructs a URL to fetch a photo for a place, given its photo reference and a maximum width.
    /// - Parameters:
    ///   - photoReference: The reference string for the photo, obtained from place details.
    ///   - maxWidth: The maximum desired width of the photo in pixels.
    /// - Returns: An optional `URL` for the photo. Returns `nil` if a URL cannot be constructed.
    func photoURL(for photoReference: String, maxWidth: Int) -> URL? // Existing method
    
    /// Searches for nearby places using the newer Google Places API (e.g., Places API New).
    /// - Parameters:
    ///   - coordinate: The `CLLocationCoordinate2D` representing the center point for the search.
    ///   - radius: The radius in meters within which to search for places.
    /// - Returns: An array of `GooglePlacesAPIService.NearbyPlaceInternal` objects representing places found nearby.
    ///   `NearbyPlaceInternal` is likely an internal type specific to the implementing service,
    ///   which might be mapped to `PlaceResult` or a similar app-specific model later.
    /// - Throws: An error if the nearby search fails or the API returns an error.
    func searchNearbyPlacesNewAPI(coordinate: CLLocationCoordinate2D, radius: Double) async throws -> [GooglePlacesAPIService.NearbyPlaceInternal]
}