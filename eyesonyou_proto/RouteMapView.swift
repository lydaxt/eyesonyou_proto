import MapKit
import SwiftUI

protocol RouteMapProvider {
    var mapRegion: MKCoordinateRegion { get }
    var route: MKRoute? { get }
    var userLocation: CLLocation? { get }
    var destinationLocation: CLLocation? { get }
}

struct RouteMapView: View {
    @EnvironmentObject var locationManager: LocationManager

    @State private var region: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )

    private var routeMapData: RouteMapProvider {
        return locationManager as RouteMapProvider
    }

    var body: some View {
        Map {

            if let userLocation = locationManager.currentLocation.coordinate {
                UserAnnotation()

                MapCircle(center: userLocation.coordinate, radius: locationManager.locationAccuracy)
                    .foregroundStyle(.blue.opacity(0.2))
                    .mapOverlayLevel(level: .aboveRoads)

                Marker("You", systemImage: "location.fill", coordinate: userLocation.coordinate)
                    .tint(.blue)
            }

            if locationManager.isNavigating {

                if let destination = locationManager.targetLocation.coordinate {
                    Marker(
                        "Destination", systemImage: "mappin.circle.fill",
                        coordinate: destination.coordinate
                    )
                    .tint(.red)
                }

                if let route = locationManager.route {
                    MapPolyline(route.polyline)
                        .stroke(.blue, lineWidth: 5)
                }
            }
        }
        .mapStyle(.standard)
        .mapControlVisibility(.hidden)
        .onAppear {

            if locationManager.currentLocation.coordinate != nil {
                centerOnUserLocation()
            }
        }
        .onChange(of: locationManager.currentLocation.coordinate) { _, _ in
            if locationManager.isNavigating {

                updateRegion()

                checkRouteDeviation()
            } else {
                centerOnUserLocation()
            }
        }
    }

    private func centerOnUserLocation() {
        guard let userLocation = locationManager.currentLocation.coordinate else { return }

        region = MKCoordinateRegion(
            center: userLocation.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
        )
    }

    private func updateRegion() {
        guard let userLocation = locationManager.currentLocation.coordinate else { return }

        if locationManager.isNavigating, let destination = locationManager.targetLocation.coordinate
        {

            let midLat = (userLocation.coordinate.latitude + destination.coordinate.latitude) / 2
            let midLon = (userLocation.coordinate.longitude + destination.coordinate.longitude) / 2

            let distance = userLocation.distance(from: destination)
            let span = min(max(distance / 5000, 0.01), 0.1)

            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: midLat, longitude: midLon),
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            )
        } else {

            region = MKCoordinateRegion(
                center: userLocation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            )
        }
    }

    private func adjustMapToShowRoute() {
        guard let route = locationManager.route else { return }

        let rect = route.polyline.boundingMapRect
        let region = MKCoordinateRegion(rect)

        let paddedRegion = MKCoordinateRegion(
            center: region.center,
            span: MKCoordinateSpan(
                latitudeDelta: region.span.latitudeDelta * 1.2,
                longitudeDelta: region.span.longitudeDelta * 1.2
            )
        )

        self.region = paddedRegion
    }

    private func checkRouteDeviation() {
        guard locationManager.isNavigating,
            let route = locationManager.route,
            let userLocation = locationManager.currentLocation.coordinate
        else { return }

    }
}
