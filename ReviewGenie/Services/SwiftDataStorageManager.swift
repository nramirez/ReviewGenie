import Foundation
import SwiftData

// SwiftData implementation of the StorageManagerProtocol.
// This class handles all data persistence operations for VisitRecord objects using SwiftData.
class SwiftDataStorageManager: StorageManagerProtocol {
    private let context: ModelContext // The SwiftData model context for database operations.

    /// Initializes the storage manager with a given model context.
    /// - Parameter context: The `ModelContext` to be used for data operations.
    init(context: ModelContext) {
        self.context = context
    }

    /// Saves an imported review to the SwiftData store.
    /// Operations are performed on the main actor to ensure thread safety with the UI.
    /// - Parameter review: The `VisitRecord` object to save.
    /// - Throws: An error if the save operation fails (though explicit save is currently commented out).
    func saveImportedReview(_ review: VisitRecord) async throws {
        // Ensure context operations are on the main thread.
        await MainActor.run {
            context.insert(review)
            // SwiftData typically auto-saves. Explicit save can be added if specific error handling for save is needed.
            print("Attempting save for review ID \(review.id) with origin \(review.reviewOrigin.rawValue)")
        }
    }
    
    /// Deletes all reviews from the store that match a specific origin.
    /// Operations are performed on the main actor.
    /// - Parameter origin: The `ReviewOrigin` to filter reviews for deletion.
    func deleteAllReviews(fromOrigin origin: ReviewOrigin) async {
        // Ensure context operations are on the main thread.
        await MainActor.run {
            let originValue = origin.rawValue
            // Fetch records matching the origin before deleting.
            let descriptor = FetchDescriptor<VisitRecord>(
                predicate: #Predicate { $0.origin == originValue }
            )
            do {
                let existingRecords = try context.fetch(descriptor)
                print("Found \(existingRecords.count) reviews with origin \(originValue) to delete.")
                for record in existingRecords {
                    context.delete(record)
                }
                // SwiftData typically auto-saves. Explicit save can be added if needed.
                print("Deleted \(existingRecords.count) reviews with origin \(originValue).")
            } catch {
                print("Error fetching or deleting reviews with origin \(originValue): \(error)")
            }
        }
    }
    
    /// Checks if there are any reviews in the store with the 'imported' origin.
    /// Operations are performed on the main actor.
    /// - Returns: `true` if imported reviews exist, `false` otherwise.
    func hasImportedReviews() async -> Bool {
        // Ensure context operations are on the main thread.
        await MainActor.run {
            let originValue = ReviewOrigin.imported.rawValue
            var descriptor = FetchDescriptor<VisitRecord>(
                predicate: #Predicate { $0.origin == originValue }
            )
            descriptor.fetchLimit = 1 // Optimize by fetching only one record if it exists.
            do {
                let count = try context.fetchCount(descriptor)
                return count > 0
            } catch {
                print("Error fetching count for imported reviews: \(error)")
                return false
            }
        }
    }

    /// Deletes all `VisitRecord` data from the SwiftData store and associated image files from disk.
    /// Operations are performed on the main actor.
    func deleteAllData() async {
        await MainActor.run {
            let descriptor = FetchDescriptor<VisitRecord>() // Fetches all VisitRecords
            do {
                let existingRecords = try context.fetch(descriptor)
                print("Found \(existingRecords.count) total reviews to delete.")
                for record in existingRecords {
                    context.delete(record)
                }
                // SwiftData typically auto-saves.
                print("Deleted \(existingRecords.count) total reviews from SwiftData.")

                // After deleting records from the database, remove associated image files.
                deleteImageDirectories()

            } catch {
                print("Error fetching or deleting all reviews: \(error)")
            }
        }
    }

    /// Deletes the directories used for storing original and optimized images.
    /// This is part of the `deleteAllData` process to ensure no orphaned files remain.
    private func deleteImageDirectories() {
        let fileManager = FileManager.default

        // Attempt to get the Application Support directory URL.
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("Error: Cannot find Application Support directory to delete image caches.")
            return
        }

        // Subdirectory names for image storage. These should ideally be defined in a shared constants file
        // or accessible via FileUtils to avoid string duplication.
        let optimizedImagesSubDir = "OptimizedVisitImages"
        let originalImagesSubDir = "OriginalVisitImages"
        
        let directoriesToDelete = [appSupportURL.appendingPathComponent(optimizedImagesSubDir),
                                   appSupportURL.appendingPathComponent(originalImagesSubDir)]

        for dirURL in directoriesToDelete {
            if fileManager.fileExists(atPath: dirURL.path) {
                do {
                    try fileManager.removeItem(at: dirURL)
                    print("Successfully deleted directory: \(dirURL.path)")
                } catch {
                    print("Error deleting directory \(dirURL.path): \(error)")
                }
            } else {
                print("Directory not found, presumed already deleted or never created: \(dirURL.path)")
            }
        }
    }
}