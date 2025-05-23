import Foundation

// MARK: - Claude API Key Configuration
private let claudeAPIKey: String = {
    guard
        let path = Bundle.main.path(forResource: "APIKeys-Info", ofType: "plist"),
        let dict = NSDictionary(contentsOfFile: path),
        let key = dict["CLAUDE_API_KEY"] as? String,
        !key.isEmpty
    else {
        fatalError("Missing CLAUDE_API_KEY in APIKeys-Info.plist")
    }
    return key
}()

private let claudeAPIVersion: String = {
    guard
        let path = Bundle.main.path(forResource: "APIKeys-Info", ofType: "plist"),
        let dict = NSDictionary(contentsOfFile: path),
        let version = dict["CLAUDE_API_VERSION"] as? String,
        !version.isEmpty
    else {
        fatalError("Missing CLAUDE_API_VERSION in APIKeys-Info.plist")
    }
    return version
}()

// MARK: - Codable Structs for Claude API

struct ClaudeStructuredReviewResponse: Codable {
    let reviews: [String]
}

private struct ClaudeRequestBody: Codable {
    let model: String
    let max_tokens: Int
    let messages: [ClaudeMessage]
    let system: String? // System prompt
    let tools: [ClaudeTool]?
    let tool_choice: ClaudeToolChoice? // To force a specific tool
}

private struct ClaudeMessage: Codable {
    let role: String // "user" or "assistant"
    let content: [ClaudeContentBlock]
}

private enum ClaudeContentBlockType: String, Codable {
    case text
    case image
    case tool_use
    case tool_result
}

private struct ClaudeContentBlock: Codable {
    let type: ClaudeContentBlockType
    let text: String?
    let source: ClaudeImageSource? // For image type
    let tool_use_id: String?       // For tool_use type
    let name: String?              // For tool_use type (tool name)
    let input: [String: JSONValue]? // For tool_use type (tool input arguments)
    let content: String?           // For tool_result type (JSON string of tool output)
    let is_error: Bool?            // For tool_result type

    // Custom initializer for simple text content
    init(text: String) {
        self.type = .text
        self.text = text
        self.source = nil
        self.tool_use_id = nil
        self.name = nil
        self.input = nil
        self.content = nil
        self.is_error = nil
    }

    // Custom initializer for image content
    init(base64ImageData: String, mediaType: String) {
        self.type = .image
        self.source = ClaudeImageSource(type: "base64", media_type: mediaType, data: base64ImageData)
        self.text = nil
        self.tool_use_id = nil
        self.name = nil
        self.input = nil
        self.content = nil
        self.is_error = nil
    }
}

private struct ClaudeImageSource: Codable {
    let type: String // e.g., "base64"
    let media_type: String // e.g., "image/jpeg", "image/png", "image/gif", "image/webp"
    let data: String // Base64 encoded image data
}

private struct ClaudeTool: Codable {
    let name: String
    let description: String
    let input_schema: ClaudeJSONSchema
}

private struct ClaudeToolChoice: Codable {
    let type: String // "auto", "any", or "tool"
    let name: String? // Required if type is "tool"
}

// Simplified JSON Schema for Claude (matches what we used for OpenAI)
private struct ClaudeJSONSchema: Codable {
    let type: String
    let properties: [String: ClaudeJSONSchemaProperty]?
    let required: [String]?
    let description: String?
}

private struct ClaudeJSONSchemaProperty: Codable {
    let type: String
    let items: ClaudeJSONSchemaItems?
    let description: String?
}

private struct ClaudeJSONSchemaItems: Codable {
    let type: String
}

// Response structure
private struct ClaudeCompletionResponse: Codable {
    let id: String
    let type: String // e.g., "message"
    let role: String // Should be "assistant"
    let content: [ClaudeContentBlock]
    let model: String
    let stop_reason: String? // e.g., "end_turn", "tool_use"
    let stop_sequence: String?
    let usage: ClaudeUsage
}

private struct ClaudeUsage: Codable {
    let input_tokens: Int
    let output_tokens: Int
}

