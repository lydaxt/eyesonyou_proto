import AVFoundation
import CoreLocation
import Foundation
import MapKit
import SwiftUI

extension Notification.Name {
    static let destinationReached = Notification.Name("DestinationReached")
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let speechSynthesizer = AVSpeechSynthesizer()

    private var locationHistory: [CLLocation] = []
    private let maxLocationHistoryItems = 5
    private var isFirstLocationUpdate = true

    @Published var locationStatus: CLAuthorizationStatus?
    @Published var currentLocation: Location = .init(coordinate: nil, address: "")
    @Published var targetLocation: Location = .init(coordinate: nil, address: "")

    @Published var locationAccuracy: Double = -1
    @Published var locationAge: TimeInterval = 0

    @Published var geocodingError: String?
    @Published var isRouting: Bool = false

    @Published var route: MKRoute?
    @Published var routeSteps: [MKRoute.Step] = []
    @Published var currentStepIndex: Int = 0
    @Published var distanceToNextStep: CLLocationDistance = 0
    @Published var currentInstruction: String = "Preparing navigation..."
    @Published var estimatedArrivalTime: Date?
    @Published var remainingDistance: CLLocationDistance = 0
    @Published var isNavigating: Bool = false

    @Published var simplifiedLocationForAnnouncement: String = ""

    var voiceGuidanceEnabled: Bool = true
    var stepAlertDistance: CLLocationDistance = 20

    var useAdaptiveFiltering: Bool = true
    var usePredictiveLocation: Bool = true

    private var isStationary = true
    private var lastMovementTime = Date()
    private var averageSpeed: CLLocationSpeed = 0

    struct Location {
        var coordinate: CLLocation?  // Location coordinates
        var address: String = ""  // Address description
        var timestamp: Date = Date()  // When this location was recorded
        var accuracy: CLLocationAccuracy = -1  // Horizontal accuracy
    }

    override init() {
        super.init()
        setupLocationManager()
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()

        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 2.0
        locationManager.activityType = .fitness

        locationManager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationStatus = manager.authorizationStatus

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            currentLocation = Location(coordinate: nil, address: "Location access denied")
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        locationAccuracy = location.horizontalAccuracy
        locationAge = -location.timestamp.timeIntervalSinceNow

        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy < 50 else {
            print("Location update rejected - poor accuracy: \(location.horizontalAccuracy)m")
            return
        }

        if isFirstLocationUpdate {

            isFirstLocationUpdate = false
            currentLocation.coordinate = location
            updateLocationHistory(location)
        } else {

            let filteredLocation = filterLocation(location)
            currentLocation.coordinate = filteredLocation
            currentLocation.accuracy = filteredLocation.horizontalAccuracy
            currentLocation.timestamp = filteredLocation.timestamp
        }

        reverseGeocode(location: location) { address in
            DispatchQueue.main.async {
                self.currentLocation.address = address
            }
        }

        if isNavigating {
            updateNavigationInfo(with: location)
        }

        updateMovementState(with: location)
    }

    private func filterLocation(_ newLocation: CLLocation) -> CLLocation {

        updateLocationHistory(newLocation)

        guard useAdaptiveFiltering else {
            return newLocation
        }

        guard locationHistory.count >= 3 else {
            return newLocation
        }

        if newLocation.horizontalAccuracy < 10 {

            return newLocation
        } else if isStationary {

            return calculateWeightedCentroid(alpha: 0.2)
        } else {

            return calculateWeightedCentroid(alpha: 0.6)
        }
    }

    private func updateLocationHistory(_ location: CLLocation) {
        locationHistory.append(location)

        if locationHistory.count > maxLocationHistoryItems {
            locationHistory.removeFirst()
        }
    }

