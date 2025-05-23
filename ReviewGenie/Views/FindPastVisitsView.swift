import SwiftUI
import CoreLocation // For CLLocationCoordinate2D
import Photos // For PHAsset

// Define RelativeDateRange enum for predefined date periods.
enum RelativeDateRange: String, CaseIterable, Identifiable {
    case yesterday = "Yesterday"
    case lastWeek = "Last Week"
    case pastMonth = "Past Month" // e.g., last 30 days
    case lastThreeMonths = "Last Three Months" // e.g., last 90 days
    case thisYear = "This Year" // From the start of the current calendar year up to the end of the current day.

    var id: String { self.rawValue }

    /// Calculates the `DateInterval` corresponding to the relative date range.
    func dateInterval() -> DateInterval {
        let now = Date()
        let calendar = Calendar.current
        switch self {
        case .yesterday:
            // Interval from the beginning of yesterday to the beginning of today.
            let startOfYesterday = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: now)!)
            let endOfYesterday = calendar.startOfDay(for: now) // Exclusive of the start of today.
            return DateInterval(start: startOfYesterday, end: endOfYesterday)
        case .lastWeek: // Previous full 7 days, ending at the start of today.
            let todayStart = calendar.startOfDay(for: now)
            let sevenDaysAgoStart = calendar.date(byAdding: .day, value: -7, to: todayStart)!
            return DateInterval(start: sevenDaysAgoStart, end: todayStart)
        case .pastMonth: // Previous full 30 days, ending at the start of today.
            let todayStart = calendar.startOfDay(for: now)
            let thirtyDaysAgoStart = calendar.date(byAdding: .day, value: -30, to: todayStart)!
            return DateInterval(start: thirtyDaysAgoStart, end: todayStart)
        case .lastThreeMonths: // Previous full 90 days, ending at the start of today.
            let todayStart = calendar.startOfDay(for: now)
            let ninetyDaysAgoStart = calendar.date(byAdding: .day, value: -90, to: todayStart)!
            return DateInterval(start: ninetyDaysAgoStart, end: todayStart)
        case .thisYear: // From the start of the current year to the end of the current day.
            let year = calendar.component(.year, from: now)
            let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
            // To include the entire current day, the interval extends to the start of the next day.
            let endOfToday = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now)!)
            return DateInterval(start: startOfYear, end: endOfToday)
        }
    }
}

// Enum for unified date selection in the Picker, combining relative ranges and specific years.
enum DateSelectionOption: Hashable, Identifiable {
    case relative(RelativeDateRange)
    case specificYear(Int)

    var id: String {
        switch self {
        case .relative(let range):
            return range.rawValue
        case .specificYear(let year):
            // Prefix "year_" to ensure uniqueness, as a RelativeDateRange rawValue might coincidentally be a number string.
            return "year_\(year)"
        }
    }

    var displayName: String {
        switch self {
        case .relative(let range):
            return range.rawValue
        case .specificYear(let year):
            return String(year)
        }
    }
}

// Actor for caching ProcessedPhoto instances to avoid redundant processing and ensure thread safety.
// This actor manages the underlying dictionary (`cache`) and a dictionary of ongoing image processing
// tasks (`processingTasks`). Using an actor serializes access to these mutable states, preventing
// race conditions when multiple parts of the UI request photos concurrently.
actor ProcessedPhotoCacheActor {
    private var cache: [String: ProcessedPhoto] = [:]
    // Tracks ongoing `ImageProcessingService.processPHAsset` tasks. The key is the asset's localIdentifier.
    // This prevents redundant processing if the same asset is requested multiple times in quick succession
    // before the initial processing for it has completed.
    private var processingTasks: [String: Task<ProcessedPhoto, Error>] = [:]

    // Retrieves a ProcessedPhoto for a given PHAsset, using cache if available,
    // otherwise processes and caches it. Handles concurrent requests for the same asset.
    func photo(for asset: PHAsset) async throws -> ProcessedPhoto {
        let identifier = asset.localIdentifier

        // Check cache first
        if let cachedPhoto = cache[identifier] {
            return cachedPhoto
        }

        // Check if a task is already processing this asset
        if let existingTask = processingTasks[identifier] {
            // Wait for the existing task to complete
            do {
                return try await existingTask.value
            } catch {
                // If the existing task failed, remove it and allow a new attempt
                processingTasks[identifier] = nil
                throw error
            }
        }

        // No cached photo and no processing task, create a new one
        let newTask = Task { () -> ProcessedPhoto in
            defer {
                // Remove the task from processingTasks once completed (successfully or with error)
                processingTasks[identifier] = nil
            }
            // Process the PHAsset using the static method.
            let processedPhoto = try await ImageProcessingService.processPHAsset(asset: asset)
            cache[identifier] = processedPhoto // Store in cache for future use.
            return processedPhoto
        }

        processingTasks[identifier] = newTask
        return try await newTask.value
    }

    // Clears the cache and any ongoing processing tasks.
    func clearCache() {
        cache = [:]
        // Cancel and remove ongoing tasks.
        processingTasks.values.forEach { $0.cancel() }
        processingTasks = [:]
        print("ProcessedPhotoCacheActor: Cache cleared.")
    }
    
    // Helper to get current cache count if needed (for @Published property or debugging)
    func getCacheCount() -> Int {
        return cache.count
    }
}

