import Foundation
import ImageIO
import UniformTypeIdentifiers // Modern UTI framework for working with type identifiers.

/// A utility struct for image-related operations.
struct ImageUtils {
    /// Determines the MIME type of an image based on its data.
    /// - Parameter data: The image data.
    /// - Returns: A string representing the MIME type (e.g., "image/jpeg"), or `nil` if the type cannot be determined or is not supported.
    static func getMIMEType(for data: Data) -> String? {
        // Create an image source from the provided data.
        // CGImageSource allows inspection of image properties without full decompression.
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            print("Error: Could not create CGImageSource from data.")
            return nil
        }

        // Get the Uniform Type Identifier (UTI) of the image from the image source.
        // The UTI string (e.g., "public.jpeg") uniquely identifies the data type.
        guard let imageCGUTI = CGImageSourceGetType(imageSource) else {
            print("Error: Could not get UTI from CGImageSource.")
            return nil
        }

        let utiString = imageCGUTI as String

        // Use the modern UTType framework for more robust type checking and information.
        if let utType = UTType(utiString) {
            // Check against common, explicitly supported image types.
            if utType.conforms(to: .jpeg) {
                return "image/jpeg"
            } else if utType.conforms(to: .png) {
                return "image/png"
            } else if utType.conforms(to: .heic) {
                // HEIC is an image format that typically uses HEVC encoding.
                return "image/heic"
            } else if utType.conforms(to: .heif) {
                // HEIF is a container format; HEIC is a common specific instance using HEVC.
                return "image/heif"
            } else if utType.conforms(to: .webP) {
                return "image/webp"
            } else {
                // Fallback: Check if the system's preferred MIME type for this UTI
                // is one of the types we generally support (e.g., for LLM input).
                if let preferredMIME = utType.preferredMIMEType {
                    let supportedMIMETypes = ["image/jpeg", "image/png", "image/heic", "image/heif", "image/webp"]
                    if supportedMIMETypes.contains(preferredMIME.lowercased()) {
                        return preferredMIME
                    }
                }
                // If the type is not explicitly handled or its preferred MIME type isn't in our supported list.
                print("Warning: Image UTI \(utiString) (\(utType.description)) is not explicitly handled or its preferred MIME type is not in the supported list.")
                return nil
            }
        } else {
            // This case occurs if the UTI string obtained from CGImageSource
            // cannot be resolved into a UTType object.
            print("Warning: Could not create UTType from UTI string: \(utiString)")
            return nil
        }
    }
}