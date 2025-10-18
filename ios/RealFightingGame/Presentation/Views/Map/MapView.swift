import MapKit
import SwiftUI

@available(iOS 17.0, *)
struct MapView: View {
    @StateObject private var viewModel: MapViewModel

    init(service: MapService, locationService: LocationService? = nil) {
        _viewModel = StateObject(wrappedValue: MapViewModel(service: service, locationService: locationService))
    }

    var body: some View {
        ZStack {
            Map(position: cameraPositionBinding, interactionModes: [.all]) {
                if let userPin = viewModel.userLocationPin {
                    Annotation("現在地", coordinate: userPin.coordinate, anchor: .center) {
                        userLocationView
                    }
                }
                ForEach(viewModel.pinsState.data ?? []) { pin in
                    Marker(pin.title, coordinate: pin.coordinate)
                        .tint(.purple)
                }
            }
            .mapStyle(.standard)
            .ignoresSafeArea(edges: .bottom)
            .simultaneousGesture(DragGesture().onChanged { _ in viewModel.userDidPanMap() })
            .onAppear {
                if case .idle = viewModel.pinsState {
                    viewModel.loadPins(force: true)
                }
                viewModel.startTrackingUserLocation()
            }
            .onDisappear {
                viewModel.stopTrackingUserLocation()
            }

            overlayStateView
        }
        .overlay(alignment: .top) { mapOverlay.padding() }
        .overlay(alignment: .bottomTrailing) {
            recenterButton
                .padding(.trailing, 16)
                .padding(.bottom, 24)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("魔素マップの説明")
    }

    private var userLocationView: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 22, height: 22)
            Circle()
                .fill(Color(red: 27 / 255, green: 134 / 255, blue: 255 / 255))
                .frame(width: 14, height: 14)
            Circle()
                .stroke(Color(red: 27 / 255, green: 134 / 255, blue: 255 / 255), lineWidth: 2)
                .frame(width: 24, height: 24)
                .opacity(0.35)
        }
        .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
        .accessibilityLabel("現在地")
    }

    private var recenterButton: some View {
        Button {
            viewModel.recenterOnUser()
        } label: {
            Image(systemName: "location.circle.fill")
                .font(.system(size: 28))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color(red: 27 / 255, green: 134 / 255, blue: 255 / 255))
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
        }
        .accessibilityLabel("現在地へ移動")
    }

    private var cameraPositionBinding: Binding<MapCameraPosition> {
        Binding<MapCameraPosition>(
            get: { MapCameraPosition.region(viewModel.region) },
            set: { newValue in
                if let updatedRegion = newValue.region {
                    viewModel.handleRegionChangeFromMap(updatedRegion)
                }
            }
        )
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview {
    MapView(
        service: MockMapService(mode: .success, latencyMs: 0, failureRate: 0, useFixture: true),
        locationService: MockLocationService()
    )
}
#endif

@available(iOS 17.0, *)
private extension MapView {
    @ViewBuilder
    var overlayStateView: some View {
        switch viewModel.pinsState {
        case .loading:
            EmptyView()
        case .failure:
            VStack(spacing: 8) {
                Text("読み込みに失敗しました")
                    .font(.headline)
                Button("再試行") {
                    viewModel.loadPins(force: true)
                }
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        case .empty:
            VStack(spacing: 8) {
                Image(systemName: "mappin.slash.circle.fill").font(.largeTitle)
                Text("付近にスポットがありません")
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        default:
            EmptyView()
        }
    }
}