// ObservableObject class that uses the ProcessedPhotoCacheActor.
// This class acts as a bridge between SwiftUI views (which expect ObservableObjects)
// and the `ProcessedPhotoCacheActor` (which handles the thread-safe caching logic).
// It ensures that if any @Published properties were to be added to this service for UI updates,
// they could be safely modified on the @MainActor.
@MainActor // Ensure changes to published properties are on the main actor
class ProcessedPhotoCacheService: ObservableObject {
    private let actor = ProcessedPhotoCacheActor()

    // Optional: Publish cache size for UI updates if needed.
    // @Published private(set) var cacheSize: Int = 0

    // Retrieves a ProcessedPhoto for a given PHAsset.
    func photo(for asset: PHAsset) async throws -> ProcessedPhoto {
        let result = try await actor.photo(for: asset)
        // To update cacheSize if it were published:
        // self.cacheSize = await actor.getCacheCount()
        return result
    }

    // Clears the cache.
    func clearCache() async {
        await actor.clearCache()
        // To update cacheSize if it were published:
        // self.cacheSize = await actor.getCacheCount() // or just set to 0
        print("ProcessedPhotoCacheService: Instructed actor to clear cache.")
    }
}

// Cache for Google Places API Nearby Search results to reduce API calls and improve performance.
class NearbyPlacesCacheService: ObservableObject {
    private var cache: [String: [GooglePlacesAPIService.NearbyPlaceInternal]] = [:]

    func get(forKey key: String) -> [GooglePlacesAPIService.NearbyPlaceInternal]? {
        return cache[key]
    }

    func set(_ places: [GooglePlacesAPIService.NearbyPlaceInternal], forKey key: String) {
        cache[key] = places
    }

    func clear() {
        cache = [:]
    }
}

// Cache for Gemini Vision API results (specifically the identified top pick) to reduce API calls.
class GeminiVisionCacheService: ObservableObject {
    private var cache: [String: GeminiVisionService.IdentifiedPlaceDetails] = [:]

    func get(forKey key: String) -> GeminiVisionService.IdentifiedPlaceDetails? {
        return cache[key]
    }

    func set(_ placeDetails: GeminiVisionService.IdentifiedPlaceDetails, forKey key: String) {
        cache[key] = placeDetails
    }

    func clear() {
        cache = [:]
    }
}

struct FindPastVisitsView: View {
    @State private var suggestions: [DraftVisitSuggestion] = []
    @State private var isLoading = false
    @State private var statusMessage = "Select a period to find past visits."
    @State private var isProcessingConfirm = false // Prevents multiple concurrent confirmations.
    @State private var selectedDateChoice: DateSelectionOption? = nil // Default to nil, indicating no period is initially selected.

    let currentYear = Calendar.current.component(.year, from: Date())
    // Provides recent 10 years plus the current year, reversed for typical Picker display order (most recent first).
    var availableYears: [Int] { Array((currentYear - 10)...currentYear).reversed() }
    
    // Combines relative date ranges and specific available years for the selection Picker.
    var allDateChoices: [DateSelectionOption] {
        var choices: [DateSelectionOption] = RelativeDateRange.allCases.map { .relative($0) }
        choices.append(contentsOf: availableYears.map { .specificYear($0) })
        return choices
    }

    // Callbacks for view actions
    var onCancel: (() -> Void)?
    var onStartReview: ((place: PlaceResult, photos: [ProcessedPhoto], date: Date)) -> Void
    var onStartSearchForNewPlace: ((photos: [ProcessedPhoto], date: Date, averageCoordinate: CLLocationCoordinate2D)) -> Void

    // Services used by this view
    private let photoService = PhotoLibraryService()
    private let geminiVisionService = GeminiVisionService() 

    // Instantiate cache services as StateObjects to manage their lifecycle.
    @StateObject private var photoCacheService = ProcessedPhotoCacheService()
    @StateObject private var nearbyPlacesCacheService = NearbyPlacesCacheService()
    @StateObject private var geminiVisionCacheService = GeminiVisionCacheService()

    // Thresholds for clustering photos into visits.
    private let TIME_THRESHOLD_SECONDS: TimeInterval = 3 * 3600 // 3 hours: photos taken more than 3 hours apart are considered separate events.
    private let DISTANCE_THRESHOLD_METERS: CLLocationDistance = 300 // 300 meters: photos taken more than 300m apart are considered separate locations.

