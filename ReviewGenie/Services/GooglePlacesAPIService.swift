import Foundation
import CoreLocation

/// Errors that can occur when interacting with the Google Places API.
enum PlacesAPIError: Error {
    case invalidURL // Indicates that the URL for the API request could not be formed.
    case networkError(Error) // Encapsulates an underlying network error (e.g., no internet connection).
    case decodingError(Error) // Encapsulates an error that occurred during JSON decoding of the API response.
    case apiError(String) // For errors reported by the API itself (e.g., ZERO_RESULTS, REQUEST_DENIED, INVALID_REQUEST).
    case noResultFound // Specifically indicates that the API returned a successful response but no results matched the query.
}

/// A service class for interacting with the Google Places API.
/// It provides methods for searching places, fetching place details, and constructing photo URLs.
class GooglePlacesAPIService: GooglePlacesServiceProtocol {
    private static let apiKey: String = {
       guard
        let path = Bundle.main.path(forResource: "APIKeys-Info", ofType: "plist"),
        let dict = NSDictionary(contentsOfFile: path),
        let key  = dict["GOOGLE_MAPS_PLACES_API_KEY"] as? String,
        !key.isEmpty
        else {
        fatalError("Missing GOOGLE_MAPS_PLACES_API_KEY in APIKeys-Info.plist")
        }
        return key
    }()

    private let session: URLSession

