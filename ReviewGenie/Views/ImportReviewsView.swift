import SwiftUI
import UniformTypeIdentifiers // For UTType.json
import SwiftData

struct ImportReviewsView: View {
    @Environment(\.modelContext) private var modelContext
    
    var onCompletion: () -> Void
    var onCancel: () -> Void

    @State private var showImportWarningAndPendingFile: Bool = false // True if a file is selected and existing imports are detected
    @State private var selectedFileURL: URL?
    @State private var isShowingFileImporter: Bool = false
    @State private var isImporting: Bool = false
    @State private var importResultMessage: String = ""

    // Default initializer
    init(onCompletion: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onCompletion = onCompletion
        self.onCancel = onCancel
        self._showImportWarningAndPendingFile = State(initialValue: false)
        self._selectedFileURL = State(initialValue: nil)
    }

    // Initializer for previews or specific state setup, allowing to set initial state for UI testing.
    init(onCompletion: @escaping () -> Void, 
         onCancel: @escaping () -> Void, 
         showImportWarningAndPendingFile: Bool, 
         selectedFileURL: URL?) {
        self.onCompletion = onCompletion
        self.onCancel = onCancel
        self._showImportWarningAndPendingFile = State(initialValue: showImportWarningAndPendingFile)
        self._selectedFileURL = State(initialValue: selectedFileURL)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Instructions")
                    .font(.title2)
                    .fontWeight(.medium)
                
                VStack(alignment: .leading, spacing: 12) {
                    InstructionStep(number: 1, text: "Go to Google Takeout: takeout.google.com")
                    InstructionStep(number: 2, text: "Click \"Deselect all\".")
                    InstructionStep(number: 3, text: "Find and select \"Maps (your places)\".")
                    InstructionStep(number: 4, text: "Ensure \"Reviews\" is set to GeoJSON format (usually default). If not, click the format button to change it.")
                    InstructionStep(number: 5, text: "Click \"Next step\", then \"Create export\".")
                    InstructionStep(number: 6, text: "Download the .zip file when ready and unzip it.")
                    InstructionStep(number: 7, text: "Locate the \"Reviews.json\" (or .geojson) file inside \"Takeout/Maps (your places)/\".")
                }
                .padding(.bottom)

                // Main File Selection Button
                Button {
                    isShowingFileImporter = true
                    if !isImporting { importResultMessage = "" }
                    // If user re-selects while warning is up, hide the warning as a new file selection process starts.
                    if showImportWarningAndPendingFile { 
                        showImportWarningAndPendingFile = false 
                        // selectedFileURL will be updated by fileImporter if a new file is chosen.
                    }
                } label: {
                    Label(selectedFileURL != nil && showImportWarningAndPendingFile ? "Or Select a Different File" : "Select Reviews GeoJSON File", systemImage: "doc.text.fill")
                        .fontWeight(.medium)
                        .padding()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .tint(.accentColor)
                .padding(.bottom, showImportWarningAndPendingFile && selectedFileURL != nil ? 8 : 16)

                // "Replace Previous Import" Button - shown only if a file is selected and existing imports are detected.
                if showImportWarningAndPendingFile && selectedFileURL != nil {
                    Button {
                        if let url = selectedFileURL {
                            Task {
                                let storageManager = SwiftDataStorageManager(context: modelContext)
                                await performActualImport(fileURL: url, storageManager: storageManager)
                                self.showImportWarningAndPendingFile = false // Hide warning after action
                            }
                        }
                    } label: {
                        Label("Replace Previous Import with Selected File", systemImage: "exclamationmark.triangle.fill")
                            .fontWeight(.medium)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                    .tint(.orange) // Use orange to indicate a potentially destructive action.
                    .padding(.bottom, 8)
                }

                // Conditional Warning Message - shown if a file is selected and existing imports are detected.
                if showImportWarningAndPendingFile {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Important:")
                            .font(.headline)
                            .foregroundColor(.orange)
                        Text("Continuing will replace any Google Maps reviews you previously imported. Reviews created directly within this app will not be affected.")
                            .font(.callout)
                    }
                    .padding()
                    .background(Material.thin, in: RoundedRectangle(cornerRadius: 8))
                }

                if isImporting {
                    HStack { // Center ProgressView during import
                        Spacer()
                        ProgressView("Importing reviews...")
                        Spacer()
                    }
                    .padding(.top)
                } else if !importResultMessage.isEmpty {
                    // Container for result message and Done button
                    VStack(spacing: 15) { 
                        HStack {
                            if importResultMessage.starts(with: "Error") || importResultMessage.starts(with: "Failed") {
                                Image(systemName: "xmark.octagon.fill")
                                    .foregroundColor(.red)
                                    .font(.title)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.title)
                            }
                            Text(importResultMessage)
                                .font(.callout)
                                .foregroundColor(importResultMessage.starts(with: "Error") || importResultMessage.starts(with: "Failed") ? .red : .primary)
                        }
                        .padding()
                        .background(Material.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        
                        // Show "Done" button only on successful import.
                        if !(importResultMessage.starts(with: "Error") || importResultMessage.starts(with: "Failed")) {
                            Button("Done") {
                                onCompletion() // Navigate away on success.
                            }
                            .buttonStyle(BorderedProminentButtonStyle())
                            .tint(.accentColor)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top)
                }
                
                Spacer() // Pushes content towards the top.
            }
            .padding()
        }
        // .navigationTitle("Import Google Reviews") // Title can be set by the parent view (e.g., HomeView).
        .toolbar { // Toolbar for the cancel button.
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    onCancel() // Use the provided callback to handle cancellation.
                }
            }
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [UTType.json, UTType(filenameExtension: "geojson") ?? .json], // Allow .json and .geojson files.
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result: result)
        }
    }

    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                importResultMessage = "Error: No file was selected."
                return
            }
            self.selectedFileURL = url // Store the selected file URL.
            self.importResultMessage = "" // Clear previous messages.
            self.isImporting = false // Ensure not in importing state from a previous attempt.

            Task {
                let storageManager = SwiftDataStorageManager(context: modelContext)
                let hasExisting = await storageManager.hasImportedReviews()
                
                if hasExisting {
                    // Existing imports detected, show warning and wait for user to click "Replace" button.
                    self.showImportWarningAndPendingFile = true
                } else {
                    // No existing imports, proceed directly with the import.
                    self.showImportWarningAndPendingFile = false
                    await performActualImport(fileURL: url, storageManager: storageManager)
                }
            }
        case .failure(let error):
            importResultMessage = "Error selecting file: \(error.localizedDescription)"
            self.showImportWarningAndPendingFile = false // Ensure warning isn't stuck if file selection fails.
        }
    }

    private func performActualImport(fileURL: URL, storageManager: StorageManagerProtocol) async {
        // Request access to the security-scoped resource.
        guard fileURL.startAccessingSecurityScopedResource() else {
            await MainActor.run {
                importResultMessage = "Error: Could not access file at path: \(fileURL.path). Make sure the app has permissions."
                isImporting = false
                showImportWarningAndPendingFile = false // Reset warning state.
            }
            return
        }
        // Release access when the function exits.
        defer { fileURL.stopAccessingSecurityScopedResource() }

        await MainActor.run {
            isImporting = true
            importResultMessage = "" // Clear any previous message before starting import.
        }

        let reviewImporterService = ReviewImporterService(storageManager: storageManager)
        
        do {
            let fileData = try Data(contentsOf: fileURL)
            let result = await reviewImporterService.importReviews(from: fileData)
            
            await MainActor.run {
                var message = "Import Complete!\nImported: \(result.importedCount)"
                if result.failedCount > 0 { message += "\nFailed: \(result.failedCount)" }
                if !result.errors.isEmpty {
                    message += "\nErrors encountered:"
                    for (index, error) in result.errors.prefix(3).enumerated() { // Show up to 3 specific errors.
                        message += "\n  \(index+1). \(error.localizedDescription)"
                    }
                    if result.errors.count > 3 { message += "\n  ...and \(result.errors.count - 3) more error(s)." }
                }
                importResultMessage = message
                isImporting = false
                showImportWarningAndPendingFile = false // Reset warning state as import process is complete.
            }
        } catch {
             await MainActor.run {
                importResultMessage = "Failed to read or process file: \(error.localizedDescription)"
                isImporting = false
                showImportWarningAndPendingFile = false // Reset warning state on failure.
            }
        }
    }
}

// Helper view for displaying each instruction step with consistent styling.
struct InstructionStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .fontWeight(.semibold)
                .foregroundColor(.accentColor)
            Text(text)
                .font(.callout) // Use callout font for instruction text for better readability in a list.
        }
    }
}

struct ImportReviewsView_Previews: PreviewProvider {
    static var previews: some View {
        // Define dummy closures for the preview.
        let dummyCompletion: () -> Void = { print("Preview Completion Called") }
        let dummyCancel: () -> Void = { print("Preview Cancel Called") }

        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: VisitRecord.self, configurations: config)
            
            // Example state for previewing the warning message.
            let viewWithWarning = ImportReviewsView(onCompletion: dummyCompletion, onCancel: dummyCancel, showImportWarningAndPendingFile: true, selectedFileURL: URL(string: "file:///example.json"))
            
            return Group {
                ImportReviewsView(onCompletion: dummyCompletion, onCancel: dummyCancel)
                    .modelContainer(container)
                    .previewDisplayName("Default State")
                
                viewWithWarning
                    .modelContainer(container)
                    .previewDisplayName("Warning State")
            }
            .navigationTitle("Import Google Reviews") // Apply title for preview context.
        } catch {
            fatalError("Failed to create container: \(error)")
        }
    }
}