    var body: some View {
        VStack(alignment: .leading) {
            // Picker for selecting the date range or year to scan for visits.
            HStack {
                Text("Scan Period:")
                    .font(.headline)
                Picker("Select Period", selection: $selectedDateChoice) {
                    Text("Select a period").tag(DateSelectionOption?.none) // Placeholder for no selection.
                    ForEach(allDateChoices) { choice in
                        Text(choice.displayName).tag(DateSelectionOption?(choice))
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .onChange(of: selectedDateChoice) { _, newChoice in
                    Task {
                        guard let choice = newChoice else { 
                            suggestions = [] // Clear suggestions if no period is selected.
                            statusMessage = "Please select a period to scan."
                            return 
                        }
                        // Trigger visit finding logic based on the selected choice.
                        switch choice {
                        case .relative(let period):
                            await findVisits(for: period)
                        case .specificYear(let year):
                            await findVisits(forYear: year)
                        }
                    }
                }
            }
            .padding(.bottom)
            
            // Display loading indicator, status message, or suggestions list.
            if isLoading {
                ProgressView(statusMessage)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if suggestions.isEmpty {
                Text(statusMessage) // Shows "No visits found" or "Select a period".
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 20) { // LazyVStack for performance with many suggestions.
                        ForEach(suggestions) { suggestion in
                            SuggestionRowItemView(
                                suggestion: suggestion,
                                doConfirmTopPick: { [self] sug, pr in 
                                    await self.handleConfirm(suggestion: sug, confirmedPlace: pr) 
                                },
                                doConfirmNearbyPlace: { [self] sug, np in 
                                    await self.handleConfirm(suggestion: sug, nearbyPlace: np)
                                },
                                doSelectDifferentPlace: { [self] sug in 
                                    self.handleSelectDifferentPlace(for: sug) 
                                },
                                photoCacheService: photoCacheService,
                                nearbyPlacesCacheService: nearbyPlacesCacheService,
                                geminiVisionCacheService: geminiVisionCacheService
                            )
                        }
                    }
                }
            }
            Spacer() // Pushes content to the top.
        }
        .padding() 
        .navigationTitle("Find Past Visits")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    onCancel?()
                }
            }
            ToolbarItem(placement: .confirmationAction) { // Refresh button.
                Button {
                    Task {
                        // Clear all caches before a manual refresh.
                        await self.photoCacheService.clearCache()
                        self.nearbyPlacesCacheService.clear()
                        self.geminiVisionCacheService.clear()
                        
                        // Re-run the scan for the currently selected period.
                        if let currentChoice = selectedDateChoice {
                            statusMessage = "Refreshing..."
                            isLoading = true // Show loading indicator immediately.
                            suggestions = [] // Clear current suggestions before refresh.
                            switch currentChoice {
                            case .relative(let period):
                                await findVisits(for: period)
                            case .specificYear(let year):
                                await findVisits(forYear: year)
                            }
                        } else {
                            // If no period is selected, reset status.
                            suggestions = []
                            statusMessage = "Please select a period to scan."
                            isLoading = false
                        }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading) // Disable refresh button while already loading.
            }
        }
    }
    
    // Helper to get an error message string from a suggestion status.
    private func getErrorMessage(for status: DraftVisitSuggestion.SuggestionStatus) -> String? {
        switch status {
        case .visionServiceFailed(let error): return error
        case .identificationFailed(let error): return error
        default: return nil // No error message for other statuses.
        }
    }

    // Finds visits for a specific calendar year.
    private func findVisits(forYear year: Int) async {
        isLoading = true
        suggestions = [] 
        // Clear all caches when doing a full year scan, as context might be very different.
        await self.photoCacheService.clearCache()
        self.nearbyPlacesCacheService.clear()
        self.geminiVisionCacheService.clear()
        
        let calendar = Calendar.current
        // Define the interval for the entire specified year.
        guard let startDate = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let endDate = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else {
            await MainActor.run {
                statusMessage = "Invalid year selected."
                isLoading = false
            }
            return
        }
        let yearInterval = DateInterval(start: startDate, end: endDate) // end date is exclusive.
        
        await MainActor.run { statusMessage = "Scanning year \(String(year)) for photos..." }
        
        // Use the common photo fetching and processing logic.
        await fetchAndProcessPhotos(for: yearInterval, periodDescription: "year \(String(year))")
    }

    // Common logic to fetch photos for a given date interval and process them into visit suggestions.
    private func fetchAndProcessPhotos(for dateInterval: DateInterval, periodDescription: String) async {
        let assets = await photoService.fetchPhotoAssets(dateInterval: dateInterval)

        guard !assets.isEmpty else {
            await MainActor.run {
                statusMessage = "No photos with location data found for \(periodDescription)."
                isLoading = false
            }
            return
        }

        await MainActor.run {
            self.statusMessage = "Found \(assets.count) photos for \(periodDescription). Identifying potential visit clusters..."
            self.suggestions = [] // Clear previous suggestions for the new scan.
            self.isLoading = true
        }

        var currentPhotoCluster: [PHAsset] = []
        var identifiedClusterCount = 0 // Counter for identified clusters.

        // Iterate through sorted assets to identify clusters based on time and location.
        for i in 0..<assets.count {
            let currentAsset = assets[i]
            
            // If currentPhotoCluster is empty, this is the start of a potential new cluster.
            if currentPhotoCluster.isEmpty {
                if currentAsset.location != nil { // Only add assets with location to a cluster.
                    currentPhotoCluster.append(currentAsset)
                }
                // If this is the last asset in the entire list and it formed a cluster (even of one photo),
                // finalize this cluster.
                if i == assets.count - 1 && !currentPhotoCluster.isEmpty {
                    identifiedClusterCount += 1
                    createMinimalSuggestion(from: currentPhotoCluster, clusterIndex: identifiedClusterCount)
                    currentPhotoCluster = [] // Reset for safety, though loop ends.
                }
                continue // Move to the next asset.
            }

            // At this point, currentPhotoCluster is not empty.
            // We need location data from the last asset in the cluster and the current asset to compare.
            guard let lastAssetInCluster = currentPhotoCluster.last,
                  let lastAssetLocation = lastAssetInCluster.location,
                  let currentAssetLocation = currentAsset.location else {
                // If essential location data is missing for comparison, finalize the existing cluster.
                if !currentPhotoCluster.isEmpty {
                    identifiedClusterCount += 1
                    createMinimalSuggestion(from: currentPhotoCluster, clusterIndex: identifiedClusterCount)
                    currentPhotoCluster = []
                }
                // Attempt to start a new cluster with the current asset if it has a location.
                if currentAsset.location != nil { currentPhotoCluster.append(currentAsset) }
                continue // Move to the next asset.
            }

            // Calculate time and distance differences between the current asset and the last one in the cluster.
            let timeDifference = currentAsset.creationDate?.timeIntervalSince(lastAssetInCluster.creationDate ?? Date.distantPast) ?? 0
            let distance = currentAssetLocation.distance(from: lastAssetLocation)
            
            var shouldFinalizeCurrentCluster = false

            // Determine if the current asset breaks the cluster criteria (too far in time or distance).
            if timeDifference > TIME_THRESHOLD_SECONDS || distance > DISTANCE_THRESHOLD_METERS {
                shouldFinalizeCurrentCluster = true
            }

            if shouldFinalizeCurrentCluster {
                // Finalize the current cluster because the criteria were met.
                identifiedClusterCount += 1
                createMinimalSuggestion(from: currentPhotoCluster, clusterIndex: identifiedClusterCount)
                currentPhotoCluster = [] // Reset to start a new cluster.
                
                // The current asset (which broke the previous cluster) starts a new cluster if it has a location.
                if currentAsset.location != nil { 
                    currentPhotoCluster.append(currentAsset)
                }
            }
            else {
                // Current asset fits within the existing cluster.
                currentPhotoCluster.append(currentAsset) 
            }

            // If this is the last asset in the entire list and it's part of an unfinalized cluster,
            // finalize this cluster. This ensures the last cluster is always processed.
            if i == assets.count - 1 && !currentPhotoCluster.isEmpty {
                identifiedClusterCount += 1
                createMinimalSuggestion(from: currentPhotoCluster, clusterIndex: identifiedClusterCount)
            }
        }

        await MainActor.run {
            self.isLoading = false 
            if self.suggestions.isEmpty {
                self.statusMessage = "No visit clusters found in \(periodDescription)."
            } else {
                self.statusMessage = "Found \(self.suggestions.count) potential visits for \(periodDescription). Details load as you scroll."
            }
        }
    }

    // Finds visits for a relative date period (e.g., "Last Week").
    private func findVisits(for period: RelativeDateRange) async {
        isLoading = true
        suggestions = []
        // For relative periods, caches are generally kept active for speed.
        // However, for very broad periods like "This Year", a cache clear might be beneficial, similar to specific year scans.
        if period == .thisYear {
            await self.photoCacheService.clearCache()
            self.nearbyPlacesCacheService.clear()
            self.geminiVisionCacheService.clear()
        }

        let dateInterval = period.dateInterval()
        await MainActor.run { statusMessage = "Scanning \(period.rawValue) for photos..." }
        
        await fetchAndProcessPhotos(for: dateInterval, periodDescription: period.rawValue)
    }

    // Creates a minimal DraftVisitSuggestion from a cluster of photos and adds it to the suggestions list.
    private func createMinimalSuggestion(from cluster: [PHAsset], clusterIndex: Int) {
        guard let firstAsset = cluster.first, let lastAsset = cluster.last else { return }

        var avgLat: Double = 0, avgLon: Double = 0
        var validCoordsCount = 0
        // Calculate the average coordinate of all photos in the cluster.
        for asset in cluster {
            if let coord = asset.location?.coordinate {
                avgLat += coord.latitude
                avgLon += coord.longitude
                validCoordsCount += 1
            }
        }
        // Ensure not to divide by zero; use first asset's location as fallback if no valid coordinates.
        let averageCoordinate = validCoordsCount > 0 ? 
            CLLocationCoordinate2D(latitude: avgLat / Double(validCoordsCount), longitude: avgLon / Double(validCoordsCount)) :
            (firstAsset.location?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)) // Fallback coordinate.

        let newMinimalSuggestion = DraftVisitSuggestion(
            averageCoordinate: averageCoordinate,
            dateRange: (start: firstAsset.creationDate ?? Date(), end: lastAsset.creationDate ?? Date()),
            representativePhotoAssetIdentifier: firstAsset.localIdentifier, // Use first asset for representative photo ID.
            allPhotoAssetIdentifiersInCluster: cluster.map { $0.localIdentifier },
            geminiSuggestedTopPick: nil, // To be filled later by SuggestionRowItemView.
            nearbyPlaceCandidates: nil, // To be filled later by SuggestionRowItemView.
            status: .pendingPhotoProcessing // Initial status.
        )
        
        Task { // Ensure UI updates (appending to suggestions) are on the main thread.
            await MainActor.run {
                self.suggestions.append(newMinimalSuggestion)
                // Sort suggestions as they are added to maintain order, typically by date descending.
                self.suggestions.sort(by: { $0.dateRange.start > $1.dateRange.start })
                self.statusMessage = "Identified \(self.suggestions.count) potential visits..."
            }
        }
    }

    // Processes PHAssets for a given suggestion to get an array of ProcessedPhoto objects.
    private func processPhotosForSuggestion(_ suggestion: DraftVisitSuggestion) async -> [ProcessedPhoto] {
        var processedPhotosForEntry: [ProcessedPhoto] = []
        let assetIdentifiers = suggestion.allPhotoAssetIdentifiersInCluster
        
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: assetIdentifiers, options: nil)
        var assetsToProcess: [PHAsset] = []
        fetchResult.enumerateObjects { (asset, _, _) in
            assetsToProcess.append(asset)
        }

        if assetsToProcess.isEmpty && !assetIdentifiers.isEmpty {
            print("Error: Could not fetch PHAssets for processing suggestion \(suggestion.id).")
            return []
        }
        
        for asset in assetsToProcess {
            do {
                // Use the cache service to get processed photos, avoiding redundant work.
                let processedPhoto = try await photoCacheService.photo(for: asset)
                processedPhotosForEntry.append(processedPhoto)
            } catch {
                print("Error processing asset \(asset.localIdentifier) for suggestion \(suggestion.id) via cache: \(error)")
            }
        }
        return processedPhotosForEntry
    }
    
    // Handles the action when the user wants to select a different place for a suggestion.
    private func handleSelectDifferentPlace(for suggestion: DraftVisitSuggestion) {
        print("User wants to select a different place for suggestion: \(suggestion.id)")
        Task {
            let processedPhotos = await processPhotosForSuggestion(suggestion)
            // Prepare context for the place search view.
            let searchContext = (photos: processedPhotos, date: suggestion.dateRange.start, averageCoordinate: suggestion.averageCoordinate)
            
            await MainActor.run {
                onStartSearchForNewPlace(searchContext) // Trigger navigation/modal for new place search.
            }
        }
    }
    
    // Handles the confirmation of a visit with a specific PlaceResult.
    private func handleConfirm(suggestion: DraftVisitSuggestion, confirmedPlace: PlaceResult) async {
        await MainActor.run {
            if self.isProcessingConfirm { return } // Prevent re-entry if already processing.
            self.isProcessingConfirm = true
            self.statusMessage = "Processing images for \(confirmedPlace.name)..."
        }

        let processedPhotos = await processPhotosForSuggestion(suggestion)
        
        // Prepare data to start the review process.
        let prefillTuple = (place: confirmedPlace, photos: processedPhotos, date: suggestion.dateRange.start)
        
        onStartReview(prefillTuple) // Trigger navigation/modal for review creation.

        await MainActor.run {
            // Update the status of the confirmed suggestion.
            if let index = self.suggestions.firstIndex(where: { $0.id == suggestion.id }) {
                self.suggestions[index].status = .userConfirmed 
            }
            self.isProcessingConfirm = false
        }
    }
    
    // Overload of handleConfirm for when a nearby place (GooglePlacesAPIService.NearbyPlaceInternal) is chosen.
    private func handleConfirm(suggestion: DraftVisitSuggestion, nearbyPlace: GooglePlacesAPIService.NearbyPlaceInternal) async {
         // Convert NearbyPlaceInternal to PlaceResult.
         let placeResult = PlaceResult(
            id: nearbyPlace.id ?? UUID().uuidString, 
            name: nearbyPlace.displayName?.text ?? "Unknown Nearby Place",
            address: nearbyPlace.formattedAddress ?? "Address not available", 
            latitude: suggestion.averageCoordinate.latitude, // Use suggestion's coordinate as nearby place might not have precise one.
            longitude: suggestion.averageCoordinate.longitude, 
            photoReference: nil, // NearbyPlaceInternal might not map directly to all PlaceResult fields.
            fetchedReviews: [],
            overallRating: nil
        )
        await handleConfirm(suggestion: suggestion, confirmedPlace: placeResult)
    }

    // Handles ignoring a suggestion (currently removes it from the list).
    private func handleIgnore(suggestion: DraftVisitSuggestion) {
        print("IGNORE action for: \(suggestion.suggestedPlaceName ?? "N/A") - ID: \\(suggestion.id)")
        suggestions.removeAll { $0.id == suggestion.id }
        if suggestions.isEmpty {
            statusMessage = "All suggestions ignored or none were found initially."
        }
    }
}

