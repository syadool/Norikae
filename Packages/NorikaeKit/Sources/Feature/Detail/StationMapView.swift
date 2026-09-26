import DesignSystem
import Domain
@preconcurrency import MapKit
import SwiftUI

/// 駅周辺の地図（駅の出口、駅まで歩く経路、FR-DTL-08）
///
/// 現在地は端末内だけで使い、サーバーには送らない（NFR-03）。徒歩経路は MapKit で求める。
struct StationMapView: View {
    let stationId: String
    let dependencies: AppDependencies

    @State private var position: MapCameraPosition = .automatic
    @State private var walkingRoute: MKRoute?
    @State private var locationState: LocationState = .idle

    enum LocationState: Equatable {
        case idle, loading, shown, denied, failed
    }

    private var station: Station? { dependencies.catalog.station(stationId) }

    var body: some View {
        Group {
            if let station {
                VStack(spacing: 0) {
                    map(station)
                    controls(station)
                }
            } else {
                EmptyStateView(systemImage: "mappin.slash", title: String(localized: "この駅は利用できません", bundle: .module))
            }
        }
        .nkScreenBackground()
        .navigationTitle(station.map { String(localized: "\($0.name)駅の周辺", bundle: .module) } ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func map(_ station: Station) -> some View {
        Map(position: $position) {
            Marker(station.name, systemImage: "tram.fill", coordinate: station.clCoordinate)
                .tint(NKColor.accentFill)
            ForEach(station.exits ?? [], id: \.self) { exit in
                Annotation(exit.name, coordinate: CLLocationCoordinate2D(latitude: exit.latitude, longitude: exit.longitude)) {
                    Image(systemName: "door.left.hand.open")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NKColor.onAccent)
                        .padding(5)
                        .background(NKColor.textSecondary, in: Circle())
                }
            }
            if let walkingRoute {
                MapPolyline(walkingRoute.polyline)
                    .stroke(NKColor.accentFill, style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [1, 8]))
            }
            if locationState == .shown {
                UserAnnotation()
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onAppear {
            position = .region(MKCoordinateRegion(center: station.clCoordinate, latitudinalMeters: 700, longitudinalMeters: 700))
        }
    }

    private func controls(_ station: Station) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let walkingRoute {
                Label {
                    Text("現在地から徒歩 約\(Int((walkingRoute.expectedTravelTime / 60).rounded()))分", bundle: .module)
                } icon: {
                    Image(systemName: "figure.walk")
                }
                .font(.subheadline.weight(.semibold))
            }
            switch locationState {
            case .denied:
                OpenSettingsLink(message: String(localized: "位置情報の利用が許可されていないため、現在地からの経路を表示できません。", bundle: .module))
            case .failed:
                Text("徒歩の経路を取得できませんでした", bundle: .module)
                    .font(.footnote)
                    .foregroundStyle(NKColor.textSecondary)
            default:
                EmptyView()
            }
            if walkingRoute == nil {
                Button {
                    Task { await showWalkingRoute(to: station) }
                } label: {
                    Label { Text("現在地からの徒歩経路", bundle: .module) } icon: { Image(systemName: "location") }
                }
                .buttonStyle(NKSecondaryButtonStyle())
                .disabled(locationState == .loading)
            }
        }
        .padding(NKSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NKColor.surface)
    }

    /// 位置情報の権限は、駅周辺地図を初めて使うときに要求する（frontend.md 7.2）
    private func showWalkingRoute(to station: Station) async {
        locationState = .loading
        do {
            let here = try await dependencies.location.currentLocation()
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: here.latitude, longitude: here.longitude)))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: station.clCoordinate))
            request.transportType = .walking
            let response = try await MKDirections(request: request).calculate()
            walkingRoute = response.routes.first
            locationState = .shown
            if let rect = walkingRoute?.polyline.boundingMapRect {
                position = .rect(rect.insetBy(dx: -rect.width * 0.2 - 200, dy: -rect.height * 0.2 - 200))
            }
        } catch LocationError.denied {
            locationState = .denied
        } catch {
            locationState = .failed
        }
    }
}

extension Station {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
