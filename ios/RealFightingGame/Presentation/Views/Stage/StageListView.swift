import SwiftUI
import MapKit

struct StageListView: View {
    @StateObject private var viewModel: StageListViewModel

    init(mapService: MapService, locationService: LocationService?) {
        _viewModel = StateObject(wrappedValue: StageListViewModel(mapService: mapService, locationService: locationService))
    }

    var body: some View {
        List {
            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            if viewModel.stages.isEmpty && !viewModel.isLoading {
                Section {
                    Label("表示できるステージがありません", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(viewModel.stages) { stage in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stage.title)
                            .font(.headline)
                        if let distance = stage.distanceText {
                            Text(distance)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
            }
        }
        .task {
            await viewModel.loadInitialIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .navigationTitle("ステージ一覧")
        .accessibilityIdentifier("stageListView")
    }
}

#Preview {
    StageListView(mapService: MockMapService(mode: .success, latencyMs: 0, failureRate: 0, useFixture: true),
                  locationService: MockLocationService())
}