    /// Initializes the service with a URLSession.
    /// - Parameter session: The URLSession to use for network requests. Defaults to `URLSession.shared`.
    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Searches for places based on a query string using the Google Places Autocomplete (New) API.
    /// - Parameter query: The search string (e.g., "restaurants in New York").
    /// - Returns: An array of `PlaceResult` objects matching the query.
    /// - Throws: `PlacesAPIError` if an error occurs.
    func searchPlaces(query: String) async throws -> [PlaceResult] {
        let key = Self.apiKey
        // print the key for debugging
        print("ℹ️ [GooglePlacesAPIService] Using Google API Key: \(key)")
        
        guard let url = URL(string: "https://places.googleapis.com/v1/places:autocomplete") else {
            throw PlacesAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        // Note: Autocomplete (New) API doesn't use a FieldMask in the request for suggestions.
        // The fields returned in suggestions are fixed for placePrediction.

        let requestBody = AutocompleteRequest(input: query)
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            // This error occurs if the AutocompleteRequest struct cannot be encoded to JSON.
            throw PlacesAPIError.decodingError(error) // Consider a specific error type like .encodingError(error)
        }

        var data: Data? = nil // Initialize as optional var to store data for potential error logging.

        do {
            // Perform the network request.
            let (responseData, urlResponse) = try await session.data(for: request)
            data = responseData // Assign to the broader scoped optional var for logging in catch block.

            // Check for HTTP errors.
            if let httpResponse = urlResponse as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                let responseBodyString = String(data: responseData, encoding: .utf8) ?? "No response body"
                print("Error: Google Autocomplete (New) API HTTP Error: \(httpResponse.statusCode). Body: \(responseBodyString)")
                throw PlacesAPIError.apiError("HTTP Error \(httpResponse.statusCode): \(responseBodyString)")
            }
            
            let decoder = JSONDecoder()
            // Decode the JSON response using the non-optional 'responseData'.
            let autocompleteResponse = try decoder.decode(AutocompleteResponse.self, from: responseData)

            // Map the API response suggestions to PlaceResult objects.
            return autocompleteResponse.suggestions?.compactMap { suggestion -> PlaceResult? in
                guard let prediction = suggestion.placePrediction,
                      let placeId = prediction.placeId, // placeId is crucial for fetching details later.
                      let mainText = prediction.structuredFormat?.mainText?.text else {
                    return nil // Skip if essential information is missing.
                }
                
                // Autocomplete provides limited information.
                // Latitude, longitude, photoReference, reviews, and overallRating are not available here.
                // These details must be fetched using fetchPlaceDetails.
                return PlaceResult(
                    id: placeId,
                    name: mainText,
                    address: prediction.structuredFormat?.secondaryText?.text ?? "", // Secondary text often contains address components.
                    latitude: 0.0, // Placeholder: Not available from Autocomplete prediction directly.
                    longitude: 0.0, // Placeholder: Not available from Autocomplete prediction directly.
                    photoReference: nil, // Placeholder: Not available from Autocomplete prediction directly.
                    fetchedReviews: [],
                    overallRating: nil // Placeholder: Not available from Autocomplete prediction directly.
                )
            } ?? [] // Return an empty array if suggestions are nil or no valid suggestions are found.
        } catch let decodingError as DecodingError {
            // Log the raw JSON if decoding fails, which helps in debugging the Codable structs.
            if let validData = data, let jsonString = String(data: validData, encoding: .utf8) {
                 print("ℹ️ [GooglePlacesAPIService] Raw JSON causing Autocomplete decoding error: \(jsonString)")
            }
            print("Autocomplete Decoding Error: \(decodingError)")
            throw PlacesAPIError.decodingError(decodingError)
        } catch let apiError as PlacesAPIError {
            throw apiError // Re-throw known API errors (e.g., the HTTP error thrown above).
        } catch {
            // Catch-all for other errors, typically network-related.
            print("Autocomplete Network Error or other: \(error)")
            throw PlacesAPIError.networkError(error)
        }
    }

    /// Fetches detailed information for a specific place using its Place ID with the Google Places (New) API.
    /// - Parameter placeID: The unique identifier for the place.
    /// - Returns: A `PlaceResult` object containing detailed information about the place.
    /// - Throws: `PlacesAPIError` if an error occurs.
    func fetchPlaceDetails(placeID: String) async throws -> PlaceResult {
        let key = Self.apiKey

        guard let url = URL(string: "https://places.googleapis.com/v1/places/" + placeID) else {
            throw PlacesAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        
        // Specify the fields to be returned by the API using a FieldMask.
        // This helps in optimizing the API call and reducing costs.
        let fieldMask = "id,displayName,formattedAddress,location,rating,photos,reviews,types"
        request.setValue(fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")

        do {
            let (data, response) = try await session.data(for: request)

            // Log the raw JSON response for debugging purposes.
            if let jsonString = String(data: data, encoding: .utf8) {
                print("ℹ️ [GooglePlacesAPIService] Raw JSON response from Place Details (New): \(jsonString)")
            }

            // Check for HTTP errors.
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                let responseBodyString = String(data: data, encoding: .utf8) ?? "No response body"
                print("Error: Google Place Details (New) API HTTP Error: \(httpResponse.statusCode). Body: \(responseBodyString)")
                throw PlacesAPIError.apiError("HTTP Error \(httpResponse.statusCode): \(responseBodyString)") 
            }

            let decoder = JSONDecoder()
            let detailsResponse = try decoder.decode(PlaceDetailsNewResponse.self, from: data)

            // Map API reviews to FetchedReview objects.
            let fetchedReviews = detailsResponse.reviews?.compactMap { apiReviewNew -> FetchedReview? in
                guard let text = apiReviewNew.text?.text,
                      let authorName = apiReviewNew.authorAttribution?.displayName,
                      let rating = apiReviewNew.rating else {
                    return nil // Skip review if essential information is missing.
                }
                return FetchedReview(
                    authorName: authorName,
                    rating: rating,
                    text: text,
                    relativeTimeDescription: apiReviewNew.relativePublishTimeDescription ?? ""
                )
            } ?? []

            // Extract the full photo name (resource name) for the first photo, if available.
            // This name is used to construct the photo URL.
            let fullPhotoName: String? = detailsResponse.photos?.first?.name

            // Construct the PlaceResult object with the fetched details.
            return PlaceResult(
                id: detailsResponse.id ?? placeID, // Fallback to input placeID if not in response.
                name: detailsResponse.displayName?.text ?? "Name not available",
                address: detailsResponse.formattedAddress ?? "Address not available",
                latitude: detailsResponse.location?.latitude ?? 0.0,
                longitude: detailsResponse.location?.longitude ?? 0.0,
                photoReference: fullPhotoName, // This is the 'name' field from the PhotoNew struct.
                fetchedReviews: fetchedReviews,
                overallRating: detailsResponse.rating,
                types: detailsResponse.types
            )
        } catch let decodingError as DecodingError {
            print("Decoding error in fetchPlaceDetails: \(decodingError)")
            throw PlacesAPIError.decodingError(decodingError)
        } catch let apiError as PlacesAPIError {
            throw apiError // Re-throw known API errors.
        } catch {
            print("Network error or other issue in fetchPlaceDetails: \(error)")
            // Ensure we always throw a PlacesAPIError.
            throw PlacesAPIError.networkError(error)
        }
    }

    /// Constructs a URL to fetch a place's photo using the Google Places Photo (New) API.
    /// - Parameters:
    ///   - photoReference: The full photo resource name (e.g., "places/PLACE_ID/photos/PHOTO_RESOURCE_NAME").
    ///   - maxWidth: The maximum desired width of the photo in pixels. Defaults to 400.
    /// - Returns: A `URL` for the photo, or `nil` if the URL cannot be constructed (e.g., invalid API key or photoReference).
    func photoURL(for photoReference: String, maxWidth: Int = 400) -> URL? {
        // The photoReference is the full 'name' field from the PhotoNew struct (e.g., "places/ChIJN1t_tDeuEmsRUsoyG83frY4/photos/AUacShih1ZEQ9h0Legw9709KVYdZ5Ho7escm286h22olzmbr_s8Grc2XyqfnTPf_1Lhfp8uLruS2YEXo2Xy_L00tqAYaOKXTQ2ySPSf_sAA2TjvstTRj2akYoqXlGqXyXq_0").
        // The URL for Place Photo (New) API is: https://places.googleapis.com/v1/PHOTO_NAME/media?maxWidthPx=WIDTH&key=API_KEY
        var components = URLComponents(string: "https://places.googleapis.com/v1/" + photoReference + "/media")
        components?.queryItems = [
            URLQueryItem(name: "maxWidthPx", value: String(maxWidth)),
            // Optionally, add maxHeightPx if needed:
            // URLQueryItem(name: "maxHeightPx", value: String(maxHeight)), 
            URLQueryItem(name: "key", value: Self.apiKey) // API key is passed as a query parameter for photo requests.
        ]
        return components?.url
    }

    // MARK: - Legacy Codable Structs (Potentially for an older API version, review for removal if not used)
    // These structs (GooglePlaceAPIEntry, Geometry, Location, PhotoInfo) seem to correspond to the older
    // Google Places API (e.g., Text Search, Nearby Search - legacy).
    // If the application exclusively uses the "Places API (New)" (v1 endpoints), these might be obsolete.

    /// Represents an entry from a legacy Google Places API response (e.g., Text Search, Nearby Search - legacy).
    struct GooglePlaceAPIEntry: Codable {
        let placeId: String
        let name: String
        let formattedAddress: String?
        let vicinity: String? // Often used in Nearby Search (legacy) responses.
        let geometry: Geometry?
        let rating: Double?
        let photos: [PhotoInfo]?
        let types: [String]? // Useful for filtering results.

        enum CodingKeys: String, CodingKey {
            case placeId = "place_id"
            case name
            case formattedAddress = "formatted_address"
            case vicinity, geometry, rating, photos, types
        }
    }

    /// Geometric information about a place (legacy).
    struct Geometry: Codable {
        let location: Location
    }

    /// Latitude and longitude coordinates (legacy).
    struct Location: Codable {
        let lat: Double
        let lng: Double
    }

    /// Information about a photo (legacy), primarily the photo reference.
    struct PhotoInfo: Codable {
        let photoReference: String // This is the shorter photo_reference, not the full resource name.
        // Add height, width if needed from the legacy API response.
        enum CodingKeys: String, CodingKey {
            case photoReference = "photo_reference"
        }
    }
    
    // MARK: - Codable Structs for Place Details (New) API Response (/v1/places/{placeId})

    /// Represents the root response from the Google Places Details (New) API.
    struct PlaceDetailsNewResponse: Codable {
        let id: String? // The unique Place ID.
        let displayName: DisplayNameNew?
        let formattedAddress: String?
        let location: LocationNew? // Geographic coordinates.
        let rating: Double? // Overall rating of the place.
        let photos: [PhotoNew]? // Array of photos associated with the place.
        let reviews: [ReviewNew]? // Array of reviews for the place.
        let types: [String]? // Array of types associated with the place (e.g., "restaurant", "cafe").
    }

    /// Represents a localized display name for a place.
    struct DisplayNameNew: Codable {
        let text: String? // The display name text.
        let languageCode: String? // BCP-47 language code.
    }

    /// Represents geographic coordinates (latitude and longitude).
    struct LocationNew: Codable {
        let latitude: Double?
        let longitude: Double?
    }

    /// Represents a photo associated with a place.
    struct PhotoNew: Codable {
        let name: String? // The full resource name of the photo (e.g., "places/PLACE_ID/photos/PHOTO_ID"). Used to fetch the photo.
        let widthPx: Int? // Maximum width of the photo in pixels.
        let heightPx: Int? // Maximum height of the photo in pixels.
        let authorAttributions: [AuthorAttributionNew]? // Attributions for the photo.
    }

    /// Represents a review for a place.
    struct ReviewNew: Codable {
        let relativePublishTimeDescription: String? // Human-readable relative time of publishing (e.g., "a month ago").
        let rating: Int? // Rating given in the review (typically 1-5).
        let text: ReviewTextNew? // The text content of the review.
        let authorAttribution: AuthorAttributionNew? // Information about the author of the review.
    }

    /// Represents the text content of a review, including language.
    struct ReviewTextNew: Codable {
        let text: String? // The review text.
        let languageCode: String? // BCP-47 language code.
    }

    /// Represents attribution information for content (e.g., photos, reviews).
    struct AuthorAttributionNew: Codable {
        let displayName: String? // Name of the author.
        let uri: String? // URI to the author's profile.
        let photoUri: String? // URI to the author's photo.
    }
    // END: Codable Structs for Place Details (New)

    // MARK: - Codable Structs for Autocomplete (New) API (/v1/places:autocomplete)

    /// Represents the request body for the Google Places Autocomplete (New) API.
    struct AutocompleteRequest: Codable {
        let input: String // The text query to search for.
        // Optional parameters like locationBias, locationRestriction, includedPrimaryTypes, etc., can be added here if needed.
        // Example:
        // let locationBias: LocationBias?
        // let includedPrimaryTypes: [String]?
    }

    /// Represents the root response from the Google Places Autocomplete (New) API.
    struct AutocompleteResponse: Codable {
        let suggestions: [AutocompleteSuggestion]? // List of autocomplete suggestions.
    }

    /// Represents a single autocomplete suggestion.
    struct AutocompleteSuggestion: Codable {
        let placePrediction: PlacePrediction? // Detailed prediction for a place.
        // Could also include 'queryPrediction' if handling those types of suggestions.
    }

    /// Represents a predicted place from an autocomplete suggestion.
    struct PlacePrediction: Codable {
        let place: String? // Resource name of the place, format: "places/PLACE_ID".
        let placeId: String? // The unique Place ID.
        let text: PlaceText? // The full text of the prediction.
        let structuredFormat: StructuredFormat? // Structured formatting of the prediction text.
        let types: [String]? // Types associated with the predicted place.
    }

    /// Represents text with matching segments, used in autocomplete predictions.
    struct PlaceText: Codable {
        let text: String? // The text content.
        let matches: [MatchSegment]? // Segments of the text that match the input query.
    }

    /// Represents a segment of text that matches the input query.
    struct MatchSegment: Codable {
        let endOffset: Int? // The ending offset of the match in the text.
        // 'beginOffset' might also be available depending on API version/configuration.
    }

    /// Represents structured formatting for main and secondary text of a prediction.
    struct StructuredFormat: Codable {
        let mainText: PlaceText? // The main text of the prediction (e.g., place name).
        let secondaryText: PlaceText? // The secondary text (e.g., address or locality).
    }
    // END: Codable Structs for Autocomplete (New)

    // Note: Old searchNearbyPlaces method using the legacy API (e.g., Google Places SDK for iOS or different endpoint) will be removed or has been removed.
    // This service now focuses on the "Places API (New)" v1 HTTP endpoints.

    // MARK: - Places API (New) - Nearby Search Structs & Method (/v1/places:searchNearby)
    // These structs are specifically for the HTTP POST request to /v1/places:searchNearby.

    /// Internal request body structure for the Nearby Search (New) API.
    struct NearbySearchRequestInternal: Codable {
        let includedTypes: [String]? // Specifies the types of places to search for. Empty or nil means all types.
        let maxResultCount: Int // Maximum number of results to return.
        let rankPreference: String? // How to rank results (e.g., "DISTANCE", "POPULARITY").
        let locationRestriction: LocationRestrictionInternal // Defines the geographic area to search within.
    }

    /// Defines a location restriction for Nearby Search, typically a circle.
    struct LocationRestrictionInternal: Codable {
        let circle: CircleRestrictionInternal
    }

    /// Defines a circular area for location restriction.
    struct CircleRestrictionInternal: Codable {
        let center: CenterLocationInternal // The center of the circle.
        let radius: Double // The radius of the circle in meters.
    }

    /// Defines the center point (latitude, longitude) for a circular restriction.
    struct CenterLocationInternal: Codable {
        let latitude: Double
        let longitude: Double
    }

    /// Internal response structure for the Nearby Search (New) API.
    /// Made public to allow decoding by callers if they need the raw structure.
    public struct NearbySearchResponseInternal: Codable {
        public let places: [NearbyPlaceInternal]? // List of nearby places found.
    }

    /// Represents a place found by the Nearby Search (New) API.
    /// Public so it can be returned and used by callers. Conforms to Identifiable and Hashable for UI purposes.
    public struct NearbyPlaceInternal: Codable, Identifiable, Hashable {
        public let displayName: DisplayNameInternal?
        public let formattedAddress: String?
        public let id: String? // This is the Google Place ID (resource name format: "places/PLACE_ID").
        public let types: [String]?
        
        /// Convenience accessor to get the Place ID.
        public var placeID: String? { return id }

        /// Represents the display name of a nearby place.
        public struct DisplayNameInternal: Codable, Hashable {
            public let text: String?
            public let languageCode: String?
        }
    }

    /// Searches for nearby places using the Google Places API (New) - Nearby Search endpoint via HTTP POST.
    /// - Parameters:
    ///   - coordinate: The `CLLocationCoordinate2D` representing the center of the search area.
    ///   - radius: The radius (in meters) of the search area. Defaults to 75.0 meters.
    /// - Returns: An array of `NearbyPlaceInternal` objects.
    /// - Throws: `PlacesAPIError` if an error occurs.
    public func searchNearbyPlacesNewAPI(coordinate: CLLocationCoordinate2D, radius: Double = 75.0) async throws -> [NearbyPlaceInternal] {
        let urlString = "https://places.googleapis.com/v1/places:searchNearby"
        guard let url = URL(string: urlString) else {
            print("Error: Could not create URL for Google Places Nearby Search (New) API.")
            throw PlacesAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        // Request specific fields using FieldMask. `places.id` is crucial for identifying places.
        // Other fields like `places.displayName`, `places.formattedAddress`, `places.types` are also requested.
        request.setValue("places.id,places.displayName,places.formattedAddress,places.types", forHTTPHeaderField: "X-Goog-FieldMask")

        let requestBody = NearbySearchRequestInternal(
            includedTypes: [] , // Empty array or nil means search for all types of places.
            maxResultCount: 10, // Limit the number of results. Max is 20 for this API.
            rankPreference: "DISTANCE", // Rank results by distance from the specified location.
            locationRestriction: LocationRestrictionInternal(
                circle: CircleRestrictionInternal(
                    center: CenterLocationInternal(latitude: coordinate.latitude, longitude: coordinate.longitude),
                    radius: radius // Search radius in meters.
                )
            )
        )

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            print("Error: Failed to encode Nearby Search (New) request body: \(error)")
            // This error occurs if the NearbySearchRequestInternal struct cannot be encoded to JSON.
            throw PlacesAPIError.decodingError(error) // Consider a specific error type like .encodingError(error)
        }
        
        do {
            let (data, response) = try await session.data(for: request)

            // Log the raw JSON response for debugging.
            if let jsonString = String(data: data, encoding: .utf8) {
                print("ℹ️ [GooglePlacesAPIService] Raw JSON response from Nearby Search (New): \(jsonString)")
            }

            // Check for HTTP errors.
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                let responseBodyString = String(data: data, encoding: .utf8) ?? "No response body"
                print("Error: Google Places Nearby Search (New) API HTTP Error: \(httpResponse.statusCode). Body: \(responseBodyString)")
                // Provide the full response body in the error for better diagnostics.
                throw PlacesAPIError.apiError("HTTP Error \(httpResponse.statusCode): \(responseBodyString)")
            }
            
            let decoder = JSONDecoder()
            let nearbySearchResponse = try decoder.decode(NearbySearchResponseInternal.self, from: data)

            // Return the array of places, or an empty array if 'places' is nil or no places are found.
            return nearbySearchResponse.places ?? []
            
        } catch let decodingError as DecodingError {
            print("Error: Failed to decode Nearby Search (New) response: \(String(describing: decodingError))")
            throw PlacesAPIError.decodingError(decodingError)
        } catch let apiError as PlacesAPIError {
            throw apiError // Re-throw known API errors.
        } catch {
            print("Error: Network or other error during Nearby Search (New) request: \(error.localizedDescription)")
            throw PlacesAPIError.networkError(error)
        }
    }
} 