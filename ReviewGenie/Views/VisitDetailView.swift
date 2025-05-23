import SwiftUI
import SwiftData

struct VisitDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var visit: VisitRecord
    @State private var isEditing = false
    @State private var editedReview: String
    var onGoHome: (() -> Void)?
    
    private var photosForCarousel: [ProcessedPhoto] {
        visit.imageReferences?.map { imageRef -> ProcessedPhoto in
            // Create ProcessedPhoto objects from ImageFileReference
            return ProcessedPhoto(
                originalItemIdentifier: nil, // Not available directly from ImageFileReference
                optimizedFileName: imageRef.optimizedFileName, 
                originalFileName: imageRef.originalFileName,
                metadata: nil, // Not available
                coordinate: nil // Not available
            )
        } ?? []
    }
    
    init(visit: VisitRecord, onGoHome: (() -> Void)? = nil) {
        self.visit = visit
        _editedReview = State(initialValue: visit.selectedReview ?? "")
        self.onGoHome = onGoHome
    }
    
    var body: some View {
        ScrollView {
            detailContent
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let onGoHome = onGoHome {
                    Button {
                        onGoHome()
                    } label: {
                        Label("Home", systemImage: "house.fill")
                    }
                }
            }
        }
        .padding()
        .navigationTitle(visit.placeName)
        .onAppear {
        }
        .onChange(of: visit.id) {
            // The photosForCarousel computed property will update automatically when visit changes.
        }
    }
    
    @ViewBuilder
    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text(visit.placeName)
                    .font(.title)
                Text(visit.address)
                    .foregroundStyle(.secondary)
                Text(visit.date.formatted(date: .long, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            
            // Ratings - Conditionally display
            HStack(spacing: 15) {
                // Always show Overall Experience
                RatingView(title: "Overall", rating: visit.overallExperienceRating, icon: "trophy.fill")
                
                if let subRatings = visit.subRatings {
                    ForEach(subRatings.filter { $0.rating ?? 0 > 0 }, id: \.question) { subRating in
                        let iconName = getIconName(for: subRating.question?.lowercased() ?? "")
                        RatingView(title: subRating.question ?? "Rating", rating: Double(subRating.rating ?? 0), icon: iconName)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity) // Ensure HStack takes available width for centering
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(10)
            .padding(.horizontal)
            
            // Display Attached Photos - Now using PhotoCarouselWithRemoveView
            if !photosForCarousel.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Attached Photos")
                        .font(.headline)
                    
                    PhotoCarouselWithRemoveView(
                        processedPhotos: photosForCarousel, 
                        onRemovePhoto: { photoToRemove in
                            // Remove the corresponding ImageFileReference from visit.imageReferences
                            // We can match based on originalFileName, assuming it's unique enough per visit for this purpose
                            visit.imageReferences?.removeAll { $0.originalFileName == photoToRemove.originalFileName }
                        },
                        originalImagesDirectoryURL: FileUtils.getOriginalImageStorageDirectory()
                    )
                }
                .padding(.horizontal)
            } else if !(visit.imageReferences?.isEmpty ?? true) { // Check imageReferences here
                HStack {
                    Text("Attached Photos:")
                        .font(.headline)
                    Spacer()
                    Text("Error loading photos or no photos found.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding()
            } else {
                // No photos were ever attached
                HStack {
                    Text("Photos Used for Review:")
                        .font(.headline)
                    Spacer()
                    Text("0")
                        .font(.body)
                }
                .padding()
            }
            
            // Review
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Review")
                        .font(.title2)
                    Spacer()
                    Button(isEditing ? "Done" : "Edit") {
                        if isEditing {
                            visit.selectedReview = editedReview
                        }
                        isEditing.toggle()
                    }
                    if !isEditing {
                        Button {
                            if let review = visit.selectedReview {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(review, forType: .string)
                            }
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .disabled(visit.selectedReview == nil)
                        
                        // "Post to Google Maps" Button
                        if let placeId = visit.placeID, !placeId.isEmpty, 
                           let reviewText = visit.selectedReview, !reviewText.isEmpty {
                            Button {
                                // No longer copying photos to a separate export folder for this flow
                                let urlString = "https://search.google.com/local/writereview?placeid=\(placeId)"
                                if let url = URL(string: urlString) {
                                    let pasteboard = NSPasteboard.general
                                    pasteboard.clearContents()
                                    pasteboard.setString(reviewText, forType: .string)
                                    print("Review text copied to clipboard.")
                                    
                                    NSWorkspace.shared.open(url) // Open Google Maps link directly
                                } else {
                                    print("Error: Could not create URL for Google Maps.")
                                    // TODO: Show error alert to user
                                }
                            } label: {
                                Label("Post to Google Maps", systemImage: "mappin.and.ellipse.circle.fill")
                            }
                        }
                    }
                }
                
                if isEditing {
                    TextEditor(text: $editedReview)
                        .frame(minHeight: 200)
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                } else {
                    Text(visit.selectedReview ?? "No review selected")
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .padding()
            
            // Generated Drafts
            if !visit.generatedDrafts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Generated Drafts")
                        .font(.title2)
                    
                    ForEach(visit.generatedDrafts, id: \.self) { draft in
                        Text(draft)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
    }
    
    private func getIconName(for category: String) -> String {
        switch category {
        case "food":
            return "fork.knife"
        case "service":
            return "person.fill"
        case "atmosphere":
            return "bubbles.and.sparkles"
        case "rooms":
            return "bed.double.fill"
        case "location":
            return "mappin.and.ellipse"
        default:
            return "star"
        }
    }
}

struct RatingView: View {
    let title: String
    let rating: Double
    let icon: String
    
    var body: some View {
        VStack {
            Label(title, systemImage: icon)
                .font(.caption)
            Text(String(format: "%.1f", rating))
                .font(.title2)
                .bold()
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: VisitRecord.self, configurations: config)
    
    // Using minimal placeholder data for the preview
    let placeholderVisit = VisitRecord(
        placeID: "placeholderID",
        placeName: "Placeholder Place",
        address: "No Address",
        latitude: 0.0,
        longitude: 0.0,
        overallExperienceRating: 0,
        numberOfPhotosUsed: 0,
        generatedDrafts: [],
        selectedReview: nil
    )
    
    VisitDetailView(visit: placeholderVisit, onGoHome: { print("Preview Home Tapped") })
        .modelContainer(container)
} 