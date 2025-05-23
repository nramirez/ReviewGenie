import SwiftUI
import SwiftData
import PhotosUI
import CoreLocation
import ImageIO
import AppKit // Import AppKit for NSImage
import UniformTypeIdentifiers // For UTType.jpeg
import Photos // For PHAsset

struct NewEntryView: View {
    @Environment(\.modelContext) private var modelContext
    
    // Callbacks for parent view
    var onSave: (UUID) -> Void
    var onCancel: () -> Void
    let prefillData: (place: PlaceResult, photos: [ProcessedPhoto], date: Date)?

    // State for photo handling
    @State private var selectedPhotosFromPicker: [PhotosPickerItem] = []
    @State private var processedPhotos: [ProcessedPhoto] = []

    @State private var searchText = ""
    @State private var selectedPlace: PlaceResult? = nil
    @State private var subRatingValues: [String: Double] = [
        "Food": 0.0,
        "Service": 0.0,
        "Atmosphere": 0.0
    ]
    @State private var overallExperienceRating: Double = 0.0
    @State private var keyNotes: String = ""
    @State private var generatedDrafts: [ReviewDraftDisplayItem] = []
    @State private var selectedDraft: String?
    @State private var originalChosenDraftText: String?
    @State private var currentStep = 0
    
    // New state for LLM selection and number of drafts
    @State private var useGemini: Bool = true
    @State private var useClaude: Bool = true
    @State private var numberOfDraftsToRequest: Int = 1
    @State private var shouldIncludePhotosInPrompt: Bool = false
    
    // State for Gemini Vision Service based suggestions
    @State private var geminiVisionService = GeminiVisionService()
    @State private var geminiSuggestedTopPick: GeminiVisionService.IdentifiedPlaceDetails? = nil
    @State private var nearbyPlaceCandidates: [GooglePlacesAPIService.NearbyPlaceInternal]? = nil
    @State private var isIdentifyingLocation: Bool = false
    @State private var locationIdentificationError: String? = nil
    
    // Total steps: 0:Photos, 1:Place, 2:Ratings, 3:Draft Selection, 4:Final Summary+Edit
    private let totalSteps = 4 

