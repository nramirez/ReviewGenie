import SwiftUI
import SwiftData
import PhotosUI
import CoreLocation
import ImageIO
import AppKit // Import AppKit for NSImage
import UniformTypeIdentifiers // For UTType.jpeg
import Photos // For PHAsset

struct ReviewGenerationView: View {
    let processedPhotos: [ProcessedPhoto] // Changed from selectedPhotos
    let selectedPlace: PlaceResult?
    let subRatingValues: [String: Double] // Added
    let overallExperienceRating: Double
    let keyNotes: String
    @Binding var generatedDraftsBinding: [ReviewDraftDisplayItem] // Renamed for clarity, holds all raw drafts
    var onDraftChosenForEditing: (ReviewDraftDisplayItem) -> Void // New callback

    // Pass new state for LLM selection and number of drafts
    let useGemini: Bool
    let useClaude: Bool
    let numberOfDraftsToRequest: Int
    let shouldIncludePhotosInPrompt: Bool
    
    @State private var isGenerating = false
    @State private var highlightedDraftID: UUID? = nil // Replaces activeDraftID, for visual selection only
    
    // Computed property for prepared drafts data for display
    private var displayableDraftsData: (sources: [String], groups: [String: [ReviewDraftDisplayItem]]) {
        // Grouping should still work even with items in different states (loading, success, error)
        let grouped = Dictionary(grouping: generatedDraftsBinding, by: { $0.source })
        let sorted = grouped.keys.sorted { (source1, source2) -> Bool in
            if source1 == "Gemini" { return true }
            if source2 == "Gemini" { return false }
            if source1 == "Claude" { return true }
            if source2 == "Claude" { return false }
            return source1 < source2
        }
        return (sources: sorted, groups: grouped)
    }

    private let geminiService: GeminiServiceProtocol = GeminiFirebaseService()
    private let claudeService: ClaudeServiceProtocol = ClaudeAPIService()
    
