import SwiftUI
import SwiftData
import PhotosUI
import CoreLocation
import ImageIO
import AppKit // Import AppKit for NSImage for macOS specific image handling
import UniformTypeIdentifiers // For UTType.jpeg, used for defining file types
import Photos // For PHAsset, used for interacting with the Photo library


// MARK: Home

/// Represents the different states the detail view can be in.
enum DetailViewState: Hashable {
    case emptyPlaceholder // Default state, showing introductory options.
    case showingVisit(VisitRecord) // Displaying details of an existing visit.
    case creatingNewReview // User is creating a new review from scratch.
    case findingPastVisits // User is in the process of finding past visits from photos.
    case creatingReviewFromSuggestion(prefillData: (place: PlaceResult, photos: [ProcessedPhoto], date: Date)) // Creating a review based on a suggestion from past visit analysis.
    case searchingForPlaceFromPastVisit(photos: [ProcessedPhoto], date: Date, averageCoordinate: CLLocationCoordinate2D) // User is searching for a place after analyzing past visit photos.
    case importingGoogleReviews // User is importing reviews from Google.

    // Custom hashing for identifiable states, especially those with associated values.
    func hash(into hasher: inout Hasher) {
        switch self {
        case .emptyPlaceholder:
            hasher.combine(0) // Unique integer for this case
        case .showingVisit(let visit):
            hasher.combine(1)
            hasher.combine(visit.id) // Include visit ID for uniqueness
        case .creatingNewReview:
            hasher.combine(2)
        case .findingPastVisits:
            hasher.combine(3)
        case .creatingReviewFromSuggestion(let prefillData):
            hasher.combine(4)
            hasher.combine(prefillData.place.id) // Include place ID
            prefillData.photos.forEach { hasher.combine($0.id) } // Include photo IDs
            hasher.combine(prefillData.date) // Include date
        case .searchingForPlaceFromPastVisit(let photos, let date, let averageCoordinate):
            hasher.combine(5)
            photos.forEach { hasher.combine($0.id) } // Include photo IDs
            hasher.combine(date) // Include date
            hasher.combine(averageCoordinate.latitude) // Include coordinate details
            hasher.combine(averageCoordinate.longitude)
        case .importingGoogleReviews:
            hasher.combine(6)
        }
    }

    // Custom equality check for states, especially those with associated values.
    static func == (lhs: DetailViewState, rhs: DetailViewState) -> Bool {
        switch (lhs, rhs) {
        case (.emptyPlaceholder, .emptyPlaceholder):
            return true
        case (.showingVisit(let lVisit), .showingVisit(let rVisit)):
            return lVisit.id == rVisit.id
        case (.creatingNewReview, .creatingNewReview):
            return true
        case (.findingPastVisits, .findingPastVisits):
            return true
        case (.creatingReviewFromSuggestion(let lPrefillData), .creatingReviewFromSuggestion(let rPrefillData)):
            // Compare all components of prefillData for equality
            return lPrefillData.place.id == rPrefillData.place.id &&
                   lPrefillData.photos.map { $0.id } == rPrefillData.photos.map { $0.id } &&
                   lPrefillData.date == rPrefillData.date
        case (.searchingForPlaceFromPastVisit(let lPhotos, let lDate, let lCoord), .searchingForPlaceFromPastVisit(let rPhotos, let rDate, let rCoord)):
            // Compare all components for equality
            return lPhotos.map { $0.id } == rPhotos.map { $0.id } &&
                   lDate == rDate &&
                   lCoord.latitude == rCoord.latitude &&
                   lCoord.longitude == rCoord.longitude
        case (.importingGoogleReviews, .importingGoogleReviews):
            return true
        default:
            // If cases don't match, they are not equal
            return false
        }
    }
}

