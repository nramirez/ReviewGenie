import Foundation
import FirebaseVertexAI
import SwiftUI // Supports working with UIImage/NSImage types, which are typically converted to Data for multimodal model input.
import CoreLocation
// No longer explicitly importing GoogleGenerativeAI, relying on FirebaseVertexAI exports

// Codable struct for the expected JSON response from Gemini
struct GeminiStructuredReviewResponse: Codable {
    let reviews: [String]
}

enum GeminiServiceError: Error {
    case modelInitializationFailed
    case responseParsingFailed
    case generationFailed(String)
    case imageConversionFailed
    case featureNotAvailable(String)
    case noReviewDraftsGenerated
}

class GeminiFirebaseService: GeminiServiceProtocol {

    private var generativeModel: GenerativeModel?

    init() {
        // Ensure your GoogleCloud project linked to Firebase has Vertex AI API enabled and billing set up.
        // Model names for Gemini 1.5: "gemini-1.5-flash-latest", "gemini-1.5-pro-latest"
        // For text-only, an older model like "gemini-pro" might also work if 1.5 isn't essential yet.
        // Specifies the generative model. Currently using "gemini-2.0-flash", a preview model.
        let modelName = "gemini-2.0-flash"
        
        // Define the response schema using the fluent style from Firebase documentation
        // let reviewSchema = Schema.object(
        //     properties: ["reviews": Schema.array(items: .string())]
        // )

        // let generationConfiguration = GenerationConfig(
        //     responseMIMEType: "application/json",
        //     responseSchema: reviewSchema
        // )
        
        // Initialize the model WITHOUT a specific generationConfig (which would include responseSchema).
        // This approach offers greater flexibility for multimodal inputs, relying on prompt engineering
        // for JSON output formatting rather than strict API-level schema enforcement.
        self.generativeModel = VertexAI.vertexAI().generativeModel(modelName: modelName)
        
        if self.generativeModel == nil {
            print("Error: Failed to initialize Gemini model. Ensure Firebase is configured correctly and Vertex AI is set up.")
        }
    }

    func generateReviewDrafts(
        placeName: String,
        address: String,
        overallRating: Double,
        foodRating: Double,
        serviceRating: Double,
        atmosphereRating: Double,
        photoData: [Data]?,
        existingReviews: [FetchedReview]?,
        userKeyNotes: String?,
        numberOfDraftsToRequest: Int
    ) async throws -> [String] {
        
        guard let model = generativeModel else {
            throw GeminiServiceError.modelInitializationFailed
        }

        var promptString = "You are a helpful assistant that writes concise and engaging Google Maps review drafts.\n"
        promptString += "Write \(numberOfDraftsToRequest) distinct review drafts for a visit to '\(placeName)' at '\(address)'.\n"
        promptString += "My overall experience was \(overallRating) out of 5 stars.\n"
        if foodRating > 0 { promptString += "Food: \(foodRating)/5. " }
        if serviceRating > 0 { promptString += "Service: \(serviceRating)/5. " }
        if atmosphereRating > 0 { promptString += "Atmosphere: \(atmosphereRating)/5.\n" }
        
        if let keyNotes = userKeyNotes, !keyNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            promptString += "\nIncorporate these key notes from the user: \(keyNotes)\n"
        }
        
        if let photos = photoData, !photos.isEmpty {
            promptString += "\nAdditionally, consider the following attached photos when writing the review. Describe relevant visual details or anything noteworthy from them:\n"
            // The actual image data will be added as separate parts in the request.
        }
        
        // Conditionally add existing reviews to the prompt
        if let reviews = existingReviews, !reviews.isEmpty {
            promptString += "\nHere are some existing reviews for context (try to be original and not repeat these too much):\n"
            for (index, review) in reviews.prefix(3).enumerated() { 
                promptString += "Existing Review \(index + 1): '\(review.text.prefix(200))...' (Rated \(review.rating)/5)\n"
            }
        }
        // Correctly escaped JSON example in the prompt string
        promptString += "\nIMPORTANT: Respond with a JSON object structured exactly as: {\"reviews\": [\"Review draft 1\", \"Review draft 2\", \"Review draft 3\"]}. Each string in the array must be one complete review draft."
        