    private func isStepDisabled(_ step: Int) -> Bool {
        guard currentStep < step else { return false } 

        switch step {
        case 1: // Place Search
            return selectedPhotosFromPicker.isEmpty
        case 2: // Ratings
            return selectedPlace == nil
        case 3: // Review Draft Selection
            let foodRating = subRatingValues["Food"] ?? 0.0
            let serviceRating = subRatingValues["Service"] ?? 0.0
            let atmosphereRating = subRatingValues["Atmosphere"] ?? 0.0
            return selectedPlace == nil || !(useGemini || useClaude) || overallExperienceRating == 0 || foodRating == 0 || serviceRating == 0 || atmosphereRating == 0
        case 4: // Final Summary + Edit
            // Can only reach this step if a draft was selected in step 3.
            // Disabling proceeding from here depends on the draft text being non-empty.
            return selectedDraft == nil || (selectedDraft?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        default:
            return false
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                ProgressView(value: Double(currentStep), total: Double(totalSteps)) 
                    .padding()
                
                currentStepView
                .frame(maxHeight: .infinity)
                .animation(.smooth, value: currentStep)
                
                HStack {
                    if currentStep > 0 {
                        Button("Back") {
                            withAnimation {
                                currentStep -= 1
                            }
                        }
                    }
                    
                    Spacer()
                    
                    if currentStep < totalSteps {
                        Button(buttonTextForStep(currentStep)) {
                            withAnimation {
                                currentStep += 1
                            }
                        }
                        .disabled(!canProceed)
                    } else { // This is currentStep == totalSteps (i.e., 4, the final summary step)
                        Button("Save") {
                            saveVisit()
                        }
                        // Save button is enabled if canProceed is true at the last step
                        .disabled(!canProceed) 
                    }
                }
                .padding()
            }
            // Toolbar is attached to the main VStack for consistent placement
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                       onCancel()
                    }
                }
            }
            .onAppear {
                applyPrefillData()
            }
        }
        .onChange(of: processedPhotos) {
            fetchPlaceSuggestionsFromPhotos()
        }
    }
    
    @ViewBuilder
    private var currentStepView: some View {
        switch currentStep {
        case 0:
            PhotoPickerView(
                selectedPhotosFromPicker: $selectedPhotosFromPicker, 
                processedPhotos: $processedPhotos
            )
            .disabled(isStepDisabled(0))
        case 1:
            PlaceSearchView(
                searchText: $searchText, 
                selectedPlace: $selectedPlace, 
                placesService: GooglePlacesAPIService(),
                photoTakenCoordinate: selectedPlace?.coordinate,
                geminiSuggestedTopPick: geminiSuggestedTopPick,
                nearbyPlaceCandidates: nearbyPlaceCandidates, 
                isIdentifyingLocation: isIdentifyingLocation,
                locationIdentificationError: locationIdentificationError,
                onPlaceSelected: {
                    withAnimation {
                        if currentStep == 1 {
                           currentStep += 1
                        }
                    }
                }
            )
            .disabled(isStepDisabled(1))
        case 2:
            RatingsView(
                subRatingValues: $subRatingValues,
                overallExperienceRating: $overallExperienceRating,
                keyNotes: $keyNotes,
                passedInselectedPlace: selectedPlace,
                placesService: GooglePlacesAPIService(),
                useGemini: $useGemini,
                useClaude: $useClaude,
                numberOfDraftsToRequest: $numberOfDraftsToRequest,
                shouldIncludePhotosInPrompt: $shouldIncludePhotosInPrompt,
                processedPhotos: processedPhotos,
                onRemovePhoto: { photoToRemove in
                    processedPhotos.removeAll { $0.id == photoToRemove.id }
                }
            )
            .disabled(isStepDisabled(2))
        case 3:
            ReviewGenerationView(
                processedPhotos: processedPhotos, 
                selectedPlace: selectedPlace,
                subRatingValues: subRatingValues, 
                overallExperienceRating: overallExperienceRating,
                keyNotes: keyNotes,
                generatedDraftsBinding: $generatedDrafts,
                onDraftChosenForEditing: { draftItem in
                    selectedDraft = draftItem.text
                    originalChosenDraftText = draftItem.text
                    withAnimation {
                        currentStep = 4
                    }
                },
                useGemini: useGemini,
                useClaude: useClaude,
                numberOfDraftsToRequest: numberOfDraftsToRequest,
                shouldIncludePhotosInPrompt: shouldIncludePhotosInPrompt
            )
            .disabled(isStepDisabled(3))
        case 4:
            FinalSummaryView(
                selectedPlace: selectedPlace,
                finalReviewText: $selectedDraft,
                processedPhotos: processedPhotos, 
                overallRating: overallExperienceRating,
                subRatingValues: subRatingValues,
                onRemovePhoto: { photoToRemove in
                    processedPhotos.removeAll { $0.id == photoToRemove.id }
                }
            )
            .disabled(isStepDisabled(4))
        default:
            EmptyView()
        }
    }

    private func applyPrefillData() {
        guard let data = prefillData else { return }

        // Set state variables from prefillData
        self.selectedPlace = data.place
        self.processedPhotos = data.photos
        // If a visitDate state variable is added, set it here: self.visitDate = data.date
        
        // Update searchText for consistency if user navigates back
        if data.place.id != "SEARCH_INITIATED_FROM_PAST_VISIT" {
            self.searchText = data.place.name
        } else {
            self.searchText = "" // Start with an empty search field for a new search
        }
        
        // Handle navigation based on prefill data type
        if data.place.id == "SEARCH_INITIATED_FROM_PAST_VISIT" {
            // If it's a search initiated from past visit, go directly to PlaceSearchView (step 1)
            // The selectedPlace is already set to our dummy/placeholder, which contains the coordinate.
            self.currentStep = 1
        } else if !data.photos.isEmpty { // This implies a confirmed place from FindPastVisitsView or manual new entry with photos
             // If photos and a confirmed place are present, skip to Ratings step (2)
            self.currentStep = 2
        } else if !data.photos.isEmpty { 
            // This condition is identical to the one above, likely a logic error or a remnant from previous logic.
            // Assuming it might have intended to cover a scenario where only photos are prefilled,
            // but the current `prefillData` structure implies a place is always present with photos.
            // This path is likely unreachable given the current `prefillData` type.
            // Keeping the structure for now in case `prefillData` type or logic changes.
            self.currentStep = 1 // Skip to Place Search if only photos are prefilled (less likely scenario here)
        } // Else, start from step 0 (default)
    }

    private func buttonTextForStep(_ step: Int) -> String {
        switch step {
        case 2: return "Generate Reviews" // From Ratings (2) to Draft Selection (3)
        // Step 3 (Draft Selection) automatically proceeds to step 4 via onDraftChosenForEditing callback
        default: return "Next" // For steps 0 (Photos) and 1 (Place Search)
        }
    }
    
    private var canProceed: Bool {
        switch currentStep {
        case 0: // Photos step
            return !processedPhotos.isEmpty 
        case 1: // Place Search step
            return selectedPlace != nil
        case 2: // Ratings step, proceeding to review generation (Step 3)
            let restaurantTypes = ["restaurant", "cafe", "bakery", "bar", "meal_delivery", "meal_takeaway"]
            let isRestaurant = selectedPlace?.types?.contains(where: { type in
                restaurantTypes.contains(where: type.lowercased().contains)
            }) ?? false

            let hotelTypes = ["hotel", "lodging", "motel", "resort", "hostel", "apartment_hotel", "guest_house"]
            let isHotel = selectedPlace?.types?.contains(where: { type in
                hotelTypes.contains(where: type.lowercased().contains)
            }) ?? false

            if isRestaurant {
                return (useGemini || useClaude) &&
                       overallExperienceRating > 0 &&
                       (subRatingValues["Food"] ?? 0.0) > 0 &&
                       (subRatingValues["Service"] ?? 0.0) > 0 &&
                       (subRatingValues["Atmosphere"] ?? 0.0) > 0
            } else if isHotel {
                return (useGemini || useClaude) &&
                       overallExperienceRating > 0 &&
                       (subRatingValues["Rooms"] ?? 0.0) > 0 &&
                       (subRatingValues["Service"] ?? 0.0) > 0 &&
                       (subRatingValues["Location"] ?? 0.0) > 0
            } else {
                // For places that are neither restaurant nor hotel, only overall rating and LLM selection are required
                return (useGemini || useClaude) && overallExperienceRating > 0
            }
        case 3: // Review Draft Selection step (Step 3). This logic determines if ReviewGenerationView can *start* generating.
                // Actual proceeding to next step (FinalSummary) is handled by onDraftChosenForEditing.
                // This canProceed for step 3 is more about enabling the "Generate" button within ReviewGenerationView if it were externalized.
                // Since ReviewGenerationView handles its own generation trigger, this case might be less critical for the main "Next" button logic,
                // as step 3 doesn't have a "Next" button in the main HStack.
                // However, if isStepDisabled uses this, it's relevant.
            let restaurantTypesForDraft = ["restaurant", "cafe", "bakery", "bar", "meal_delivery", "meal_takeaway"]
            let isRestaurantForDraft = selectedPlace?.types?.contains(where: { type in
                restaurantTypesForDraft.contains(where: type.lowercased().contains)
            }) ?? false
            
            let hotelTypesForDraft = ["hotel", "lodging", "motel", "resort", "hostel", "apartment_hotel", "guest_house"]
            let isHotelForDraft = selectedPlace?.types?.contains(where: { type in
                hotelTypesForDraft.contains(where: type.lowercased().contains)
            }) ?? false

            if isRestaurantForDraft {
                return selectedPlace != nil && 
                        (useGemini || useClaude) && 
                        overallExperienceRating > 0 && 
                        (subRatingValues["Food"] ?? 0.0) > 0 && 
                        (subRatingValues["Service"] ?? 0.0) > 0 && 
                        (subRatingValues["Atmosphere"] ?? 0.0) > 0
            } else if isHotelForDraft {
                return selectedPlace != nil && 
                        (useGemini || useClaude) && 
                        overallExperienceRating > 0 && 
                        (subRatingValues["Rooms"] ?? 0.0) > 0 && 
                        (subRatingValues["Service"] ?? 0.0) > 0 && 
                        (subRatingValues["Location"] ?? 0.0) > 0
            } else {
                 // For places that are neither restaurant nor hotel, only overall rating and LLM selection are required for drafts
                return selectedPlace != nil && 
                        (useGemini || useClaude) && 
                        overallExperienceRating > 0
            }
        case 4: // Final Summary/Edit step (Step 4), proceeding means saving
            return selectedDraft != nil && !(selectedDraft?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        default: return false
        }
    }
    
    private func saveVisit() {
        guard let place = selectedPlace else { return }
        
        let subRatingsArray: [QuestionRating] = subRatingValues.map { key, value in
            QuestionRating(question: key, rating: Int(value))
        }
        
        let encoder = JSONEncoder()
        let subRatingsData = try? encoder.encode(subRatingsArray.filter { $0.rating ?? 0 > 0 })

        // Create ImageFileReference objects from processedPhotos
        let imageRefs: [ImageFileReference] = processedPhotos.map {
            ImageFileReference(originalFileName: $0.originalFileName, optimizedFileName: $0.optimizedFileName)
        }

        let visit = VisitRecord(
            placeID: place.id,
            placeName: place.name,
            address: place.address,
            latitude: place.latitude,
            longitude: place.longitude,
            overallExperienceRating: overallExperienceRating,
            numberOfPhotosUsed: processedPhotos.count, 
            generatedDrafts: generatedDrafts.map { $0.text },
            selectedReview: selectedDraft,
            imageReferences: imageRefs,
            subRatingsData: subRatingsData 
            // Ensure other VisitRecord init parameters are included if they exist (e.g., visitDate)
        )
        
        modelContext.insert(visit)
        onSave(visit.id)
    }

    private func fetchPlaceSuggestionsFromPhotos() {
        // Clear previous results
        self.geminiSuggestedTopPick = nil
        self.nearbyPlaceCandidates = nil
        self.locationIdentificationError = nil

        guard !processedPhotos.isEmpty else {
            print("No processed photos available for identification.")
            Task {
                await MainActor.run {
                    self.isIdentifyingLocation = false
                }
            }
            return
        }

        self.isIdentifyingLocation = true

        Task {
            // 1. Calculate overall average coordinate hint from all photos
            let coordinates = processedPhotos.compactMap { $0.coordinate }
            var averageCoordinateHint: CLLocationCoordinate2D? = nil
            if !coordinates.isEmpty {
                let totalLat = coordinates.reduce(0) { $0 + $1.latitude }
                let totalLon = coordinates.reduce(0) { $0 + $1.longitude }
                averageCoordinateHint = CLLocationCoordinate2D(latitude: totalLat / Double(coordinates.count),
                                                             longitude: totalLon / Double(coordinates.count))
            }

            // 2. Collect and deduplicate nearby places from all photo locations
            var allNearbyContextCandidates: [GooglePlacesAPIService.NearbyPlaceInternal] = []
            let placesService = GooglePlacesAPIService()
            var processingErrors: [String] = []

            for photo in processedPhotos {
                if let photoCoordinate = photo.coordinate {
                    do {
                        let photoSpecificNearby = try await placesService.searchNearbyPlacesNewAPI(
                            coordinate: photoCoordinate,
                            radius: 75 // Adjust radius based on expected accuracy and density of places
                        )
                        allNearbyContextCandidates.append(contentsOf: photoSpecificNearby)
                    } catch {
                        let errorMsg = "Error fetching nearby places for photo \(photo.optimizedFileName): \(error.localizedDescription)"
                        print("[NewEntryView] \(errorMsg)")
                        processingErrors.append(errorMsg)
                        // Continue processing other photos even if one fails for nearby search
                    }
                }
            }

            var uniqueNearbyContextPlaces: [GooglePlacesAPIService.NearbyPlaceInternal] = []
            var seenNearbyIDs = Set<String>()
            for candidate in allNearbyContextCandidates {
                if let id = candidate.id, !id.isEmpty {
                    if !seenNearbyIDs.contains(id) {
                        uniqueNearbyContextPlaces.append(candidate)
                        seenNearbyIDs.insert(id)
                    }
                } else {
                    // Handle candidates without an ID if necessary, e.g., by adding if they have a unique name/address.
                    // For now, only candidates with valid, unique IDs are included.
                    // To include all: uniqueNearbyContextPlaces.append(candidate)
                }
            }
            print("[NewEntryView] Compiled \(uniqueNearbyContextPlaces.count) unique nearby places from all photo locations.")

            // 3. Call GeminiVisionService with all photos and the unique aggregated nearby context
            do {
                // Prepare Data array of OPTIMIZED images for Gemini
                // let optimizedPhotoData: [Data] = processedPhotos.compactMap { $0.loadOptimizedImageData() }

                let visionResult = try await geminiVisionService.identifyLocationFromImages(
                    photos: self.processedPhotos, 
                    // The `identifyLocationFromImages` service currently takes [ProcessedPhoto].
                    // It's responsible for accessing optimized image data via `ProcessedPhoto.loadOptimizedImageData()`
                    // or using `optimizedFileName` as needed.
                    // If the service API changes to require [Data], `optimizedPhotoData` (commented above) should be passed.
                    averageCoordinateHint: averageCoordinateHint, 
                    nearbyContextPlaces: uniqueNearbyContextPlaces
                )
                await MainActor.run {
                    self.isIdentifyingLocation = false
                    self.geminiSuggestedTopPick = visionResult.geminiPickedPlace
                    // Display the nearby candidates compiled and sent to Gemini.
                    // If Gemini's response includes a refined `nearbyCandidates` list, `visionResult.nearbyCandidates` could be used instead.
                    self.nearbyPlaceCandidates = uniqueNearbyContextPlaces 

                    if let topPick = visionResult.geminiPickedPlace, let name = topPick.name, !name.isEmpty {
                        print("Gemini Vision (aggregated context): Suggested top pick: \(name)")
                        self.locationIdentificationError = nil
                    } else if let topPickReasoning = visionResult.geminiPickedPlace?.reasoning, !topPickReasoning.isEmpty {
                        self.locationIdentificationError = "Gemini couldn't identify a specific place. Reasoning: \(topPickReasoning)"
                        print("Gemini Vision (aggregated context): No specific place identified. Reasoning: \(topPickReasoning)")
                    } else if !processingErrors.isEmpty {
                        self.locationIdentificationError = "Issues during place suggestion: \(processingErrors.joined(separator: "; "))"
                    } else {
                        self.locationIdentificationError = "Gemini couldn't suggest a location even with aggregated context."
                        print("Gemini Vision (aggregated context): No suggestion returned.")
                    }
                }
            } catch let error as GeminiVisionServiceError {
                let errorMessage = "Vision service error: \(error)"
                print("Error identifying location with GeminiVisionService (aggregated context): \(error)")
                processingErrors.append(errorMessage)
                await MainActor.run {
                    self.isIdentifyingLocation = false
                    self.locationIdentificationError = "Suggestion Error: \(processingErrors.joined(separator: "; "))"
                    self.nearbyPlaceCandidates = uniqueNearbyContextPlaces // Still show candidates found before the error
                }
            } catch {
                let errorMessage = "Unexpected error: \(error.localizedDescription)"
                print("Unexpected error identifying location (aggregated context): \(error.localizedDescription)")
                processingErrors.append(errorMessage)
                await MainActor.run {
                    self.isIdentifyingLocation = false
                    self.locationIdentificationError = "An unexpected error occurred: \(processingErrors.joined(separator: "; "))"
                    self.nearbyPlaceCandidates = uniqueNearbyContextPlaces // Still show candidates found before the error
                }
            }
        }
    }
}

