import SwiftUI
import CoreLocation

// Note: This view relies on PlaceResult, GooglePlacesServiceProtocol,
// GeminiVisionService.IdentifiedPlaceDetails, and GooglePlacesAPIService.NearbyPlaceInternal.
// Ensure these types are accessible.

struct PlaceSearchView: View {
    @Binding var searchText: String
    @Binding var selectedPlace: PlaceResult?
    let placesService: GooglePlacesServiceProtocol // Usually GooglePlacesAPIService instance
    let photoTakenCoordinate: CLLocationCoordinate2D?
    
    let geminiSuggestedTopPick: GeminiVisionService.IdentifiedPlaceDetails?
    let nearbyPlaceCandidates: [GooglePlacesAPIService.NearbyPlaceInternal]?
    let isIdentifyingLocation: Bool
    let locationIdentificationError: String?
    
    var onPlaceSelected: () -> Void

    @State private var searchSuggestions: [PlaceResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var searchTask: Task<Void, Error>? = nil
    @State private var debounceTimer: Timer? = nil

    var body: some View {
        VStack(alignment: .leading) {
            if isIdentifyingLocation {
                HStack {
                    ProgressView()
                    Text("Identifying location from photos...")
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .center)
            } else if let error = locationIdentificationError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.orange)
                        .font(.caption)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            } else if let suggestion = geminiSuggestedTopPick, let suggestedName = suggestion.name, !suggestedName.isEmpty {
                VStack(alignment: .leading) {
                    Text("Suggested Place (from Photos):")
                        .font(.headline)
                        .padding(.bottom, 2)
                    
                    HStack {
                        Image(systemName: "photo.stack.fill") 
                            .font(.title)
                            .foregroundColor(.accentColor)
                            .frame(width: 50, height: 50)

                        VStack(alignment: .leading) {
                            Text(suggestedName).bold()
                            if let suggestedAddress = suggestion.address, !suggestedAddress.isEmpty {
                                Text(suggestedAddress).font(.caption).foregroundColor(.secondary)
                            }
                            if let confidence = suggestion.confidence {
                                Text(String(format: "Confidence: %.0f%%", confidence * 100))
                                    .font(.caption2)
                                    .foregroundColor(confidence > 0.7 ? .green : .orange)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(10)
                    .contentShape(Rectangle()) 
                    .onTapGesture {
                        let placeResult = PlaceResult(
                            id: suggestion.placeID ?? UUID().uuidString, 
                            name: suggestedName,
                            address: suggestion.address ?? "Address not available",
                            latitude: suggestion.latitude ?? 0.0,
                            longitude: suggestion.longitude ?? 0.0,
                            photoReference: nil, 
                            fetchedReviews: [],  
                            overallRating: nil 
                        )
                        searchText = suggestedName 
                        selectedPlace = placeResult
                        searchSuggestions = [] 
                        onPlaceSelected() 
                    }
                    if let reasoning = suggestion.reasoning, !reasoning.isEmpty {
                        Text("Reasoning: \(reasoning)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .padding(.top, 1)
                    }
                }
                .padding(.bottom) 
                Divider()
            }

            if let candidates = nearbyPlaceCandidates, !candidates.isEmpty {
                VStack(alignment: .leading) {
                    Text("Other Nearby Options:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.leading)
                        .padding(.top, 5)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(candidates) { place in // place is GooglePlacesAPIService.NearbyPlaceInternal
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(place.displayName?.text ?? "Unknown Place")
                                        .font(.caption.bold())
                                        .lineLimit(2)
                                    if let address = place.formattedAddress, !address.isEmpty {
                                        Text(address)
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(8)
                                .frame(width: 150, height: 70) 
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    let placeResult = PlaceResult(
                                        id: place.id ?? UUID().uuidString,
                                        name: place.displayName?.text ?? "Unknown Name",
                                        address: place.formattedAddress ?? "Address not available",
                                        latitude: 0.0, 
                                        longitude: 0.0,
                                        photoReference: nil,
                                        fetchedReviews: [],
                                        overallRating: nil
                                    )
                                    searchText = place.displayName?.text ?? "Unknown Name"
                                    selectedPlace = placeResult
                                    searchSuggestions = [] 
                                    onPlaceSelected()
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 10) 
                    }
                }
                .padding(.bottom, 5) 
            }

            Text("Search for a Place")
                .font(.title2)
                .padding(.bottom, 5)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Enter place name or address", text: $searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: searchText) { oldValue, newValue in
                        if newValue.isEmpty && selectedPlace != nil {
                            selectedPlace = nil
                            searchSuggestions = [] 
                            errorMessage = nil
                            isLoading = false
                        }
                        
                        debounceTimer?.invalidate()
                        if !newValue.isEmpty && (selectedPlace == nil || newValue != selectedPlace?.name) {
                            isLoading = true 
                            errorMessage = nil
                            debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                                searchTask?.cancel() 
                                searchTask = Task {
                                    await search(for: newValue)
                                }
                            }
                        } else if newValue.isEmpty {
                            searchSuggestions = []
                            isLoading = false
                            errorMessage = nil
                        }
                    }
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )

            if isLoading {
                ProgressView()
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            } else if !searchSuggestions.isEmpty && selectedPlace == nil {
                List(searchSuggestions) { place in
                    HStack {
                        if let photoRef = place.photoReference,
                           let photoURL = placesService.photoURL(for: photoRef, maxWidth: 100) {
                            AsyncImage(url: photoURL) { image in
                                image.resizable()
                                     .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(.trailing, 5)
                        } else {
                            Image(systemName: "mappin.and.ellipse")
                                .frame(width: 40, height: 40)
                                .padding(.trailing, 5)
                        }
                        VStack(alignment: .leading) {
                            Text(place.name).bold()
                            Text(place.address).font(.caption)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        searchText = place.name 
                        selectedPlace = place
                        searchSuggestions = [] 
                        isLoading = false
                        onPlaceSelected()
                    }
                }
                .listStyle(.plain)
                .frame(maxHeight: 200) 
            } else if selectedPlace != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected Place:").font(.headline).padding(.top)
                    HStack {
                         if let photoRef = selectedPlace?.photoReference,
                           let photoURL = placesService.photoURL(for: photoRef, maxWidth: 200) {
                            AsyncImage(url: photoURL) { image in
                                image.resizable()
                                     .aspectRatio(contentMode: .fit)
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.trailing, 10)
                        } else {
                            Image(systemName: "mappin.and.ellipse")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 60, height: 60)
                                .padding(.trailing, 10)
                                .foregroundColor(.secondary)
                        }
                        VStack(alignment: .leading) {
                            Text(selectedPlace!.name).font(.title3).bold()
                            Text(selectedPlace!.address).font(.subheadline).foregroundColor(.secondary)
                             if let rating = selectedPlace?.overallRating {
                                HStack {
                                    Image(systemName: "star.fill").foregroundColor(.yellow)
                                    Text(String(format: "%.1f", rating))
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                    if let fetchedReviews = selectedPlace?.fetchedReviews, !fetchedReviews.isEmpty {
                        Text("Recent Reviews:").font(.caption).bold().padding(.top, 5)
                        ForEach(fetchedReviews.prefix(2)) { review in 
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\"\(review.text.prefix(100))...\"").font(.caption).italic()
                                Text("- \(review.authorName), Rated: \(review.rating)/5")
                                    .font(.caption2).foregroundColor(.gray)
                            }
                            .padding(.bottom, 3)
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(10)
            }
            Spacer() 
        }
        .padding()
        .onDisappear {
            searchTask?.cancel()
            debounceTimer?.invalidate()
        }
    }

    private func search(for query: String) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            await MainActor.run {
                self.searchSuggestions = []
                self.isLoading = false
                self.errorMessage = nil
            }
            return
        }

        if let selected = selectedPlace, selected.name == trimmedQuery {
            await MainActor.run { isLoading = false } 
            return
        }
        
        do {
            let results = try await placesService.searchPlaces(query: trimmedQuery) 
            if Task.isCancelled { return }

            await MainActor.run {
                self.searchSuggestions = results
                self.isLoading = false
                if results.isEmpty {
                    self.errorMessage = "No results found for \"\(trimmedQuery)\"."
                } else {
                    self.errorMessage = nil 
                }
            }
        } catch is CancellationError {
            // Task was cancelled, no need to update UI or log an error.
        } catch {
            if Task.isCancelled { return } 
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = "Search error: \(error.localizedDescription)"
                print("Detailed search error in PlaceSearchView.search: \(error)")
            }
        }
    }
} 