import Foundation
import CoreLocation // For CLLocationCoordinate2D, used for location hints.
import Photos // For PHAsset, if dealing directly with PhotoKit assets (though current input is ProcessedPhoto).
import FirebaseVertexAI // For interacting with Google's Gemini AI models via Firebase.
import Firebase // For FirebaseApp initialization and core services.
import UniformTypeIdentifiers // For accurately determining MIME types from file extensions.

/// Errors that can occur during the Gemini Vision service operations.
enum GeminiVisionServiceError: Error {
    case modelNotInitialized // The Gemini model failed to initialize.
    case noAssetsProvided // No photos were provided for analysis.
    case imageDataFetchingFailed(String) // Failed to load image data from the provided assets.
    case geminiRequestFailed(String) // The request to the Gemini API failed.
    case responseParsingFailed(String) // Failed to parse the JSON response from Gemini.
    case noPlaceIdentified // Gemini did not identify a place.
    case nearbySearchFailed(String) // An error occurred during a GMSPlacesClient (or similar) nearby search.
}

/// Represents the result of a location identification attempt using Gemini Vision.
public struct GeminiVisionIdentification {
    /// The place details identified by Gemini, if any.
    let geminiPickedPlace: GeminiVisionService.IdentifiedPlaceDetails?
    /// The list of nearby places provided as context to Gemini, passed through for reference.
    let nearbyCandidates: [GooglePlacesAPIService.NearbyPlaceInternal]?
}

/// A service responsible for identifying locations from images using the Gemini multimodal model.
struct GeminiVisionService {
    /// Defines the structure for the JSON response expected from Gemini when identifying a place.
    struct IdentifiedPlaceDetails: Codable, Hashable {
        let name: String? // The identified name of the place.
        let address: String? // The full street address of the place.
        let placeID: String? // The Google Place ID, if Gemini can determine it.
        let latitude: Double? // The latitude of the identified place.
        let longitude: Double? // The longitude of the identified place.
        let confidence: Double? // Gemini's confidence in the identification (0.0 to 1.0).
        let reasoning: String?  // Gemini's explanation for the identification.

        enum CodingKeys: String, CodingKey {
            case name
            case address
            case placeID = "place_id" // Maps to "place_id" in the JSON.
            case latitude
            case longitude
            case confidence
            case reasoning
        }
    }

    /// The generative AI model instance used for vision tasks.
    private var generativeModel: GenerativeModel?

    /// Initializes the GeminiVisionService.
    /// This involves setting up the specific Gemini model to be used and ensuring Firebase is configured.
    init() {
        // Model selection: "gemini-2.0-flash" is chosen for its multimodal capabilities and performance.
        // This can be updated if newer or more suitable models become available.
        let modelName = "gemini-2.0-flash"

        // Critical: Firebase must be configured (FirebaseApp.configure()) before VertexAI services can be used.
        // This check ensures the app doesn't crash if Firebase isn't ready.
        // Ideally, FirebaseApp.configure() is called once at app launch (e.g., in AppDelegate).
        if FirebaseApp.app() == nil {
            print("Error: FirebaseApp not configured. Make sure FirebaseApp.configure() is called before initializing Gemini services.")
            // Service will be non-functional if Firebase isn't configured.
            self.generativeModel = nil
            return
        }
        
        // Initialize the GenerativeModel from Firebase Vertex AI.
        self.generativeModel = VertexAI.vertexAI().generativeModel(modelName: modelName)
        
        if self.generativeModel == nil {
            print("Error: Failed to initialize GeminiVisionService model (\(modelName)). Check Firebase setup, Vertex AI API enablement, and model availability in your Google Cloud project region.")
        } else {
            print("✅ [GeminiVisionService] Initialized successfully with model: \(modelName)")
        }
    }