// Helper for encoding/decoding dynamic JSON values if necessary for tool input schema.
// For this specific case (reviews: [String]), it's straightforward, but good for complex schemas.
enum JSONValue: Codable {
    case string(String)
    case number(Double) // Using Double to cover Int and Float
    case object([String: JSONValue])
    case array([JSONValue])
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.typeMismatch(JSONValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON type"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let string): try container.encode(string)
        case .number(let number): try container.encode(number)
        case .object(let object): try container.encode(object)
        case .array(let array): try container.encode(array)
        case .bool(let bool): try container.encode(bool)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - Claude Service Error
enum ClaudeServiceError: Error {
    case apiKeyMissing
    case networkError(Error)
    case responseParsingFailed(Error?)
    case generationFailed(String)
    case noReviewDraftsGenerated
    case toolUseOutputMissing
}

// MARK: - ClaudeAPIService
class ClaudeAPIService: ClaudeServiceProtocol {

    private let modelName = "claude-3-5-sonnet-20240620"
    private let maxTokensToSample = 2048 // Corresponds to `max_tokens` in the Claude API request, limiting the response length.

    init() {
        if claudeAPIKey == "YOUR_CLAUDE_API_KEY" || claudeAPIKey.isEmpty {
            print("WARNING: Claude API Key is a placeholder. Please set it in ClaudeAPIService.swift.")
        }
    }

    func generateReviewDraft(
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
        
        guard claudeAPIKey != "YOUR_CLAUDE_API_KEY" && !claudeAPIKey.isEmpty else {
            print("ERROR: Claude API Key is a placeholder or empty.")
            throw ClaudeServiceError.apiKeyMissing
        }

        var systemPrompt = "You are a helpful assistant that writes concise and engaging Google Maps review drafts. You must use the 'extract_reviews' tool to provide your answer, ensuring you generate exactly \(numberOfDraftsToRequest) distinct review drafts in the 'reviews' array within the tool's input schema."

        var userPromptString = "Please generate \(numberOfDraftsToRequest) distinct review drafts for my visit. "
        userPromptString += "The visit was to '\(placeName)' at '\(address)'.\n"
        userPromptString += "My overall experience was \(overallRating) out of 5 stars.\n"
        if foodRating > 0 { userPromptString += "Food: \(foodRating)/5. " }
        if serviceRating > 0 { userPromptString += "Service: \(serviceRating)/5. " }
        if atmosphereRating > 0 { userPromptString += "Atmosphere: \(atmosphereRating)/5.\n" }

        if let keyNotes = userKeyNotes, !keyNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userPromptString += "\nPlease also consider the following key notes from the user: \(keyNotes)\n"
        }
        
        // Image related prompt updates will be handled by adding image blocks first,
        // then the text block with instructions.
        var finalUserPromptText = userPromptString
        if let photos = photoData, !photos.isEmpty {
            finalUserPromptText += "\nBased on the preceding images and the details above, write the review drafts."
        } else {
            finalUserPromptText += "\nBased on the details above, write the review drafts."
        }

        if let reviews = existingReviews, !reviews.isEmpty {
            // This needs to be part of the text prompt that follows any images.
            var contextString = "\nHere are some existing reviews for context (try to be original and not repeat these too much):\n"
            for (index, review) in reviews.prefix(3).enumerated() {
                contextString += "Existing Review \(index + 1): '\(review.text.prefix(200))...' (Rated \(review.rating)/5)\n"
            }
            finalUserPromptText += contextString
        }
        
        print("--- Claude Prompt ---")
        print("System: \(systemPrompt)")
        // The userPromptString used for printing here might not show the image data itself,
        // but the finalUserPromptText which is part of the content blocks will be sent.
        print("User (text part): \(finalUserPromptText)")
        print("---------------------")

        var contentBlocks: [ClaudeContentBlock] = []

        if let photos = photoData, !photos.isEmpty {
            for (index, imageData) in photos.enumerated() {
                let base64String = imageData.base64EncodedString()
                if let mimeType = ImageUtils.getMIMEType(for: imageData) {
                    contentBlocks.append(ClaudeContentBlock(base64ImageData: base64String, mediaType: mimeType))
                    print("Added image \(index + 1) to Claude request as base64 encoded \(mimeType).")
                } else {
                    print("Warning: Could not determine MIME type for image \(index + 1). Attempting with image/jpeg for Claude.")
                    contentBlocks.append(ClaudeContentBlock(base64ImageData: base64String, mediaType: "image/jpeg"))
                }
            }
        }
        // Add the main text prompt after any image blocks
        contentBlocks.append(ClaudeContentBlock(text: finalUserPromptText))

        let toolSchema = ClaudeJSONSchema(
            type: "object",
            properties: [
                "reviews": ClaudeJSONSchemaProperty(
                    type: "array",
                    items: ClaudeJSONSchemaItems(type: "string"),
                    description: "An array of exactly \(numberOfDraftsToRequest) distinct review drafts."
                )
            ],
            required: ["reviews"],
            description: "Schema for generating exactly \(numberOfDraftsToRequest) distinct review drafts."
        )

        let reviewTool = ClaudeTool(
            name: "extract_reviews",
            description: "Extracts exactly \(numberOfDraftsToRequest) distinct review drafts based on the user's input and ratings.",
            input_schema: toolSchema
        )
        
        let toolChoice = ClaudeToolChoice(type: "tool", name: "extract_reviews")

        let requestBody = ClaudeRequestBody(
            model: modelName,
            max_tokens: maxTokensToSample,
            messages: [ClaudeMessage(role: "user", content: contentBlocks)],
            system: systemPrompt,
            tools: [reviewTool],
            tool_choice: toolChoice
        )

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(claudeAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue(claudeAPIVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let jsonData = try JSONEncoder().encode(requestBody)
            request.httpBody = jsonData
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("--- Claude Request Body ---")
                print(jsonString)
                print("---------------------------")
            }
        } catch {
            print("Error encoding Claude request body: \(error)")
            throw ClaudeServiceError.generationFailed("Failed to encode request body: \(error.localizedDescription)")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("Claude API call did not receive a valid HTTP response.")
                throw ClaudeServiceError.networkError(URLError(.badServerResponse))
            }

            print("Claude API Status Code: \(httpResponse.statusCode)")
            if let responseBodyString = String(data: data, encoding: .utf8) {
                print("--- Claude Raw Response Body ---")
                print(responseBodyString)
                print("------------------------------")
            }

            if !(200...299).contains(httpResponse.statusCode) {
                let errorDetail = String(data: data, encoding: .utf8) ?? "No error body from API"
                print("Claude API HTTP Error: \(httpResponse.statusCode), Detail: \(errorDetail)")
                throw ClaudeServiceError.generationFailed("Claude API Error \(httpResponse.statusCode): \(errorDetail)")
            }

            let decoder = JSONDecoder()
            let completionResponse = try decoder.decode(ClaudeCompletionResponse.self, from: data)

            // Find the tool_use content block
            guard let toolUseBlock = completionResponse.content.first(where: { $0.type == .tool_use && $0.name == "extract_reviews" }) else {
                print("Error: No 'extract_reviews' tool_use block found in Claude response. Stop Reason: \(completionResponse.stop_reason ?? "N/A")")
                // Log all content blocks for debugging
                completionResponse.content.forEach { block in
                    print("Found block: type=\(block.type), name=\(block.name ?? "nil"), text=\(block.text ?? "nil")")
                }
                throw ClaudeServiceError.toolUseOutputMissing
            }

            guard let toolInput = toolUseBlock.input else {
                print("Error: 'extract_reviews' tool_use block has no input.")
                throw ClaudeServiceError.toolUseOutputMissing
            }
            
            // The input to the tool is the JSON we want. We need to convert it from [String: JSONValue] to Data, then decode.
            // This is a bit convoluted because the tool input is already "parsed" into JSONValue by Claude.
            // We need to re-serialize it to Data then parse into our ClaudeStructuredReviewResponse.
            let toolInputData = try JSONEncoder().encode(toolInput) // Re-encode the [String: JSONValue] part
            
            print("--- Claude Tool Input (Raw Data for Decoding) ---")
            if let toolInputString = String(data: toolInputData, encoding: .utf8) {
                print(toolInputString)
            }
            print("-------------------------------------------------")

            let structuredReviewOutput = try decoder.decode(ClaudeStructuredReviewResponse.self, from: toolInputData)

            if !structuredReviewOutput.reviews.isEmpty {
                if structuredReviewOutput.reviews.count < numberOfDraftsToRequest {
                     print("Warning: Claude returned \(structuredReviewOutput.reviews.count) drafts via tool, but \(numberOfDraftsToRequest) were requested.")
                }
                print("Successfully parsed \(structuredReviewOutput.reviews.count) structured review(s) from Claude tool use.")
                return structuredReviewOutput.reviews // Return all reviews
            } else {
                print("Error: Claude tool use returned JSON with an empty 'reviews' array.")
                throw ClaudeServiceError.noReviewDraftsGenerated
            }

        } catch let error as ClaudeServiceError {
            print("ClaudeServiceError caught: \(error)")
            throw error
        } catch let decodingError as DecodingError {
            print("Claude Response/Tool Input Decoding Error: \(decodingError)")
            switch decodingError {
            case .typeMismatch(let type, let context):
                print("Type mismatch: \(type), context: \(context.debugDescription)")
            case .valueNotFound(let type, let context):
                print("Value not found: \(type), context: \(context.debugDescription)")
            case .keyNotFound(let key, let context):
                print("Key not found: \(key), context: \(context.debugDescription)")
            case .dataCorrupted(let context):
                print("Data corrupted: \(context.debugDescription)")
            @unknown default:
                print("Unknown decoding error: \(decodingError.localizedDescription)")
            }
            throw ClaudeServiceError.responseParsingFailed(decodingError)
        } catch {
            print("Claude API Call General Uncaught Error: \(error)")
            throw ClaudeServiceError.generationFailed("Claude Network/Service Error: \(error.localizedDescription)")
        }
    }
} 