        print("--- Gemini Prompt (for structured output) ---")
        print(promptString)
        print("---------------------------------------------")

        do {
            var requestParts: [any Part] = []
            requestParts.append(TextPart(promptString))

            if let photos = photoData, !photos.isEmpty {
                for (index, imageData) in photos.enumerated() {
                    if let mimeType = ImageUtils.getMIMEType(for: imageData) {
                        requestParts.append(InlineDataPart(data: imageData, mimeType: mimeType))
                        print("Added image \(index + 1) to Gemini request with detected mimetype \(mimeType).")
                    } else {
                        print("Warning: Could not determine MIME type for image \(index + 1). Attempting with image/jpeg for Gemini.")
                        requestParts.append(InlineDataPart(data: imageData, mimeType: "image/jpeg"))
                    }
                }
            }

            // Wrap parts in ModelContent and then in an array for the generateContent call
            let modelInput = ModelContent(role: "user", parts: requestParts)
            let response = try await model.generateContent([modelInput])
            
            guard let textContent = response.text else {
                print("Gemini response was nil or did not contain a text part for structured output. Full response: \(response)")
                throw GeminiServiceError.responseParsingFailed
            }
            
            print("--- Gemini Raw JSON Response Text ---")
            print(textContent)
            print("-----------------------------------")

            // Clean the textContent to remove potential Markdown fences
            var cleanedTextContent = textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanedTextContent.hasPrefix("```json") {
                cleanedTextContent = String(cleanedTextContent.dropFirst(7)) // Remove "```json"
            }
            if cleanedTextContent.hasSuffix("```") {
                cleanedTextContent = String(cleanedTextContent.dropLast(3)) // Remove "```"
            }
            cleanedTextContent = cleanedTextContent.trimmingCharacters(in: .whitespacesAndNewlines) // Trim again after removal

            guard let jsonData = cleanedTextContent.data(using: String.Encoding.utf8) else {
                print("Error: Could not convert Gemini JSON response text to Data. Cleaned Text: \(cleanedTextContent)")
                throw GeminiServiceError.responseParsingFailed
            }
            
            do {
                let structuredResponse = try JSONDecoder().decode(GeminiStructuredReviewResponse.self, from: jsonData)
                
                if !structuredResponse.reviews.isEmpty {
                    if structuredResponse.reviews.count < numberOfDraftsToRequest {
                         print("Warning: Gemini returned \(structuredResponse.reviews.count) drafts in JSON, but \(numberOfDraftsToRequest) were requested.")
                    }
                    print("Successfully parsed \(structuredResponse.reviews.count) structured review(s) from Gemini.")
                    return structuredResponse.reviews
                } else {
                    print("Error: Gemini returned JSON with an empty 'reviews' array.")
                    throw GeminiServiceError.noReviewDraftsGenerated
                }
            } catch let error {
                print("Error: Failed to decode Gemini JSON response. Error: \(String(describing: error))" )
                print("Raw JSON response that failed parsing: \(textContent)")
                throw GeminiServiceError.responseParsingFailed
            }

        } catch let specificError as GenerateContentError {
            if specificError.localizedDescription.contains("InvalidArgument") || 
               specificError.localizedDescription.contains("Invalid request") { 
                 print("Gemini content generation failed with InvalidArgument-like error: \(specificError.localizedDescription)")
                 print("This often indicates an issue with the responseSchema complexity or structure (now part of model init). Review the schema and prompt.")
                 throw GeminiServiceError.generationFailed("InvalidArgument: Issue with response schema or prompt. Details: \(specificError.localizedDescription)")
            } else {
                print("Gemini content generation failed with GenerateContentError: \(specificError.localizedDescription)")
                throw GeminiServiceError.generationFailed(specificError.localizedDescription)
            }
        }
        catch {
            print("Gemini content generation failed with a general error: \(error)")
            throw GeminiServiceError.generationFailed(error.localizedDescription)
        }
    }
}