    private func calculateWeightedCentroid(alpha: Double) -> CLLocation {
        guard !locationHistory.isEmpty else {

            return CLLocation(latitude: 0, longitude: 0)
        }

        let latest = locationHistory.last!

        if locationHistory.count == 1 {
            return latest
        }

        var totalWeight = 0.0
        var weightedLat = 0.0
        var weightedLng = 0.0

        for (index, location) in locationHistory.enumerated() {

            let timeWeight = Double(index + 1) / Double(locationHistory.count)
            let accuracyWeight = 1.0 / max(location.horizontalAccuracy, 1.0)
            let weight = timeWeight * accuracyWeight

            weightedLat += location.coordinate.latitude * weight
            weightedLng += location.coordinate.longitude * weight
            totalWeight += weight
        }

        let filteredLat =
            (weightedLat / totalWeight) * (1 - alpha) + latest.coordinate.latitude * alpha
        let filteredLng =
            (weightedLng / totalWeight) * (1 - alpha) + latest.coordinate.longitude * alpha

        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: filteredLat, longitude: filteredLng),
            altitude: latest.altitude,
            horizontalAccuracy: latest.horizontalAccuracy,
            verticalAccuracy: latest.verticalAccuracy,
            course: latest.course,
            speed: latest.speed,
            timestamp: latest.timestamp
        )
    }

    private func updateMovementState(with location: CLLocation) {

        let isCurrentlyMoving = location.speed > 0.5

        if isCurrentlyMoving {
            isStationary = false
            lastMovementTime = Date()

            if averageSpeed <= 0 {
                averageSpeed = location.speed
            } else {
                averageSpeed = averageSpeed * 0.7 + location.speed * 0.3
            }

            let newDistanceFilter = max(2.0, min(averageSpeed * 1.0, 10.0))
            if abs(locationManager.distanceFilter - newDistanceFilter) > 1.0 {
                locationManager.distanceFilter = newDistanceFilter
            }
        } else if !isStationary && Date().timeIntervalSince(lastMovementTime) > 5.0 {

            isStationary = true
            averageSpeed = 0

            locationManager.distanceFilter = 2.0
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let errorMessage: String

        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                errorMessage = "Location access denied by user"
            case .network:
                errorMessage = "Network error occurred"
            case .locationUnknown:
                errorMessage = "Unable to determine location"
            case .rangingUnavailable:
                errorMessage = "Ranging unavailable"
            case .rangingFailure:
                errorMessage = "Ranging failure"
            default:
                errorMessage =
                    "Location error: \(clError.code.rawValue) - \(error.localizedDescription)"
            }
        } else {
            errorMessage = "Location error: \(error.localizedDescription)"
        }

        print("LocationManager error: \(errorMessage)")
        currentLocation = Location(coordinate: nil, address: errorMessage)
        geocodingError = errorMessage
    }

    func reverseGeocode(location: CLLocation, completion: @escaping (String) -> Void) {
        let geocoder = CLGeocoder()

        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let error = error {
                print("Reverse geocoding error: \(error.localizedDescription)")
                self.geocodingError = error.localizedDescription
                self.simplifiedLocationForAnnouncement = "unknown area"
                completion("Unable to determine address")
                return
            }

            guard let placemark = placemarks?.first else {
                self.simplifiedLocationForAnnouncement = "unknown area"
                completion("No address found")
                return
            }

            let address = self.formatPlacemark(placemark)

            let fullAddress = address
            let truncationPoints = ["Kowloon", "Hong Kong", "New Territories", "Islands"]

            var simplifiedAddress = fullAddress

            for region in truncationPoints {
                if let range = fullAddress.range(of: region) {

                    let endIndex = fullAddress.index(range.upperBound, offsetBy: 0)
                    simplifiedAddress = String(fullAddress[..<endIndex])
                    break
                }
            }

            simplifiedAddress = simplifiedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            if simplifiedAddress.hasSuffix(",") {
                simplifiedAddress.removeLast()
            }

            self.simplifiedLocationForAnnouncement = simplifiedAddress

            print("Full address: \(address)")
            print("Simplified for announcement: \(self.simplifiedLocationForAnnouncement)")

            completion(address)
        }
    }

    func geocodeAddress() {

        guard !targetLocation.address.isEmpty else {
            self.geocodingError = "No destination address to geocode"
            return
        }

        let geocoder = CLGeocoder()

        self.geocodingError = nil

        geocoder.geocodeAddressString(targetLocation.address) { [weak self] placemarks, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                if let error = error {
                    print("Geocoding error: \(error.localizedDescription)")
                    self.geocodingError = error.localizedDescription
                    return
                }

                guard let placemark = placemarks?.first, let location = placemark.location else {
                    self.geocodingError = "Could not find location for this address"
                    return
                }

                self.targetLocation.coordinate = location
            }
        }
    }

    private func formatPlacemark(_ placemark: CLPlacemark) -> String {
        var components: [String] = []

        if let name = placemark.name { components.append(name) }
        if let thoroughfare = placemark.thoroughfare { components.append(thoroughfare) }
        if let subThoroughfare = placemark.subThoroughfare { components.append(subThoroughfare) }
        if let locality = placemark.locality { components.append(locality) }
        if let subLocality = placemark.subLocality { components.append(subLocality) }
        if let administrativeArea = placemark.administrativeArea {
            components.append(administrativeArea)
        }
        if let postalCode = placemark.postalCode { components.append(postalCode) }
        if let country = placemark.country { components.append(country) }

        return components.joined(separator: ", ")
    }

    func calculateRouteOnly() {
        guard let sourceLocation = currentLocation.coordinate,
            let destinationLocation = targetLocation.coordinate
        else {
            self.geocodingError = "Missing source or destination coordinates"
            return
        }

        calculateRoute(from: sourceLocation, to: destinationLocation) { success in
            if success {
                DispatchQueue.main.async {

                    self.isNavigating = true

                    self.currentInstruction = "Route calculated. Ready to begin navigation."
                }
            }
        }
    }

    func startNavigation() {

        if isNavigating && !routeSteps.isEmpty {
            currentStepIndex = 0

            if !routeSteps.isEmpty {
                currentInstruction = routeSteps[0].instructions
                if voiceGuidanceEnabled {
                    speakInstruction(currentInstruction)
                }
            }
        } else {

            calculateRouteOnly()
        }
    }

    func stopNavigation() {
        isNavigating = false
        route = nil
        routeSteps = []
        currentStepIndex = 0
        currentInstruction = "Navigation ended"
        speechSynthesizer.stopSpeaking(at: .immediate)
    }

    private func calculateRoute(
        from source: CLLocation, to destination: CLLocation, completion: @escaping (Bool) -> Void
    ) {
        isRouting = true

        let sourcePlacemark = MKPlacemark(coordinate: source.coordinate)
        let destinationPlacemark = MKPlacemark(coordinate: destination.coordinate)

        let sourceItem = MKMapItem(placemark: sourcePlacemark)
        let destinationItem = MKMapItem(placemark: destinationPlacemark)

        let request = MKDirections.Request()
        request.source = sourceItem
        request.destination = destinationItem
        request.transportType = .walking

        let directions = MKDirections(request: request)
        directions.calculate { [weak self] response, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.isRouting = false

                if let error = error {
                    print("Route calculation error: \(error.localizedDescription)")
                    self.geocodingError = "Unable to calculate route: \(error.localizedDescription)"
                    completion(false)
                    return
                }

                guard let response = response, let route = response.routes.first else {
                    self.geocodingError = "No suitable route found"
                    completion(false)
                    return
                }

                self.route = route
                self.routeSteps = route.steps

                let travelTime = route.expectedTravelTime
                self.estimatedArrivalTime = Date().addingTimeInterval(travelTime)
                self.remainingDistance = route.distance

                completion(true)
            }
        }
    }

    private func updateNavigationInfo(with currentLocation: CLLocation) {
        guard isNavigating, !routeSteps.isEmpty else { return }

        // Update total remaining distance to destination
        if let destinationLocation = targetLocation.coordinate {
            remainingDistance = currentLocation.distance(from: destinationLocation)
        }

        _ = routeSteps[currentStepIndex]

        if currentStepIndex + 1 < routeSteps.count {
            let nextStep = routeSteps[currentStepIndex + 1]

            let pointCount = nextStep.polyline.pointCount
            let points = nextStep.polyline.points()
            if pointCount > 0 {
                let mapPoint = points[0]
                let nextStepCoordinate = mapPoint.coordinate
                let nextStepLocation = CLLocation(
                    latitude: nextStepCoordinate.latitude, longitude: nextStepCoordinate.longitude)
                distanceToNextStep = currentLocation.distance(from: nextStepLocation)

                if distanceToNextStep <= stepAlertDistance {
                    currentStepIndex += 1
                    currentInstruction = nextStep.instructions
                    if voiceGuidanceEnabled {
                        speakInstruction(currentInstruction)
                    }
                }
            }
        } else {

            if let destinationLocation = targetLocation.coordinate {
                distanceToNextStep = currentLocation.distance(from: destinationLocation)

                if distanceToNextStep <= stepAlertDistance
                    && currentStepIndex == routeSteps.count - 1
                {
                    currentInstruction = "You have arrived at your destination"
                    if voiceGuidanceEnabled {
                        speakInstruction(currentInstruction)
                    }

                    NotificationCenter.default.post(name: .destinationReached, object: nil)

                    stopNavigation()
                }
            }
        }
    }

    func speakInstruction(_ instruction: String) {

        SpeechManager.shared.addToQueue(instruction)
    }

    func formatDistance(_ distance: CLLocationDistance) -> String {
        if distance >= 1000 {
            let kilometers = distance / 1000
            return String(format: "%.1f km", kilometers)
        } else {
            return String(format: "%.0f m", distance)
        }
    }

    func formatEstimatedArrivalTime() -> String {
        guard let arrivalTime = estimatedArrivalTime else {
            return "Calculating..."
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: arrivalTime)
    }

    func calculateRouteOnly(completion: @escaping (Bool) -> Void) {
        guard let sourceLocation = currentLocation.coordinate,
            let destinationLocation = targetLocation.coordinate
        else {
            self.geocodingError = "Missing source or destination coordinates"
            completion(false)
            return
        }

        calculateRoute(from: sourceLocation, to: destinationLocation) { success in
            DispatchQueue.main.async {

                if success {
                    self.isNavigating = true
                    self.currentInstruction = "Route calculated. Ready to begin navigation."
                }
                completion(success)
            }
        }
    }
}

extension LocationManager: RouteMapProvider {
    var mapRegion: MKCoordinateRegion {
        if let userLocation = currentLocation.coordinate,
            let destination = targetLocation.coordinate
        {

            let centerLat = (userLocation.coordinate.latitude + destination.coordinate.latitude) / 2
            let centerLon =
                (userLocation.coordinate.longitude + destination.coordinate.longitude) / 2

            let distance = userLocation.distance(from: destination)
            let span = min(max(distance / 5000, 0.01), 0.1)

            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            )
        } else if let userLocation = currentLocation.coordinate {

            return MKCoordinateRegion(
                center: userLocation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        } else {

            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694),  //Hong Kong
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
    }

    var userLocation: CLLocation? {
        return currentLocation.coordinate
    }

    var destinationLocation: CLLocation? {
        return targetLocation.coordinate
    }
}