/// The main view of the application, displaying a list of visits and a detail view.
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext // SwiftData model context for data operations.
    @Query(sort: [SortDescriptor<VisitRecord>(\.date, order: .reverse)]) private var visits: [VisitRecord] // Fetches all visits, sorted by date descending.
    @State private var detailState: DetailViewState = .emptyPlaceholder // Manages the current state of the detail view.
    @State private var listSelection: VisitRecord.ID? // Tracks the selected visit in the list.
    @State private var newlyAddedVisitID: VisitRecord.ID? // Temporarily stores the ID of a newly added visit for highlighting.
    @State private var previousVisitCount: Int = 0 // Used to detect when new visits are added.
    
    var body: some View {
        NavigationSplitView {
            // Sidebar: List of visits
            ScrollViewReader { proxy in // Allows programmatic scrolling of the list.
                Group {
                    if visits.isEmpty {
                        // Displayed when there are no reviews.
                        ContentUnavailableView {
                            Label("No Reviews Yet", systemImage: "doc.text.magnifyingglass")
                        } description: {
                            Text("Tap the '+' button to add your first review.")
                        } actions: {
                            Button {
                                detailState = .creatingNewReview // Transition to new review creation.
                            } label: {
                                Label("Add New Review", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.accentColor)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // List of existing visits.
                        List(selection: $listSelection) {
                            ForEach(visits) { visit in
                                NavigationLink(value: visit.id) { // NavigationLink triggers selection change.
                                    VisitRowView(visit: visit, isNewlyAdded: visit.id == newlyAddedVisitID)
                                }
                            }
                            .onDelete(perform: deleteVisits) // Enables swipe-to-delete.
                        }
                        .listStyle(.sidebar) // Standard sidebar list style.
                    }
                }
                .onAppear {
                    // Initialize previousVisitCount when the view appears.
                    previousVisitCount = visits.count
                }
                .onChange(of: visits) { oldVisits, newVisits in
                    // Handles actions when the visits array changes (e.g., a new visit is added).
                    // Specifically, scrolls to and highlights a newly added visit.
                    if newVisits.count > previousVisitCount && listSelection == nil && (detailState == .emptyPlaceholder || detailState == .findingPastVisits) {
                        if let newVisit = newVisits.first { // Assumes new visit is at the top due to sorting.
                            newlyAddedVisitID = newVisit.id
                            withAnimation {
                                proxy.scrollTo(newVisit.id, anchor: .center) // Scroll to the new visit.
                            }
                            // Remove highlight after a delay.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation {
                                    newlyAddedVisitID = nil
                                }
                            }
                        }
                    }
                    previousVisitCount = newVisits.count // Update count for next change detection.
                }
            }
        } detail: {
            // Detail pane: Content changes based on `detailState`.
            detailView(for: detailState)
        }
        .toolbar {
            // Toolbar item for creating a new review.
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    detailState = .creatingNewReview
                    listSelection = nil // Deselect any item in the list.
                }) {
                    Label("New Review", systemImage: "square.and.pencil")
                }
                .tint(.accentColor)
            }
        }
        .onChange(of: listSelection) { oldValue, newValue in
            // Updates the detail view when the list selection changes.
            if let visitId = newValue,
               let selectedVisit = visits.first(where: { $0.id == visitId }) {
                detailState = .showingVisit(selectedVisit) // Show details of the selected visit.
            } else if newValue == nil && detailState != .creatingNewReview && detailState != .importingGoogleReviews && detailState != .findingPastVisits {
                // If selection is cleared and not in a creation/import flow, show placeholder.
                detailState = .emptyPlaceholder
            }
        }
    }
    
    /// Builds the appropriate detail view based on the current `DetailViewState`.
    @ViewBuilder
    private func detailView(for state: DetailViewState) -> some View {
        switch state {
        case .emptyPlaceholder:
            emptyPlaceholderView()
        case .showingVisit(let visit):
            showingVisitView(visit: visit)
        case .creatingNewReview:
            creatingNewReviewView()
        case .findingPastVisits:
            findingPastVisitsView()
        case .creatingReviewFromSuggestion(let prefillData):
            creatingReviewFromSuggestionView(prefillData: prefillData)
        case .searchingForPlaceFromPastVisit(let photos, let date, let averageCoordinate):
            searchingForPlaceFromPastVisitView(photos: photos, date: date, averageCoordinate: averageCoordinate)
        case .importingGoogleReviews:
            importingGoogleReviewsView()
        }
    }

    /// View displayed when no specific item is selected or action is in progress.
    private func emptyPlaceholderView() -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image("ReviewGenieLogo") // App logo.
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300)

            // Button to add a new review.
            Button {
                detailState = .creatingNewReview
                listSelection = nil
            } label: {
                Label("Add New Review", systemImage: "plus")
                    .font(.headline)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                    .frame(minWidth: 250)
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)

            // Button to import Google reviews.
            Button {
                detailState = .importingGoogleReviews
                listSelection = nil
            } label: {
                Label("Import Google Reviews", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                    .frame(minWidth: 250)
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)

            // Button to find past visits.
            Button {
                detailState = .findingPastVisits
                listSelection = nil
            } label: {
                Label("Find Past Visits", systemImage: "calendar.badge.clock")
                    .font(.headline)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                    .frame(minWidth: 250)
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
            
            Spacer()
        }
        .padding(40)
        .multilineTextAlignment(.center)
    }

    /// View for displaying the details of a selected visit.
    private func showingVisitView(visit: VisitRecord) -> some View {
        VisitDetailView(visit: visit,
                        onGoHome: { // Callback to return to the empty placeholder state.
                            detailState = .emptyPlaceholder
                            listSelection = nil
                        }
        )
    }

    /// View for creating a new review from scratch.
    private func creatingNewReviewView() -> some View {
        NewEntryView(
            onSave: { newVisitUUID in // Callback when a new review is saved.
                self.listSelection = newVisitUUID // Select the newly created visit in the list.
            },
            onCancel: { // Callback if the user cancels review creation.
                detailState = .emptyPlaceholder
                listSelection = nil
            },
            prefillData: nil // No prefilled data for a new review.
        )
    }

    /// View for the "Find Past Visits" feature.
    private func findingPastVisitsView() -> some View {
        FindPastVisitsView(
            onCancel: { // Callback if the user cancels.
                detailState = .emptyPlaceholder
                listSelection = nil
            },
            onStartReview: { place, photos, date in // Callback to start a review from a suggestion.
                detailState = .creatingReviewFromSuggestion(prefillData: (place: place, photos: photos, date: date))
                listSelection = nil
            },
            onStartSearchForNewPlace: { photos, date, averageCoordinate in // Callback to search for a place based on photo data.
                detailState = .searchingForPlaceFromPastVisit(photos: photos, date: date, averageCoordinate: averageCoordinate)
                listSelection = nil
            }
        )
    }

    /// View for creating a review prefilled with data from a past visit suggestion.
    private func creatingReviewFromSuggestionView(prefillData: (place: PlaceResult, photos: [ProcessedPhoto], date: Date)) -> some View {
        NewEntryView(
            onSave: { newVisitUUID in // Callback when the review is saved.
                self.listSelection = newVisitUUID // Select the new visit.
            },
            onCancel: { // Callback if the user cancels.
                detailState = .findingPastVisits // Return to the "Find Past Visits" state.
                listSelection = nil
            },
            prefillData: prefillData // Pass the prefill data to the NewEntryView.
        )
    }

    /// View for creating a review when searching for a place based on past visit photo data.
    private func searchingForPlaceFromPastVisitView(photos: [ProcessedPhoto], date: Date, averageCoordinate: CLLocationCoordinate2D) -> some View {
        // Create a placeholder PlaceResult to indicate a search is in progress.
        let searchPlaceholderPlace = PlaceResult(
            id: "SEARCH_INITIATED_FROM_PAST_VISIT", // Unique ID for this placeholder.
            name: "Searching...",
            address: "Nearby: \(String(format: "%.4f, %.4f", averageCoordinate.latitude, averageCoordinate.longitude))",
            latitude: averageCoordinate.latitude,
            longitude: averageCoordinate.longitude,
            photoReference: nil,
            fetchedReviews: [],
            overallRating: nil
        )

        return NewEntryView(
            onSave: { newVisitUUID in // Callback when the review is saved.
                self.listSelection = newVisitUUID // Select the new visit.
            },
            onCancel: { // Callback if the user cancels.
                detailState = .findingPastVisits // Return to the "Find Past Visits" state.
                listSelection = nil
            },
            prefillData: (place: searchPlaceholderPlace, photos: photos, date: date) // Pass prefill data including the search placeholder.
        )
    }

    /// View for importing Google reviews.
    private func importingGoogleReviewsView() -> some View {
        ImportReviewsView(
            onCompletion: { // Callback when import is complete.
                detailState = .emptyPlaceholder
                listSelection = nil
            },
            onCancel: { // Callback if the user cancels import.
                detailState = .emptyPlaceholder
                listSelection = nil
            }
        )
    }

    /// Deletes visits from the model context at the specified offsets.
    private func deleteVisits(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(visits[index])
        }
        // If the currently selected visit was deleted, clear the selection.
        if let currentSelection = listSelection, !visits.contains(where: { $0.id == currentSelection }) {
            listSelection = nil
        }
    }
}

