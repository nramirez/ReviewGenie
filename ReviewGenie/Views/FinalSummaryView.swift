import SwiftUI
import SwiftData
import PhotosUI
import CoreLocation
import ImageIO
import AppKit // Import AppKit for NSImage, used for operations like converting to Data.
import UniformTypeIdentifiers // For UTType, used in image type identification.
import Photos // For PHAsset, representing photo library assets.

// Helper struct to make `Image` identifiable for use in SwiftUI lists or ForEach loops,
// associating it with a `ProcessedPhoto.ID`.
private struct IdentifiableImage: Identifiable {
    let id: ProcessedPhoto.ID
    let image: Image
}

/// A view that displays a summary of the review details, including place information,
/// ratings, review text, and photos, allowing for final confirmation and editing of the review text.
struct FinalSummaryView: View {
    let selectedPlace: PlaceResult?
    @Binding var finalReviewText: String? // Binding to allow editing of the final review text.
    let processedPhotos: [ProcessedPhoto] // Photos that have been processed and are ready for display/upload.
    let overallRating: Double
    let subRatingValues: [String: Double] // Dictionary of sub-ratings (e.g., "Food", "Service").
    var onRemovePhoto: ((ProcessedPhoto) -> Void)? // Callback function to handle photo removal.

    var body: some View {
        ScrollView { // Enables scrolling for content that might exceed screen height.
            VStack(alignment: .leading, spacing: 15) {
                Text("Confirm Your Review")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.bottom, 5)

                // MARK: - Place Information
                if let place = selectedPlace {
                    VStack(alignment: .leading) {
                        Text(place.name).font(.headline)
                        Text(place.address).font(.subheadline).foregroundColor(.gray)
                    }
                    Divider()
                }

                // MARK: - Ratings Display
                VStack(alignment: .leading) {
                    Text("Your Ratings").font(.headline)
                    RatingDisplayRow(label: "Overall", rating: overallRating)
                    
                    // Display sub-ratings if they exist and have a value greater than 0.
                    if let foodRating = subRatingValues["Food"], foodRating > 0 {
                        RatingDisplayRow(label: "Food", rating: foodRating)
                    }
                    if let serviceRating = subRatingValues["Service"], serviceRating > 0 {
                        RatingDisplayRow(label: "Service", rating: serviceRating)
                    }
                    if let atmosphereRating = subRatingValues["Atmosphere"], atmosphereRating > 0 {
                        RatingDisplayRow(label: "Atmosphere", rating: atmosphereRating)
                    }
                }
                Divider()

                // MARK: - Review Text Editor
                VStack(alignment: .leading) {
                    Text("Your Review").font(.headline)
                    
                    if let reviewBinding = Binding($finalReviewText) {
                         TextEditor(text: reviewBinding)
                            .frame(minHeight: 150, maxHeight: 300) // Set min/max height for the text editor.
                            .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)) // Standardized internal padding.
                            .foregroundColor(Color(nsColor: .labelColor)) // Ensure text color adapts to system theme.
                            .background(Color(nsColor: .textBackgroundColor)) // Ensure background adapts to system theme.
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1) // Add a subtle border.
                            )
                    } else {
                        Text("No review draft selected.")
                            .foregroundColor(.gray)
                    }
                }
                Divider()

                // MARK: - Photos Display
                if !processedPhotos.isEmpty {
                    Text("Your Photos (\(processedPhotos.count))").font(.headline)
                    PhotoCarouselWithRemoveView(
                        processedPhotos: processedPhotos,
                        onRemovePhoto: onRemovePhoto,
                        originalImagesDirectoryURL: FileUtils.getOriginalImageStorageDirectory()
                    )
                }
                // Note: The redundant 'else if !processedPhotos.isEmpty' block has been removed.
                // If a "No photos" or "Loading photos..." message is desired when processedPhotos is empty,
                // it should be handled with a simple 'else' or a different state management approach.

            }
            .padding() // Add padding around the entire VStack content.
        }
        .onAppear {
            // Actions to perform when the view appears, if any.
        }
        .onChange(of: processedPhotos) { 
            // Actions to perform when the processedPhotos array changes, if any.
        }
    }
}

/// A view component to display a single rating category with a label,
/// star representation, and numeric value.
struct RatingDisplayRow: View {
    let label: String
    let rating: Double
    
    // Star appearance constants
    var maxRating: Int = 5
    var starSize: CGFloat = 16
    var onColor: Color = .orange
    var offColor: Color = .gray

    var body: some View {
        HStack {
            Text(label + ":")
                .frame(width: 80, alignment: .leading) // Align labels for consistent layout.
                
            // Draw stars based on the rating value.
            ForEach(1..<maxRating + 1, id: \.self) { number in
                Image(systemName: Double(number) <= rating ? "star.fill" : "star")
                    .resizable()
                    .scaledToFit()
                    .frame(width: starSize, height: starSize)
                    .foregroundColor(Double(number) <= rating ? onColor : offColor)
            }
            
            Spacer() // Pushes the numeric rating to the trailing edge.

            Text(String(format: "%.1f", rating))
                .font(.system(.body, design: .monospaced)) // Monospaced font for aligned numeric display.
        }
    }
}
