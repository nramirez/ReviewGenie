//
//  ContentView.swift
//  ReviewGenie
//
//  Created by naz on 5/9/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    // Query for VisitRecords, sorted by date descending
    @Query(sort: \VisitRecord.date, order: .reverse) private var visitRecords: [VisitRecord]
    
    // State to show NewEntryView sheet
    @State private var isShowingNewEntrySheet = false
    // State to track selected record for detail view
    @State private var selectedVisitRecord: VisitRecord? = nil

    // Explicit public initializer
    public init() {}

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedVisitRecord) {
                ForEach(visitRecords) { record in
                    NavigationLink(value: record) {
                        VStack(alignment: .leading) {
                            Text(record.placeName).font(.headline)
                            Text(record.date, style: .date)
                        }
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .navigationTitle("Past Reviews")
            .navigationSplitViewColumnWidth(min: 250, ideal: 300)
            .toolbar {
                ToolbarItem {
                    Button {
                        isShowingNewEntrySheet = true
                    } label: {
                        Label("Add Review", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .navigation) {
                    NavigationLink {
                        ImportReviewsView(onCompletion: {
                            print("ImportReviewsView completed in ContentView - no automatic pop.")
                        }, onCancel: {
                            print("ImportReviewsView cancelled in ContentView - no automatic pop.")
                        })
                    } label: {
                        Label("Import Reviews", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .sheet(isPresented: $isShowingNewEntrySheet) {
                 NewEntryView(onSave: { newVisitUUID in
                    isShowingNewEntrySheet = false
                    // If ContentView needs to do something with newVisitUUID, it can be handled here.
                    // For now, just dismissing the sheet.
                }, onCancel: {
                    isShowingNewEntrySheet = false
                }, prefillData: nil)
            }
        } detail: {
            if let record = selectedVisitRecord {
                VStack(alignment: .leading) {
                    Text(record.placeName).font(.largeTitle)
                    Text(record.address)
                    Divider()
                    Text("Visited: \(record.date, style: .date)")
                    Text("Overall Rating: \(record.overallExperienceRating, specifier: "%.1f")")
                    if let reviewText = record.selectedReview {
                        Text("Review:").font(.headline).padding(.top)
                        Text(reviewText)
                    }
                    Text("Source: \(record.reviewOrigin.rawValue)")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.top)
                    Spacer()
                }
                .padding()
            } else {
                // Show actions when no review is selected
                VStack(spacing: 30) {
                    Text("Welcome to ReviewGenie!")
                        .font(.title)
                        
                    Text("Select a review from the list, or choose an action below:")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 20)
                    
                    Button {
                        isShowingNewEntrySheet = true
                    } label: {
                        Label("Add New Review", systemImage: "plus.circle.fill")
                            .font(.title2)
                            .padding()
                            .frame(maxWidth: 300)
                    }
                    .buttonStyle(.borderedProminent)
                    // .tint(.gray) // Optionally add if you want a specific gray tint
                    
                    // Note: NavigationLink inside detail of NavigationSplitView can sometimes
                    // have quirks depending on exact OS/SwiftUI version. Test carefully.
                    // If issues arise, an alternative might be needed (e.g., programmatic navigation).
                }
                .padding()
            }
        }
    }

    // deleteItems for VisitRecord
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            offsets.map { visitRecords[$0] }.forEach(modelContext.delete)
            // SwiftData automatically saves changes usually, but explicit save can be added if needed:
            // try? modelContext.save()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: VisitRecord.self, inMemory: true)
}
