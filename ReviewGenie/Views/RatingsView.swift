import SwiftUI
import CoreLocation

struct RatingsView: View {
    @Binding var subRatingValues: [String: Double]
    @Binding var overallExperienceRating: Double
    @Binding var keyNotes: String
    let passedInselectedPlace: PlaceResult?
    let placesService: GooglePlacesServiceProtocol

    @State private var detailedPlaceForDisplay: PlaceResult? = nil
    @State private var isLoadingDetails: Bool = false

    @Binding var useGemini: Bool
    @Binding var useClaude: Bool
    @Binding var numberOfDraftsToRequest: Int
    @Binding var shouldIncludePhotosInPrompt: Bool
    let processedPhotos: [ProcessedPhoto]
    var onRemovePhoto: ((ProcessedPhoto) -> Void)?
    
    var body: some View {
        let currentPlaceToDisplay = detailedPlaceForDisplay ?? passedInselectedPlace

        // Determine if the place is a restaurant-like venue
        let restaurantTypes = ["restaurant", "cafe", "bakery", "bar", "meal_delivery", "meal_takeaway"]
        let isRestaurant = currentPlaceToDisplay?.types?.contains(where: { type in
            restaurantTypes.contains(where: type.lowercased().contains)
        }) ?? false

        // Determine if the place is a hotel-like venue
        let hotelTypes = ["hotel", "lodging", "motel", "resort", "hostel", "apartment_hotel", "guest_house"]
        let isHotel = currentPlaceToDisplay?.types?.contains(where: { type in
            hotelTypes.contains(where: type.lowercased().contains)
        }) ?? false

        ScrollView {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    if isLoadingDetails {
                        ProgressView()
                            .frame(maxWidth: 300, maxHeight: 250, alignment: .center)
                    } else if let place = currentPlaceToDisplay, let photoRef = place.photoReference,
                       let photoURL = placesService.photoURL(for: photoRef, maxWidth: 600) {
                        AsyncImage(url: photoURL) { image in
                            image.resizable()
                                 .aspectRatio(contentMode: .fit)
                                 .frame(maxWidth: 300, maxHeight: 250)
                                 .cornerRadius(8)
                                 .clipped()
                        } placeholder: {
                            Image(systemName: "photo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundColor(.gray)
                                .frame(width: 150, height: 150)
                        }
                    } else if currentPlaceToDisplay != nil {
                        Image(systemName: "mappin.and.ellipse")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundColor(.gray)
                            .frame(maxWidth: 200, maxHeight: 200)
                    }

                    if let place = currentPlaceToDisplay {
                        Text(place.name).font(.title3).fontWeight(.bold).padding(.top, 5)
                        Text(place.address).font(.caption).foregroundColor(.secondary)
                        if let rating = place.overallRating {
                            HStack { Text("Google Rating: "); Text(String(format: "%.1f", rating)); Image(systemName: "star.fill").foregroundColor(.orange) }.font(.caption).padding(.top, 1)
                        }
                    }
                }
                .frame(idealWidth: 280, maxWidth: 350)
                .padding(.trailing)

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledStarRating(title: "Rate Your Experience", rating: $overallExperienceRating, labelWidth: 100)
                        
                        if isRestaurant {
                            let foodBinding = Binding<Double>(
                                get: { subRatingValues["Food"] ?? 0.0 },
                                set: { subRatingValues["Food"] = $0 }
                            )
                            let serviceBinding = Binding<Double>(
                                get: { subRatingValues["Service"] ?? 0.0 },
                                set: { subRatingValues["Service"] = $0 }
                            )
                            let atmosphereBinding = Binding<Double>(
                                get: { subRatingValues["Atmosphere"] ?? 0.0 },
                                set: { subRatingValues["Atmosphere"] = $0 }
                            )

                            LabeledStarRating(title: "Food", rating: foodBinding, labelWidth: 100)
                            LabeledStarRating(title: "Service", rating: serviceBinding, labelWidth: 100)
                            LabeledStarRating(title: "Atmosphere", rating: atmosphereBinding, labelWidth: 100)
                        } else if isHotel {
                            let roomsBinding = Binding<Double>(
                                get: { subRatingValues["Rooms"] ?? 0.0 },
                                set: { subRatingValues["Rooms"] = $0 }
                            )
                            let serviceBinding = Binding<Double>(
                                get: { subRatingValues["Service"] ?? 0.0 },
                                set: { subRatingValues["Service"] = $0 }
                            )
                            let locationBinding = Binding<Double>(
                                get: { subRatingValues["Location"] ?? 0.0 },
                                set: { subRatingValues["Location"] = $0 }
                            )

                            LabeledStarRating(title: "Rooms", rating: roomsBinding, labelWidth: 100)
                            LabeledStarRating(title: "Service", rating: serviceBinding, labelWidth: 100)
                            LabeledStarRating(title: "Location", rating: locationBinding, labelWidth: 100)
                        }
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Generation Options")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .padding(.bottom, 5)

                            HStack(spacing: 15) {
                                Toggle("Gemini", isOn: $useGemini)
                                    .fixedSize()
                                Toggle("Claude", isOn: $useClaude)
                                    .fixedSize()
                                
                                Spacer()

                                Picker("", selection: $numberOfDraftsToRequest) {
                                    Text("1 Draft").tag(1)
                                    Text("2 Drafts").tag(2)
                                }
                                .pickerStyle(.menu)
                                .fixedSize()
                            }
                            Toggle("Include photos for review generation", isOn: $shouldIncludePhotosInPrompt)
                                .padding(.top, 5)
                        }
                        .padding(.vertical, 10)
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Key Notes for Your Review")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .padding(.bottom, 3)
                            Text("Optionally, add key notes about your experience (e.g., \"loved the chairs, river was cold, food salty\") to help guide the review generation.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 5)

                            TextEditor(text: $keyNotes)
                                .frame(minHeight: 80, maxHeight: 150)
                                .padding(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                                .background(Color(.textBackgroundColor))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .padding(.vertical, 10)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()

            if !processedPhotos.isEmpty {
                Section {
                    VStack(alignment: .leading) {
                        Text("Selected Photos (\(processedPhotos.count))")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .padding(.bottom, 3)
                        
                        PhotoCarouselWithRemoveView(
                            processedPhotos: processedPhotos,
                            onRemovePhoto: onRemovePhoto,
                            originalImagesDirectoryURL: FileUtils.getOriginalImageStorageDirectory()
                        )
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            if let placeToFetchDetailsFor = passedInselectedPlace {
                if detailedPlaceForDisplay?.id != placeToFetchDetailsFor.id || placeToFetchDetailsFor.photoReference == nil {
                    print("ℹ️ [RatingsView] Attempting to fetch full details for place: \(placeToFetchDetailsFor.name)")
                    isLoadingDetails = true
                    Task {
                        do {
                            let fetchedDetails = try await placesService.fetchPlaceDetails(placeID: placeToFetchDetailsFor.id)
                            await MainActor.run {
                                self.detailedPlaceForDisplay = fetchedDetails
                                self.isLoadingDetails = false
                                print("✅ [RatingsView] Successfully fetched details for: \(fetchedDetails.name)")
                            }
                        } catch {
                            await MainActor.run {
                                self.isLoadingDetails = false
                                print("⚠️ [RatingsView] Failed to fetch full details for \(placeToFetchDetailsFor.name): \(error.localizedDescription)")
                            }
                        }
                    }
                } else {
                    print("ℹ️ [RatingsView] Details for \(placeToFetchDetailsFor.name) likely already fetched or initial data sufficient.")
                }
            }
        }
        .onChange(of: processedPhotos) {
            // Placeholder for potential future logic when processedPhotos changes
        }
    }
}

struct LabeledStarRating: View {
    let title: String
    @Binding var rating: Double
    var starSize: CGFloat = 24
    var labelWidth: CGFloat?

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .frame(width: labelWidth, alignment: .leading)
            Spacer()
            StarRatingInputView(label: nil, rating: $rating, starSize: starSize, alignment: .leading)
        }
    }
}

struct StarRatingInputView: View {
    let label: String?
    @Binding var rating: Double
    var maxRating: Int = 5
    var starSize: CGFloat = 24
    var alignment: HorizontalAlignment = .leading
    var offImage: Image?
    var onImage: Image?
    var offColor: Color = .gray
    var onColor: Color = .yellow

    private func image(for number: Int) -> Image {
        if Double(number) > rating {
            return offImage ?? Image(systemName: "star")
        } else {
            return onImage ?? Image(systemName: "star.fill")
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if let labelText = label {
                Text(labelText)
                Spacer()
            }
            
            ForEach(1..<maxRating + 1, id: \.self) { number in
                image(for: number)
                    .resizable()
                    .scaledToFit()
                    .frame(width: starSize, height: starSize)
                    .foregroundColor(Double(number) > rating ? offColor : onColor)
                    .onTapGesture {
                        if rating == Double(number) {
                            // Intentionally not deselecting to 0 if tapped again,
                            // user can clear rating via other means if necessary.
                        } else {
                            rating = Double(number)
                        }
                    }
            }
            
            if label != nil {
                Text(String(format: "%.1f", rating))
                    .frame(width: 35, alignment: .trailing)
                    .font(.caption)
            }
        }
        .frame(maxWidth: label == nil ? .infinity : nil, alignment: label == nil ? .center : .leading)
        .font(.headline)
    }
}