// View for displaying a single row item in the list of visit suggestions.
// This view is responsible for lazily loading detailed data for its suggestion.
struct SuggestionRowItemView: View {
    let suggestion: DraftVisitSuggestion // The minimal suggestion passed from the parent view.
    @State private var representativeImage: Image? = nil
    
    // State for data fetched by this row view itself (e.g., top pick, nearby places).
    @State private var processedPhotosForRow: [ProcessedPhoto] = []
    @State private var fetchedNearbyPlaces: [GooglePlacesAPIService.NearbyPlaceInternal]? = nil
    @State private var identifiedTopPick: GeminiVisionService.IdentifiedPlaceDetails? = nil
    @State private var isLoadingRowData: Bool = false // Indicates if this specific row is loading its details.
    @State private var rowError: String? = nil // Error message specific to this row's data loading.

    // Action closures passed from FindPastVisitsView.
    var doConfirmTopPick: (DraftVisitSuggestion, PlaceResult) async -> Void
    var doConfirmNearbyPlace: (DraftVisitSuggestion, GooglePlacesAPIService.NearbyPlaceInternal) async -> Void 
    var doSelectDifferentPlace: (DraftVisitSuggestion) -> Void
    
    // Cache services observed for changes and used for data fetching.
    @ObservedObject var photoCacheService: ProcessedPhotoCacheService
    @ObservedObject var nearbyPlacesCacheService: NearbyPlacesCacheService
    @ObservedObject var geminiVisionCacheService: GeminiVisionCacheService

