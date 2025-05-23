import Foundation
import SwiftUI // For Identifiable, often useful in models passed to views

// MARK: - Review Draft Display Item Definition

/// Represents a single review draft item, typically displayed in a list where users can
/// interact with or monitor the status of AI-generated review summaries.
struct ReviewDraftDisplayItem: Identifiable, Hashable {

    /// An enumeration representing the current processing status of the review draft.
    /// This helps in providing visual feedback to the user (e.g., loading indicators, error messages).
    enum Status: Hashable {
        /// Indicates that the review draft is currently being processed or generated.
        case loading
        /// Indicates that the review draft has been successfully generated or processed.
        case success
        /// Indicates that an error occurred during the generation or processing of the review draft.
        /// - `message`: A descriptive message explaining the error.
        case error(message: String)

        /// Conforms to `Hashable` by providing a custom hashing logic.
        /// This is necessary because the `error` case has an associated value.
        func hash(into hasher: inout Hasher) {
            switch self {
            case .loading:
                hasher.combine(0) // Arbitrary unique integer for this case
            case .success:
                hasher.combine(1) // Arbitrary unique integer for this case
            case .error(let message):
                hasher.combine(2) // Arbitrary unique integer for this case
                hasher.combine(message) // Include the associated value in the hash
            }
        }

        /// Conforms to `Equatable` by providing custom equality comparison.
        /// This is necessary because the `error` case has an associated value.
        static func == (lhs: Status, rhs: Status) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading):
                return true
            case (.success, .success):
                return true
            case (.error(let lMsg), .error(let rMsg)):
                return lMsg == rMsg // Two errors are equal if their messages are equal
            default:
                return false // All other combinations are not equal
            }
        }
    }

    /// A unique identifier for the review draft item, conforming to `Identifiable`.
    /// This is automatically generated as a UUID.
    let id = UUID()
    /// A string indicating the source or context of the review draft (e.g., "Gemini Pro", "User Edited").
    var source: String
    /// The textual content of the review draft. This can be edited by the user or updated by AI.
    var text: String
    /// An optional string holding the original text of the review draft before any edits.
    /// This can be used to allow users to revert changes.
    var originalTextForRestore: String? = nil
    /// The current processing status of this review draft item (e.g., loading, success, error).
    var status: Status
}