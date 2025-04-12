import AVFoundation
import MapKit
import SwiftUI

struct NavigationMode: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var locationManager: LocationManager

    @State private var searchText: String = ""
    @State private var suggestions: [Suggestion] = []
    @State private var showSuggestions: Bool = false
    @State private var isNavigating: Bool = false
    @State private var hasAnnouncedInstructions: Bool = false
    @State private var isSelectingSuggestion = false

    private static let sharedSpeechSynthesizer = AVSpeechSynthesizer()
    private var speechSynthesizer: AVSpeechSynthesizer { Self.sharedSpeechSynthesizer }

    private struct Suggestion: Identifiable {
        let id = UUID()
        let name: String
        let address: String
        let coordinate: CLLocationCoordinate2D
    }

    struct SelectionButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(
                    configuration.isPressed ? Color.blue.opacity(0.1) : Color.white
                )
                .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
        }
    }

    var body: some View {
        ZStack {
            appModel.outdoorColor.ignoresSafeArea()

            ScrollView {
                contentView
            }
        }
        .navigationTitle("Outdoor Navigation")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Outdoor Navigation Screen")
        .accessibilityHint("Use this screen to set and navigate to a destination")
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                suggestions = []
                showSuggestions = false
            } else if !isSelectingSuggestion {
                Task { await search(newValue) }
            }
        }
        .onAppear {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("Failed to configure audio session: \(error)")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                announceNavigationInstructions()
            }
        }
        .fullScreenCover(isPresented: $isNavigating) {
            NavigationView()
                .environment(appModel)
                .environmentObject(locationManager)
        }
    }

    private func announceNavigationInstructions() {
        if !UIAccessibility.isVoiceOverRunning && !hasAnnouncedInstructions {
            let currentArea =
                locationManager.currentLocation.address.isEmpty
                ? "still determining"
                : locationManager.simplifiedLocationForAnnouncement

            let instructionText =
                "This is Navigation Mode. Your current location is \(currentArea). You can search your destination in the search bar below, and tap the bottom button to start navigation."

            let utterance = AVSpeechUtterance(string: instructionText)
            utterance.rate = 0.6
            utterance.pitchMultiplier = 1.0
            utterance.volume = 1.0
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

            speechSynthesizer.speak(utterance)
            hasAnnouncedInstructions = true
        }
    }

    private var contentView: some View {
        VStack(spacing: 24) {
            currentLocationSection
            destinationSection
            navigationButton
            Spacer()
        }
        .padding()
        .background(appModel.outdoorColor)
    }

    private var currentLocationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            currentLocationHeader
            currentLocationAddress
            currentLocationMap
        }
        .padding()
        .background(Color.white)
        .cornerRadius(30)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }

    private var currentLocationHeader: some View {
        HStack(spacing: 16) {
            Image(systemName: "location.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(appModel.accentColor)
                .accessibilityLabel("Current Location Icon")
            Text("Current Location")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(appModel.primaryColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current Location Section")
        .accessibilityHint("Shows your current position")
    }

    private var currentLocationAddress: some View {
        Text(locationManager.currentLocation.address)
            .font(.system(size: 20))
            .foregroundStyle(appModel.primaryColor)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(appModel.backgroundColor)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
            .accessibilityLabel("Current Address: \(locationManager.currentLocation.address)")
            .accessibilityHint("Your current location address")
    }

    private var currentLocationMap: some View {
        RouteMapView()
            .frame(height: 180)
            .cornerRadius(16)
            .padding(.top, 8)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading) {
                    Text("Accuracy: \(Int(locationManager.locationAccuracy))m")
                        .font(.caption)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.8))
                        )
                }
                .padding(8)
            }
            .accessibilityLabel("Current location test map")
            .accessibilityHint(
                "Map showing current location accuracy: \(Int(locationManager.locationAccuracy)) meters"
            )
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            destinationHeader
            selectedDestination
            Divider()
            searchBar
            suggestionsList
        }
        .padding()
        .background(Color.white)
        .cornerRadius(30)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }

    private var destinationHeader: some View {
        HStack(spacing: 16) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(appModel.warningColor)
                .accessibilityLabel("Destination Icon")
            Text("Destination")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(appModel.primaryColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Destination Section")
        .accessibilityHint("Set your target location here")
    }

    private var selectedDestination: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected Destination:")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.gray)
            Text(
                locationManager.targetLocation.address.isEmpty
                    ? "No destination selected" : locationManager.targetLocation.address
            )
            .font(.system(size: 20))
            .foregroundStyle(
                locationManager.targetLocation.address.isEmpty ? .gray : appModel.primaryColor
            )
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(appModel.backgroundColor)
            .cornerRadius(12)
            .accessibilityLabel(
                "Destination: \(locationManager.targetLocation.address.isEmpty ? "No destination selected" : locationManager.targetLocation.address)"
            )
            .accessibilityHint("The currently selected destination address")
            .onChange(of: locationManager.targetLocation.address) { _, newAddress in
                if !newAddress.isEmpty {
                    announceSelectedDestination(newAddress)
                }
            }
        }
    }

    private func announceSelectedDestination(_ destination: String) {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }

        print("Announcing destination selection: \(destination)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let announcementText = "Destination selected: \(destination)"

            let utterance = AVSpeechUtterance(string: announcementText)
            utterance.rate = 0.55
            utterance.pitchMultiplier = 1.0
            utterance.volume = 1.0
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

            print("Starting to speak: \(announcementText)")
            self.speechSynthesizer.speak(utterance)
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.gray)
                .accessibilityLabel("Search Icon")
            TextField("Enter destination", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .submitLabel(.search)
                .accessibilityLabel("Search Destination")
                .accessibilityHint("Enter the name or address of your destination")
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    suggestions = []
                    showSuggestions = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.gray)
                        .accessibilityLabel("Clear Search")
                        .accessibilityHint("Clears the search field and suggestions")
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.9))
        .cornerRadius(12)
    }

    private var suggestionsList: some View {
        Group {
            if showSuggestions && !suggestions.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(suggestions) { suggestion in
                            suggestionButton(for: suggestion)
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(Color.white)
                .cornerRadius(10)
                .shadow(radius: 5)
                .accessibilityLabel("Destination Suggestions")
                .accessibilityHint("List of suggested destinations based on your search")
            }
        }
    }

    private func suggestionButton(for suggestion: Suggestion) -> some View {
        Button(action: {
            isSelectingSuggestion = true

            speechSynthesizer.stopSpeaking(at: .immediate)

            showSuggestions = false
            searchText = suggestion.name

            locationManager.targetLocation.coordinate = CLLocation(
                latitude: suggestion.coordinate.latitude,
                longitude: suggestion.coordinate.longitude
            )
            locationManager.targetLocation.address = "\(suggestion.name), \(suggestion.address)"

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isSelectingSuggestion = false
            }
        }) {
            VStack(alignment: .leading) {
                Text(suggestion.name)
                    .font(.headline)
                    .foregroundStyle(appModel.primaryColor)
                Text(suggestion.address)
                    .font(.subheadline)
                    .foregroundStyle(.gray)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(SelectionButtonStyle())
        .accessibilityLabel("\(suggestion.name), \(suggestion.address)")
        .accessibilityHint("Select this as your destination")
    }

    private var navigationButton: some View {
        Button {
            isNavigating = true
        } label: {
            HStack {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                Text("Start Navigation")
            }
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .disabled(locationManager.targetLocation.address.isEmpty)
        .buttonStyle(.borderedProminent)
        .tint(locationManager.targetLocation.address.isEmpty ? .blue : .orange)
        .accessibilityLabel("Start Navigation")
        .accessibilityHint(
            locationManager.targetLocation.address.isEmpty
                ? "Disabled. Please select a destination first"
                : "Begins navigation to \(locationManager.targetLocation.address)")
    }

    private func search(_ query: String) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: locationManager.currentLocation.coordinate?.coordinate
                ?? CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694),
            span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
        )
        do {
            let response = try await MKLocalSearch(request: request).start()
            suggestions = response.mapItems.map {
                Suggestion(
                    name: $0.name ?? "Unknown",
                    address: [$0.placemark.thoroughfare, $0.placemark.locality].compactMap { $0 }
                        .joined(separator: ", "),
                    coordinate: $0.placemark.coordinate
                )
            }
            showSuggestions = true
        } catch {
            print("Search error: \(error)")
        }
    }
}