/// Represents a single row in the list of visits.
struct VisitRowView: View {
    let visit: VisitRecord // The visit data to display.
    let isNewlyAdded: Bool // Flag to indicate if this row was just added, for highlighting.
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(visit.placeName)
                    .font(.headline)
                Spacer()
                // Display "IMPORTED" badge if the review was imported.
                if visit.reviewOrigin == .imported {
                    Text("IMPORTED")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }
            Text(visit.address)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            // Display sub-ratings if available.
            HStack(spacing: 12) {
                if let subRatings = visit.subRatings {
                    ForEach(subRatings.filter { ($0.rating ?? 0) > 0 && $0.question != nil }, id: \.question!) { subRating in
                        if let question = subRating.question, let ratingValue = subRating.rating {
                            // Determine icon based on sub-rating question.
                            let iconName: String = {
                                switch question.lowercased() {
                                    case "food": return "fork.knife"
                                    case "service": return "person.fill"
                                    case "atmosphere": return "bubbles.and.sparkles"
                                    case "rooms": return "bed.double.fill"
                                    case "location": return "mappin.and.ellipse"
                                    default: return "star" // Default icon.
                                }
                            }()
                            Label("\(ratingValue)", systemImage: iconName)
                        }
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        // Apply a temporary background highlight if the visit was newly added.
        .background(isNewlyAdded ? Color(red: 0.10, green: 0.30, blue: 0.65).opacity(0.2) : Color.clear)
        .animation(.easeInOut, value: isNewlyAdded) // Animate the background change.
    }
}

/// Extension to `PlaceResult` to provide a convenient `CLLocationCoordinate2D`.
extension PlaceResult {
    /// Computed property to get `CLLocationCoordinate2D` from latitude and longitude.
    /// Returns `nil` if latitude and longitude are both 0.0 (often indicating no valid coordinate).
    var coordinate: CLLocationCoordinate2D? {
        if self.latitude != 0.0 || self.longitude != 0.0 {
            return CLLocationCoordinate2D(latitude: self.latitude, longitude: self.longitude)
        }
        return nil
    }
}

