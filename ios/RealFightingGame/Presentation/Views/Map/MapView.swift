import MapKit
import SwiftUI

@available(iOS 17.0, *)
struct MapView: View {
    @StateObject private var viewModel = MapViewModel()

    var body: some View {
        Map(position: cameraPositionBinding) {
            ForEach(viewModel.destinations) { pin in
                Marker(pin.title, coordinate: pin.coordinate)
                    .tint(.purple)
            }
        }
        .mapStyle(.standard)
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .top) {
            mapOverlay
                .padding()
        }
    }

    private var mapOverlay: some View {
        VStack(spacing: 8) {
            Text("魔素マップ")
                .font(.headline)
            Text("訓練に適したスポットを表示中")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
    }

    private var cameraPositionBinding: Binding<MapCameraPosition> {
        Binding<MapCameraPosition>(
            get: { MapCameraPosition.region(viewModel.region) },
            set: { newValue in
                if let updatedRegion = newValue.region {
                    viewModel.region = updatedRegion
                }
            }
        )
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview {
    MapView()
}
#endif