    // Instances of services for API calls.
    private let placesService = GooglePlacesAPIService()
    private let geminiVisionService = GeminiVisionService()

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            // --- Left Side: Representative Image + More Pics Count ---
            VStack(spacing: 4) {
                if let image = representativeImage {
                    image.resizable().scaledToFill().frame(width: 100, height: 100).cornerRadius(8).clipped()
                } else {
                    // Placeholder image.
                    Image(systemName: "photo.on.rectangle.angled").resizable().scaledToFit().frame(width: 100, height: 100).cornerRadius(8).foregroundColor(.gray)
                }
                let morePicsCount = suggestion.allPhotoAssetIdentifiersInCluster.count - 1
                if morePicsCount > 0 {
                    let picsSuffix = morePicsCount == 1 ? "pic" : "pics"
                    let countString = String(morePicsCount) 
                    let morePicsDisplayString = "+" + countString + " more " + picsSuffix
                    Text(morePicsDisplayString).font(.caption).foregroundColor(.secondary)
                }
            }
            .frame(width: 100)
            
            // --- Right Side: Horizontal Carousel of Place Suggestions / Loading / Error ---
            VStack(alignment: .leading) {
                // Cluster Date Header (using initial suggestion data).
                HStack {
                    Text("Visit around: \(suggestion.dateRange.start.formatted(date: .abbreviated, time: .shortened))")
                        .font(.headline)
                    Spacer()
                }
                .padding(.bottom, 2)

                if isLoadingRowData {
                    ProgressView("Loading details...")
                        .frame(height: 100) // Consistent height during loading.
                } else if let error = rowError {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                        .font(.caption)
                        .frame(height: 100)
                } else {
                    // Horizontal ScrollView for the place suggestion cards.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 15) {
                            // 1. Top Pick Card (from Gemini Vision).
                            if let topPickToDisplay = identifiedTopPick, let name = topPickToDisplay.name, !name.isEmpty {
                               PlaceSuggestionCardView(
                                    placeName: name,
                                    address: topPickToDisplay.address,
                                    confidence: topPickToDisplay.confidence, 
                                    isTopPick: true, 
                                    onSelect: { 
                                        let placeResult = PlaceResult(
                                            id: topPickToDisplay.placeID ?? UUID().uuidString,
                                            name: name,
                                            address: topPickToDisplay.address ?? "Address not available",
                                            latitude: topPickToDisplay.latitude ?? suggestion.averageCoordinate.latitude,
                                            longitude: topPickToDisplay.longitude ?? suggestion.averageCoordinate.longitude,
                                            photoReference: nil, fetchedReviews: [], overallRating: nil
                                        )
                                        Task { await doConfirmTopPick(suggestion, placeResult) } 
                                    },
                                    onSelectDifferentPlace: nil // This action is handled by OtherPlaceActionCardView.
                               )
                               .frame(width: 220)
                            }

                            // 2. Nearby Place Cards (from Google Places).
                            if let nearbyCandidates = fetchedNearbyPlaces {
                                ForEach(nearbyCandidates.prefix(2)) { nearbyPlace in // Show up to 2 nearby places.
                                    PlaceSuggestionCardView(
                                        placeName: nearbyPlace.displayName?.text ?? "Nearby Place",
                                        address: nearbyPlace.formattedAddress,
                                        confidence: nil, // Confidence not applicable here.
                                        isTopPick: false,
                                        onSelect: {
                                            Task { await doConfirmNearbyPlace(suggestion, nearbyPlace) }
                                        },
                                        onSelectDifferentPlace: nil 
                                    )
                                    .frame(width: 220)
                                }
                            }
                            
                            // 3. "It's another place" Card - always available for manual search.
                            OtherPlaceActionCardView {
                                doSelectDifferentPlace(suggestion)
                            }
                            .frame(width: 180) 
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            .layoutPriority(1) // Give more layout priority to the right side content.
        }
        .padding() 
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5)) 
        .cornerRadius(12)
        .shadow(radius: 3)
        .task { // Asynchronously load row-specific data when the view appears.
            await loadRowData()
        }
    }
    
    // Asynchronously loads detailed data for this specific suggestion row.
    // This includes the representative image, nearby places, and vision-based top pick.
    private func loadRowData() async {
        // Generate a cache key unique to this suggestion's content.
        let cacheKey = generateCacheKey(for: suggestion)

        // Try loading from cache first to avoid redundant network calls.
        if let cachedNearby = nearbyPlacesCacheService.get(forKey: cacheKey) {
            self.fetchedNearbyPlaces = cachedNearby
        }
        if let cachedVision = geminiVisionCacheService.get(forKey: cacheKey) {
            self.identifiedTopPick = cachedVision
        }

        // Load representative image if not already loaded.
        if representativeImage == nil {
            self.representativeImage = await suggestion.getRepresentativeThumbnail(targetSize: CGSize(width: 200, height: 200))
        }

        // If all critical data (nearby places, top pick, image) is loaded (from cache or previously), exit early.
        if fetchedNearbyPlaces != nil && identifiedTopPick != nil && representativeImage != nil {
            isLoadingRowData = false // Ensure loading state is off.
            return
        }

        // Prevent multiple concurrent loading tasks for the same row.
        guard !isLoadingRowData else { 
            return
        }

        isLoadingRowData = true
        rowError = nil // Reset error state for this loading attempt.

        // 1. Load Representative Image (ensure it's loaded before heavy processing, though likely handled above).
        if representativeImage == nil { // Redundant check for safety.
            self.representativeImage = await suggestion.getRepresentativeThumbnail(targetSize: CGSize(width: 200, height: 200))
        }

        // 2. Process Photos for Vision analysis (if top pick isn't cached and photos exist).
        if identifiedTopPick == nil && !suggestion.allPhotoAssetIdentifiersInCluster.isEmpty {
            // Process photos only if vision result is not cached/available and not already processed for this row.
            if self.processedPhotosForRow.isEmpty { // Avoid reprocessing if already done for this row instance.
                var tempProcessedPhotos: [ProcessedPhoto] = []
                let assetFetchResult = PHAsset.fetchAssets(withLocalIdentifiers: suggestion.allPhotoAssetIdentifiersInCluster, options: nil)
                var assetsToProcess: [PHAsset] = []
                assetFetchResult.enumerateObjects { (asset, _, _) in assetsToProcess.append(asset) }

                for asset in assetsToProcess {
                    do {
                        let processed = try await photoCacheService.photo(for: asset)
                        tempProcessedPhotos.append(processed)
                    } catch {
                        // Log error and continue; some photos might still be processed.
                        print("Error processing PHAsset \\(asset.localIdentifier) for row \\(suggestion.id) via cache: \\(error)")
                    }
                }
                self.processedPhotosForRow = tempProcessedPhotos
            }

            // If photo processing failed to yield any photos, set an error.
            // This might skip vision analysis but allow nearby places fetching.
            if self.processedPhotosForRow.isEmpty {
                if rowError == nil { rowError = "Could not process photos for this visit." }
            }
        } else if identifiedTopPick != nil {
             // Log if using cached vision result, helpful for debugging.
             print("Using cached/existing vision result for suggestion \\(suggestion.id)")
        }

        // 3. Fetch Nearby Places (if not already loaded from cache).
        if fetchedNearbyPlaces == nil {
            do {
                let nearby = try await placesService.searchNearbyPlacesNewAPI(
                    coordinate: suggestion.averageCoordinate,
                    radius: 75 // Search within a 75m radius.
                )
                self.fetchedNearbyPlaces = nearby
                nearbyPlacesCacheService.set(nearby, forKey: cacheKey) // Cache the result.
            } catch {
                print("Error fetching nearby places for row \\(suggestion.id): \\(error.localizedDescription)")
                if rowError == nil { rowError = "Could not load nearby places." } // Set error if not already set.
            }
        } else {
            // Log if using cached nearby places, helpful for debugging.
            print("Using cached/existing nearby places for suggestion \\(suggestion.id)")
        }

        // 4. Identify Location with Vision (if top pick isn't cached and photos were successfully processed).
        if identifiedTopPick == nil && !self.processedPhotosForRow.isEmpty {
            do {
                let visionResult = try await geminiVisionService.identifyLocationFromImages(
                    photos: self.processedPhotosForRow,
                    averageCoordinateHint: suggestion.averageCoordinate,
                    nearbyContextPlaces: self.fetchedNearbyPlaces // Provide nearby places as context for vision.
                )
                if let pickedPlace = visionResult.geminiPickedPlace {
                    self.identifiedTopPick = pickedPlace
                    geminiVisionCacheService.set(pickedPlace, forKey: cacheKey) // Cache the result.
                }
                // Note: visionResult.nearbyCandidates might differ from self.fetchedNearbyPlaces.
                // Currently, self.fetchedNearbyPlaces (from Google Places) are displayed. This could be revisited.
            } catch {
                print("Error identifying location with Vision for row \\(suggestion.id): \\(error.localizedDescription)")
                if rowError == nil { // Don't overwrite a more specific error (e.g., photo processing error).
                    rowError = "Could not get a specific suggestion from vision analysis."
                }
            }
        } else if identifiedTopPick == nil && self.processedPhotosForRow.isEmpty && !suggestion.allPhotoAssetIdentifiersInCluster.isEmpty {
             // This case implies photos were needed for vision, but processing them failed earlier.
             // rowError should ideally already be set from the photo processing block.
             if rowError == nil { rowError = "Photos unavailable for vision analysis." }
        }

        isLoadingRowData = false // Mark loading as complete.
    }

    // Helper to generate a unique cache key for a suggestion.
    // Uniqueness is based on the sorted set of photo identifiers and the formatted average coordinate.
    private func generateCacheKey(for suggestion: DraftVisitSuggestion) -> String {
        // Sort identifiers to ensure consistent key regardless of original order in the cluster.
        let sortedIdentifiersText = suggestion.allPhotoAssetIdentifiersInCluster.sorted().joined(separator: "|")
        let coordinateText = String(format: "%.6f,%.6f", suggestion.averageCoordinate.latitude, suggestion.averageCoordinate.longitude)
        return "\(sortedIdentifiersText)-\(coordinateText)"
    }
}