    /// Identifies a location from a set of processed photos, optionally using a coordinate hint and nearby place context.
    ///
    /// - Parameters:
    ///   - photos: An array of `ProcessedPhoto` objects containing image data and metadata.
    ///   - averageCoordinateHint: An optional `CLLocationCoordinate2D` providing a geographical hint for the images' location.
    ///   - nearbyContextPlaces: An optional array of `GooglePlacesAPIService.NearbyPlaceInternal` objects,
    ///                          representing places already known to be near the `averageCoordinateHint`.
    /// - Returns: A `GeminiVisionIdentification` struct containing the identified place details and the context candidates.
    /// - Throws: `GeminiVisionServiceError` if any part of the process fails.
    func identifyLocationFromImages(
        photos: [ProcessedPhoto],
        averageCoordinateHint: CLLocationCoordinate2D?,
        nearbyContextPlaces: [GooglePlacesAPIService.NearbyPlaceInternal]?
    ) async throws -> GeminiVisionIdentification {

        guard let model = generativeModel else {
            // Ensure the model was initialized successfully.
            throw GeminiVisionServiceError.modelNotInitialized
        }

        guard !photos.isEmpty else {
            // Must have at least one photo to analyze.
            throw GeminiVisionServiceError.noAssetsProvided
        }

        var imageDatas: [Data] = []
        var imageMimeTypes: [String] = []
        let maxImagesToProcess = 3 // Limit the number of images sent to Gemini to manage request size and cost.

        // Prepare image data and their MIME types for the Gemini request.
        for photo in photos.prefix(maxImagesToProcess) {
            if let imageData = photo.loadOptimizedImageData() {
                imageDatas.append(imageData)
                // Default MIME type, will be overridden if a more specific one is found.
                var mimeType = "application/octet-stream" // A generic byte stream.
                // Attempt to determine a more accurate MIME type from the file extension.
                if let fileExtension = photo.optimizedFileName.components(separatedBy: ".").last?.lowercased(),
                   let utType = UTType(filenameExtension: fileExtension), // Get UTType from extension.
                   let preferredMimeType = utType.preferredMIMEType { // Get preferred MIME type from UTType.
                    mimeType = preferredMimeType
                }
                imageMimeTypes.append(mimeType)
            } else {
                print("  ⚠️ Could not load data for processed photo: \(photo.optimizedFileName). Skipping this image.")
            }
        }

        guard !imageDatas.isEmpty else {
            // If no image data could be loaded, cannot proceed.
            print("Error: Could not load image data for any of the provided assets.")
            throw GeminiVisionServiceError.imageDataFetchingFailed("No image data could be loaded from the provided assets.")
        }

        // Construct the prompt for Gemini.
        var promptComponents: [String] = [
            "Analyze the provided image(s) to identify the specific name and location of the place depicted (e.g., restaurant name, park name, specific shop, landmark).",
            "Your goal is to determine the single most likely place shown in the images.",
            "Leverage Google Search grounding if necessary to verify and refine your identification." // Instructs Gemini to use its search capabilities.
        ]
        
        // Add location context to the prompt if available.
        if let coordinateHint = averageCoordinateHint {
            var locationContextPrompt = "The photo(s) were taken at or very near these coordinates: (latitude: \(coordinateHint.latitude), longitude: \(coordinateHint.longitude))."

            // If nearby places are provided, include them in the prompt for Gemini to consider.
            if let foundCustomPlaces = nearbyContextPlaces, !foundCustomPlaces.isEmpty {
                let placeListString = foundCustomPlaces.prefix(5).compactMap { place -> String? in // Limit to top 5 nearby places.
                    guard let name = place.displayName?.text else { return nil }
                    let address = place.formattedAddress ?? "Address N/A"
                    let placeId = place.id ?? "N/A"
                    return "- Name: \"\(name)\", Address: \"\(address)\", Place ID: \"\(placeId)\""
                }.joined(separator: "\n")
                
                locationContextPrompt += "\n\nA search for establishments within a 75-meter radius of these coordinates returned the following list (ranked by distance):\n" + placeListString
                locationContextPrompt += "\n\nYour primary task is to determine which ONE of these listed establishments is most likely depicted in the image(s), considering the visual evidence. "
                locationContextPrompt += "If you select a place from this list, use its exact Name, Address, and Place ID in your JSON response. "
                locationContextPrompt += "If you are highly confident that NONE of the places in this list match the visual evidence in the image(s), clearly state this and your reasoning, and then identify the most likely place based on visual cues and general search (still ensuring it's very close to the given coordinates, within 50 meters). Otherwise, prioritize selecting from the provided list."
            } else {
                // If no nearby places list, instruct Gemini to focus on visual evidence within a radius.
                locationContextPrompt += "\nPrioritize visual evidence from the image(s) to identify the specific place name AT these coordinates or within a 50-meter radius. The identified place MUST be within this 50-meter radius."
            }
            promptComponents.append(locationContextPrompt)

        } else { 
            // If no coordinate hint, rely solely on visual cues.
            promptComponents.append("No specific coordinate hint is available for these images. Rely solely on visual cues from the image(s) to identify the most prominent and specific place depicted.")
        }

        // Instruct Gemini on the desired JSON output format.
        promptComponents.append("Provide your single best identification as a JSON object with the following keys: \"name\" (string, the identified place name), \"address\" (string, full street address if found), \"place_id\" (string, Google Place ID if identifiable), \"latitude\" (number), \"longitude\" (number), \"confidence\" (number, your confidence from 0.0 to 1.0 in your identification), and \"reasoning\" (string, a brief explanation of how you identified the place, including which visual cues or list items were used).")
        promptComponents.append("If you cannot confidently identify a specific place, return null for name and address, and explain why in the reasoning.")

        let fullPrompt = promptComponents.joined(separator: " ")
        print("ℹ️ [GeminiVisionService] Prompt for Gemini: \(fullPrompt)")

        // Assemble the request parts: the text prompt and the image data.
        var requestParts: [any Part] = [TextPart(fullPrompt)]
        for (index, imageData) in imageDatas.enumerated() {
            let mimeType = imageMimeTypes[index]
            requestParts.append(InlineDataPart(data: imageData, mimeType: mimeType))
        }
        let modelInput = ModelContent(role: "user", parts: requestParts) // Package parts into ModelContent.

        var cleanedTextContent: String? = nil // To store the cleaned JSON string for debugging.
        do {
            // Send the request to the Gemini model.
            let response = try await model.generateContent([modelInput])
            
            guard let textContent = response.text else {
                // The response should contain a text part with the JSON.
                throw GeminiVisionServiceError.responseParsingFailed("Gemini response did not contain text content.")
            }
            
            // Clean the response text: Gemini might wrap JSON in markdown (```json ... ```) or include other text.
            // This attempts to extract just the JSON object.
            if let jsonStartIndex = textContent.firstIndex(of: "{"),
               let jsonEndIndex = textContent.lastIndex(of: "}") {
                // Basic extraction of content between the first '{' and last '}'.
                cleanedTextContent = String(textContent[jsonStartIndex...jsonEndIndex])
            } else {
                // Fallback cleaning for markdown fences if simple extraction fails.
                cleanedTextContent = textContent.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if cleanedTextContent?.hasPrefix("```json") ?? false { cleanedTextContent = String(cleanedTextContent!.dropFirst(7)) }
                if cleanedTextContent?.hasSuffix("```") ?? false { cleanedTextContent = String(cleanedTextContent!.dropLast(3)) }
                cleanedTextContent = cleanedTextContent?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            }

            guard let jsonData = cleanedTextContent?.data(using: .utf8) else {
                // If the cleaned text cannot be converted to Data, parsing will fail.
                throw GeminiVisionServiceError.responseParsingFailed("Could not convert cleaned JSON response to Data. Cleaned text: \(cleanedTextContent ?? "NIL")")
            }
            
            // Decode the JSON data into the IdentifiedPlaceDetails struct.
            let decodedResponse = try JSONDecoder().decode(IdentifiedPlaceDetails.self, from: jsonData)
            print("✅ [GeminiVisionService] Successfully parsed Gemini response.")
            
            // Return the identification result.
            return GeminiVisionIdentification(
                geminiPickedPlace: decodedResponse,
                nearbyCandidates: nearbyContextPlaces // Pass through the context candidates for UI or further processing.
            )

        } catch let error as GenerateContentError { // Specific error from Gemini content generation.
            print("Error: Gemini content generation failed: \(error.localizedDescription)")
            throw GeminiVisionServiceError.geminiRequestFailed(error.localizedDescription)
        } catch let error as DecodingError { // Error during JSON decoding.
            print("Error: Failed to decode Gemini JSON response: \(error.localizedDescription). Cleaned text: \(cleanedTextContent ?? "NIL")")
            throw GeminiVisionServiceError.responseParsingFailed("Failed to decode JSON: \(error.localizedDescription)")
        } catch { // Catch-all for other unexpected errors.
            print("Error: An unexpected error occurred during Gemini request/processing: \(error.localizedDescription)")
            throw GeminiVisionServiceError.geminiRequestFailed("Unexpected error: \(error.localizedDescription)")
        }
    }
}