    // Computed property for the dynamic title
    private var titleText: String {
        if isGenerating {
            return "Generating Reviews..."
        } else if generatedDraftsBinding.isEmpty {
            return "No Drafts Generated"
        } else {
            return "Refine and Choose Your Review"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titleText)
                .font(.title2)
                .padding(.bottom, 5)
            
            if isGenerating {
                ProgressView("Generating drafts...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
            
            let displayData = displayableDraftsData

            if !isGenerating && !generatedDraftsBinding.isEmpty {
                List {
                    ForEach(displayData.sources, id: \.self) { source in
                        DraftDisplaySourceLayoutView(
                            source: source,
                            sourceDrafts: displayData.groups[source] ?? [],
                            numberOfDraftsToRequest: numberOfDraftsToRequest,
                            onDraftTap: { draftItem in
                                self.highlightedDraftID = draftItem.id
                                self.onDraftChosenForEditing(draftItem)
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                if selectedPlace != nil {
                    Button("Re-generate All Reviews") {
                        performReviewGeneration()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 15)
                }
            } else if !isGenerating && generatedDraftsBinding.isEmpty && selectedPlace != nil {
                Text("Ready to generate reviews.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
        .padding()
        .onAppear {
            // If generatedDraftsBinding is empty and a place is selected, then perform review generation.
            if generatedDraftsBinding.isEmpty && selectedPlace != nil {
                performReviewGeneration()
            }
            // No need to manage highlightedDraftID or provisionallySelectedDraftText here anymore
            // as selection is now direct navigation.
        }
    }
    
    private func performReviewGeneration() { 
        isGenerating = true

        // 1. Initialize generatedDraftsBinding with loading states
        var initialDrafts: [ReviewDraftDisplayItem] = []
        if useGemini {
            for _ in 0..<numberOfDraftsToRequest {
                initialDrafts.append(ReviewDraftDisplayItem(
                    source: "Gemini",
                    text: "Generating draft...",
                    status: .loading
                ))
            }
        }
        if useClaude {
            for _ in 0..<numberOfDraftsToRequest {
                initialDrafts.append(ReviewDraftDisplayItem(
                    source: "Claude",
                    text: "Generating draft...",
                    status: .loading
                ))
            }
        }
        generatedDraftsBinding = initialDrafts

        Task {
            var photoDataForAPI: [Data]? = nil

            if shouldIncludePhotosInPrompt && !processedPhotos.isEmpty {
                print("Photo inclusion requested. Loading \(processedPhotos.count) optimized photos for API...")
                var loadedPhotoData: [Data] = []
                for photo in processedPhotos {
                    // Load data from file system
                    if let data = photo.loadOptimizedImageData() { // Use helper on ProcessedPhoto
                        loadedPhotoData.append(data)
                    } else {
                        print("Warning: Failed to load image data for file \(photo.optimizedFileName) for API call.") // Using optimizedFileName for logging
                        // Decide if you want to proceed without this image or fail
                    }
                }
                if !loadedPhotoData.isEmpty {
                    photoDataForAPI = loadedPhotoData
                }
            }

            // Using async let for concurrent calls
            var geminiTask: Task<Result<[String], Error>, Never>? = nil
            if useGemini {
                geminiTask = Task {
                    await Task { // Inner Task to match original structure for result handling
                        try await geminiService.generateReviewDrafts(
                            placeName: selectedPlace?.name ?? "",
                            address: selectedPlace?.address ?? "",
                            overallRating: overallExperienceRating,
                            foodRating: subRatingValues["Food"] ?? 0.0,
                            serviceRating: subRatingValues["Service"] ?? 0.0,
                            atmosphereRating: subRatingValues["Atmosphere"] ?? 0.0,
                            photoData: photoDataForAPI,
                            existingReviews: selectedPlace?.fetchedReviews ?? [],
                            userKeyNotes: keyNotes,
                            numberOfDraftsToRequest: numberOfDraftsToRequest
                        )
                    }.result
                }
            }
            
            var claudeTask: Task<Result<[String], Error>, Never>? = nil
            if useClaude {
                claudeTask = Task {
                    await Task { // Inner Task
                        try await claudeService.generateReviewDraft(
                            placeName: selectedPlace?.name ?? "",
                            address: selectedPlace?.address ?? "",
                            overallRating: overallExperienceRating,
                            foodRating: subRatingValues["Food"] ?? 0.0,
                            serviceRating: subRatingValues["Service"] ?? 0.0,
                            atmosphereRating: subRatingValues["Atmosphere"] ?? 0.0,
                            photoData: photoDataForAPI,
                            existingReviews: selectedPlace?.fetchedReviews ?? [],
                            userKeyNotes: keyNotes,
                            numberOfDraftsToRequest: numberOfDraftsToRequest
                        )
                    }.result
                }
            }

            // Await and process results, updating generatedDraftsBinding
            if let geminiResult = await geminiTask?.value {
                await MainActor.run {
                    // Find the loading drafts for Gemini and update them
                    var geminiDraftIndex = 0
                    for i in 0..<generatedDraftsBinding.count {
                        if generatedDraftsBinding[i].source == "Gemini" && generatedDraftsBinding[i].status == .loading {
                            if geminiDraftIndex < numberOfDraftsToRequest {
                                switch geminiResult {
                                case .success(let draftTexts):
                                    if geminiDraftIndex < draftTexts.count {
                                        generatedDraftsBinding[i].text = draftTexts[geminiDraftIndex]
                                        generatedDraftsBinding[i].originalTextForRestore = draftTexts[geminiDraftIndex]
                                        generatedDraftsBinding[i].status = .success
                                    } else {
                                        // Not enough drafts returned by Gemini
                                        generatedDraftsBinding[i].text = "Gemini: Could not generate draft \(geminiDraftIndex + 1)."
                                        generatedDraftsBinding[i].status = .error(message: "Not enough drafts returned.")
                                    }
                                case .failure(let error):
                                    generatedDraftsBinding[i].text = "Gemini Error: \(error.localizedDescription)"
                                    generatedDraftsBinding[i].status = .error(message: error.localizedDescription)
                                }
                                geminiDraftIndex += 1
                            }
                        }
                    }
                }
            }
            
            if let claudeResult = await claudeTask?.value {
                await MainActor.run {
                    // Find the loading drafts for Claude and update them
                    var claudeDraftIndex = 0
                    for i in 0..<generatedDraftsBinding.count {
                        if generatedDraftsBinding[i].source == "Claude" && generatedDraftsBinding[i].status == .loading {
                            if claudeDraftIndex < numberOfDraftsToRequest {
                                switch claudeResult {
                                case .success(let draftTexts):
                                    if claudeDraftIndex < draftTexts.count {
                                        generatedDraftsBinding[i].text = draftTexts[claudeDraftIndex]
                                        generatedDraftsBinding[i].originalTextForRestore = draftTexts[claudeDraftIndex]
                                        generatedDraftsBinding[i].status = .success
                                    } else {
                                        // Not enough drafts returned by Claude
                                        generatedDraftsBinding[i].text = "Claude: Could not generate draft \(claudeDraftIndex + 1)."
                                        generatedDraftsBinding[i].status = .error(message: "Not enough drafts returned.")
                                    }
                                case .failure(let error):
                                    generatedDraftsBinding[i].text = "Claude Error: \(error.localizedDescription)"
                                    generatedDraftsBinding[i].status = .error(message: error.localizedDescription)
                                }
                                claudeDraftIndex += 1
                            }
                        }
                    }
                }
            }

            // After all tasks attempt to complete, set overall generating state to false.
            // Individual items in generatedDraftsBinding will reflect their own success/error/loading state.
            await MainActor.run {
                self.isGenerating = false
                // The `generatedDraftsBinding` used to trigger `initializeTextsAndSelection`.
                // Now that generatedDraftsBinding is directly managed, we might not need this specific onChange trigger
                // or generatedDrafts in the same way.
                // Let's see how the UI behaves and adjust `initializeTextsAndSelection` or its triggers if needed.
                // For now, `generatedDraftsBinding` is the source of truth for display.
                
                // Select the first successful draft by default if there are any
                if let firstSuccessItem = self.generatedDraftsBinding.first(where: { $0.status == .success }) {
                    self.highlightedDraftID = firstSuccessItem.id // Changed from activeIndex and activeEditorIndex
                    // Also update the selected review for save - will be handled by onChange(of: highlightedDraftID)
                }
            }
        }
    }
}

// New Helper View for displaying drafts from a single source
private struct DraftDisplaySourceLayoutView: View {
    let source: String
    let sourceDrafts: [ReviewDraftDisplayItem] // Direct drafts to display
    let numberOfDraftsToRequest: Int
    let onDraftTap: (ReviewDraftDisplayItem) -> Void // Callback when a draft is tapped

    var body: some View {
        Section { // Keep Section here if it's per source, or move it into the loop if preferred
            VStack(alignment: .leading, spacing: 6) {
                Text("Drafts from \(source)")
                    .font(.headline)
                    .padding(.bottom, 3)
                
                // Use the IDs from sourceDrafts to find the correct items in generatedDraftsBinding for binding
                if sourceDrafts.count > 1 && numberOfDraftsToRequest > 1 {
                    HStack(spacing: 10) {
                        ForEach(sourceDrafts) { draftItemFromLayout in // Iterating over a copy for layout
                            DraftDisplayCardView(
                                draftItem: draftItemFromLayout, // Pass the item directly
                                onTap: {
                                    onDraftTap(draftItemFromLayout) // Call the callback
                                }
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    ForEach(sourceDrafts) { draftItem in
                        DraftDisplayCardView(
                            draftItem: draftItem, // Pass the item directly
                            onTap: {
                                onDraftTap(draftItem) // Call the callback
                            }
                        )
                    }
                }
            }
        }
    }
}

// Displays a single non-editable draft.
struct DraftDisplayCardView: View {
    let draftItem: ReviewDraftDisplayItem
    var onTap: () -> Void
    
    // No @FocusState or other complex state needed here for display-only card

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch draftItem.status {
            case .loading:
                HStack {
                    ProgressView()
                    Text(draftItem.text) // Shows "Generating draft..."
                        .foregroundColor(.secondary)
                }
                .frame(minHeight: 80, maxHeight: 180) 
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Material.ultraThickMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                )
            case .success:
                Text(draftItem.text)
                    .frame(minHeight: 80, maxHeight: .infinity, alignment: .topLeading) // Allow dynamic height
                    .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)) // Adjusted padding
                    .frame(maxWidth: .infinity, alignment: .leading) // Ensure it takes full width
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Material.ultraThickMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                    )
                
            case .error(let message):
                VStack(alignment: .leading) {
                    Text("Error")
                        .foregroundColor(.red)
                        .fontWeight(.bold)
                    Text(message)
                        .foregroundColor(.red.opacity(0.8))
                        .font(.caption)
                }
                .frame(minHeight: 80, maxHeight: 180)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Material.ultraThickMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red.opacity(0.6), lineWidth: 1)
                )
            }
        }
        .cornerRadius(10)
        .onTapGesture { 
            if draftItem.status == .success { // Only allow tap if successful
                onTap() // Call the passed-in onTap closure
            }
        } 
    }
}