// A card view for displaying a place suggestion (either a top pick or a nearby place).
struct PlaceSuggestionCardView: View {
    let placeName: String
    let address: String?
    let confidence: Double? // Confidence score, typically for top picks from vision analysis.
    let isTopPick: Bool
    var onSelect: () -> Void // Action to perform when the card is tapped.
    var onSelectDifferentPlace: (() -> Void)? // Optional action (not used by this card directly).

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(placeName)
                .font(.headline) 
                .lineLimit(2)
            if let addr = address, !addr.isEmpty {
                Text(addr)
                    .font(.subheadline) 
                    .foregroundColor(.secondary)
                    .lineLimit(2) 
            }
            
            // Display confidence if it's a top pick and confidence is available.
            if isTopPick, let conf = confidence {
                Text(String(format: "Confidence: %.0f%%", conf * 100))
                    .font(.caption)
                    .foregroundColor(conf > 0.7 ? .green : .orange) // Color based on confidence level.
                    .padding(.top, 2)
            }
        }
        .padding(12) 
        .frame(maxWidth: .infinity, minHeight: 80) // Ensure a minimum tappable area.
        .background(Material.regularMaterial) // Adapts to light/dark mode.
        .cornerRadius(10)
        .contentShape(Rectangle()) // Define the tappable area.
        .onTapGesture {
            onSelect() 
        }
    }
}

// A card view that provides an action to search for a different place.
struct OtherPlaceActionCardView: View {
    var onSelectDifferentPlace: () -> Void // Action to trigger when tapped.

    var body: some View {
        VStack(alignment: .center, spacing: 4) { 
            Text("It's another place?")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.bottom, 2) 
            
            Text("Search location") 
                 .font(.caption)
                 .foregroundColor(.accentColor) // Use accent color for interactive text.
        }
        .padding(EdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8)) 
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .center) 
        .background(Material.regularMaterial)
        .cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectDifferentPlace()
        }
    }
}