struct ProcessedPhoto: Identifiable, Hashable { 
    let id = UUID()
    let originalItemIdentifier: String?
    let optimizedFileName: String
    let originalFileName: String
    let metadata: [String: AnyHashable]? 
    let coordinate: CLLocationCoordinate2D?

    static func == (lhs: ProcessedPhoto, rhs: ProcessedPhoto) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // Helper to load image data for the OPTIMIZED version
    func loadOptimizedImageData() -> Data? {
        // Assumes FileUtils.loadImageData loads from the optimized images directory by default
        return FileUtils.loadImageData(fileName: optimizedFileName) 
    }
    
    // Helper to get SwiftUI Image for the OPTIMIZED version (for UI display)
    func getSwiftUIImage() -> Image? {
         guard let data = loadOptimizedImageData(), let nsImage = NSImage(data: data) else {
             return nil 
         }
         return Image(nsImage: nsImage)
     }
}

enum FileUtils {
    static private let imageSubdirectory = "OptimizedVisitImages" // For optimized images
    static private let originalImageSubdirectory = "OriginalVisitImages" // For original images
    static private let photoExportSubdirectory = "ReviewGeniePhotoExports"
    static let userDefaultsExportPathKey = "ReviewGenieUserChosenExportPath"

    // Returns the directory for storing OPTIMIZED images
    static func getImagesDirectory() -> URL? { 
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("Error: Cannot find Application Support directory.")
            return nil
        }
        let directoryURL = appSupportURL.appendingPathComponent(imageSubdirectory, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            do {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
                print("Created optimized image directory at: \(directoryURL.path)")
            } catch {
                print("Error creating optimized image directory: \(error)")
                return nil
            }
        }
        return directoryURL
    }

    // Returns the directory for storing ORIGINAL images
    static func getOriginalImageStorageDirectory() -> URL? { 
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("Error: Cannot find Application Support directory for original images.")
            return nil
        }
        let directoryURL = appSupportURL.appendingPathComponent(originalImageSubdirectory, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            do {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
                print("Created original image storage directory at: \(directoryURL.path)")
            } catch {
                print("Error creating original image storage directory: \(error)")
                return nil
            }
        }
        return directoryURL
    }

    static func getPhotoExportDirectory() -> URL? { 
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("Error: Cannot find Application Support directory for photo exports.")
            return nil
        }
        let directoryURL = appSupportURL.appendingPathComponent(photoExportSubdirectory, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            do {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
                print("Created photo export directory at: \(directoryURL.path)")
            } catch {
                print("Error creating photo export directory in Application Support: \(error)")
                return nil
            }
        }
        return directoryURL
    }
    
    // Saves image data to a specified directory, or defaults to the optimized images directory.
    static func saveImageData(data: Data, fileName: String, inDirectory targetDirectoryURL: URL? = nil) -> Bool {
        let finalDirectoryURL: URL?
        if let explicitDir = targetDirectoryURL {
            finalDirectoryURL = explicitDir
        } else {
            finalDirectoryURL = getImagesDirectory() // Default to optimized images directory
        }

        guard let directoryURL = finalDirectoryURL else { 
            print("Error: Target directory for saving image data is nil.")
            return false
        }
        
        let fileURL = directoryURL.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL, options: .atomic)
             print("Saved image \(fileName) to: \(fileURL.path)")
            return true
        } catch {
            print("Error saving image \(fileName) to \(fileURL.path): \(error)")
            return false
        }
    }

    // Loads image data from a specified directory, or defaults to the optimized images directory.
    static func loadImageData(fileName: String, fromDirectory sourceDirectoryURL: URL? = nil) -> Data? {
        let finalDirectoryURL: URL?
        if let explicitDir = sourceDirectoryURL {
            finalDirectoryURL = explicitDir
        } else {
            finalDirectoryURL = getImagesDirectory() // Default to optimized images directory
        }
        
        guard let directoryURL = finalDirectoryURL else { 
            print("Error: Source directory for loading image data is nil.")
            return nil 
        }
        let fileURL = directoryURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("Error: Image file not found at \(fileURL.path)")
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return data
        } catch {
            print("Error loading image \(fileName) from \(fileURL.path): \(error)")
            return nil
        }
    }

     static func createOptimizedImageData(from source: CGImageSource, maxPixelSize: CGFloat, compressionQuality: CGFloat) -> Data? {
         let thumbnailOptions: [CFString: Any] = [
             kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
             kCGImageSourceCreateThumbnailWithTransform: true, // Apply orientation transformations
             kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
         ]

         guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
             print("Error: Could not create thumbnail CGImage for optimization.")
             return nil
         }

         let optimizedData = NSMutableData()
         let destType = UTType.jpeg.identifier as CFString

         guard let destination = CGImageDestinationCreateWithData(optimizedData, destType, 1, nil) else {
             print("Error: Could not create image destination.")
             return nil
         }

         let imageHasAlpha = cgImage.alphaInfo != .none && cgImage.alphaInfo != .noneSkipLast && cgImage.alphaInfo != .noneSkipFirst

         let destinationProperties: [CFString: Any] = [
             kCGImageDestinationLossyCompressionQuality: compressionQuality
         ]

         if !imageHasAlpha && destType == UTType.jpeg.identifier as CFString {
             // For opaque JPEGs, ensure no alpha is written by drawing to a new context without alpha.
             guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else {
                  print("Error: Could not get color space for opaque image conversion.")
                  return nil
             }
             let width = cgImage.width
             let height = cgImage.height
             guard let context = CGContext(data: nil,
                                         width: width,
                                         height: height,
                                         bitsPerComponent: cgImage.bitsPerComponent, // Use source's bitsPerComponent
                                         bytesPerRow: 0, // Auto-calculate bytes per row
                                         space: colorSpace,
                                         bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
             else {
                 print("Error: Could not create CGContext for opaque image conversion.")
                 return nil
             }
             context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
             guard let opaqueCGImage = context.makeImage() else {
                 print("Error: Could not make opaque CGImage from context.")
                 return nil
             }
             CGImageDestinationAddImage(destination, opaqueCGImage, destinationProperties as CFDictionary)
         } else {
             // If image has alpha (and not JPEG, though JPEG doesn't support alpha well) or other cases, add original thumbnail
             CGImageDestinationAddImage(destination, cgImage, destinationProperties as CFDictionary)
         }

         if CGImageDestinationFinalize(destination) {
             return optimizedData as Data
         } else {
             print("Error: Failed to finalize optimized image data.")
             return nil
         }
     }

     static func extractCoordinate(fromMetadata metadata: [String: Any]?) -> CLLocationCoordinate2D? {
         guard let metadata = metadata,
               let gpsDictionary = metadata[kCGImagePropertyGPSDictionary as String] as? [String: Any] else { return nil }
         guard let lat = gpsDictionary[kCGImagePropertyGPSLatitude as String]as? Double,
               let lon = gpsDictionary[kCGImagePropertyGPSLongitude as String]as? Double,
               let latRef = gpsDictionary[kCGImagePropertyGPSLatitudeRef as String]as? String,
               let lonRef = gpsDictionary[kCGImagePropertyGPSLongitudeRef as String]as? String else { return nil }
         let finalLat = (latRef == "S") ? -lat : lat
         let finalLon = (lonRef == "W") ? -lon : lon
         let coord = CLLocationCoordinate2D(latitude: finalLat, longitude: finalLon)
         return CLLocationCoordinate2DIsValid(coord) ? coord : nil
     }

    static func makeMetadataHashable(_ metadata: [String: Any]?) -> [String: AnyHashable]? {
        guard let metadata = metadata else { return nil }
        var hashableDict: [String: AnyHashable] = [:]
        for (key, value) in metadata {
            if let hashableValue = value as? AnyHashable {
                hashableDict[key] = hashableValue
            } else {
                // Log or handle non-hashable types if necessary
                print("Warning: Skipping non-hashable metadata key: \(key) of type \(type(of: value))")
            }
        }
        return hashableDict
    }

    static func clearDirectory(at directoryURL: URL) {
        let fileManager = FileManager.default
        do {
            let filePaths = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil, options: [])
            for filePath in filePaths {
                try fileManager.removeItem(at: filePath)
            }
            print("Successfully cleared directory: \(directoryURL.path)")
        } catch {
            print("Error clearing directory \(directoryURL.path): \(error)")
        }
    }
}