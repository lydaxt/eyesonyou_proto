import AVFoundation
import CoreLocation
import MapKit
import RealityKit
import SwiftUI

extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

extension String {
    func simplifiedForNavigation() -> String {
        let lowercased = self.lowercased()

        if lowercased.contains("turn right") {
            return "turn right"
        } else if lowercased.contains("turn left") {
            return "turn left"
        } else if lowercased.contains("continue") || lowercased.contains("head") {
            return "walk straight forward"
        } else if lowercased.contains("arrive") {
            return "arrive at your destination"
        } else {
            return self
        }
    }
}

struct NavigationView: View {
    @EnvironmentObject var locationManager: LocationManager
    @Environment(AppModel.self) private var appModel
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    @State private var routeCalculated = false
    @State private var realityKitModel = RealityKitModel()
    @State private var isInImmersiveMode = false
    @State private var shouldDismiss = false

    private let distanceThresholds: [Double] = [200, 100, 50, 25, 10]
    @State private var lastAnnouncedThreshold: Double = Double.infinity
    @State private var lastProcessedStep: Int = -1
    @State private var lastDistanceAnnouncementTime: Date = Date()
    @State private var distanceAnnounceTimer: Timer?
    @State private var hasAnnouncedFirstStep = false

    private let speechManager = SpeechManager.shared

    @State private var isSpecialCaseDestination = false

    @State private var lastAnnouncementWhenStationaryTime: Date? = nil
    @State private var stationaryAnnouncementCooldown: TimeInterval = 30.0
    @State private var lastCheckedDistance: CLLocationDistance? = nil

    var body: some View {
        navigationContentView
            .onAppear {
                isSpecialCaseDestination = locationManager.targetLocation.address.contains(
                    "Run Run Shaw Creative Media Centre")

                speechManager.onQueueEmpty = {
                }

                if !locationManager.isNavigating {
                    locationManager.calculateRouteOnly { success in
                        if success {
                            self.routeCalculated = true

                            self.speechManager.addToQueue(self.createRouteInfoText())

                            self.realityKitModel.wireframe = true
                            self.realityKitModel.proximityWarnings = true
                            self.enterImmersiveMode()

                            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                                locationManager.startNavigation()

                                self.startDistanceAnnouncementTimer()
                            }
                        }
                    }
                } else {
                    startDistanceAnnouncementTimer()
                }

                NotificationCenter.default.addObserver(
                    forName: .destinationReached,
                    object: nil,
                    queue: .main
                ) { _ in
                    self.handleDestinationArrival()
                }
            }
            .onDisappear {
                distanceAnnounceTimer?.invalidate()
                speechManager.stopSpeaking()
                exitImmersiveMode()
                NotificationCenter.default.removeObserver(self)

                if !locationManager.isNavigating {
                    locationManager.stopNavigation()
                }
            }
            .onChange(of: appModel.immersiveSpaceState) { _, newValue in
                isInImmersiveMode = (newValue == .open)
            }
            .onChange(of: shouldDismiss) { _, dismiss in
                if dismiss {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
    }

    private func startDistanceAnnouncementTimer() {
        distanceAnnounceTimer?.invalidate()

        distanceAnnounceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) {
            [self] _ in
            checkAndAnnounceDistanceUpdates()
        }
    }

    private func checkAndAnnounceDistanceUpdates() {
        guard locationManager.isNavigating,
            locationManager.currentStepIndex < locationManager.routeSteps.count,
            locationManager.voiceGuidanceEnabled,
            !speechManager.isSpeaking
        else {
            return
        }

        let currentStep = locationManager.routeSteps[locationManager.currentStepIndex]
        let distance = locationManager.distanceToNextStep

        let currentTime = Date()
        let isUserLikelyStationary =
            lastCheckedDistance != nil && abs(distance - lastCheckedDistance!) < 3.0

        if isUserLikelyStationary {
            let shouldRepeat =
                lastAnnouncementWhenStationaryTime == nil
                || currentTime.timeIntervalSince(lastAnnouncementWhenStationaryTime!)
                    >= stationaryAnnouncementCooldown

            if shouldRepeat {
                lastAnnouncementWhenStationaryTime = currentTime

                let announcement =
                    "You are still on the way to \(simplifiedInstruction(currentStep.instructions)). "
                    + "Distance remaining: \(formatDistanceForSpeech(distance))."

                speechManager.addToQueue(announcement)
                return
            }
        } else {
            lastAnnouncementWhenStationaryTime = nil
        }

        lastCheckedDistance = distance

        guard Date().timeIntervalSince(lastDistanceAnnouncementTime) >= 5.0 else {
            return
        }

        if !hasAnnouncedFirstStep {
            hasAnnouncedFirstStep = true

            if let nearestThreshold = distanceThresholds.first(where: { distance <= $0 }) {
                lastAnnouncedThreshold = nearestThreshold
                lastDistanceAnnouncementTime = currentTime

                let announcement = formatAnnouncementForDistance(
                    currentStep.instructions, distance: nearestThreshold)
                speechManager.addToQueue(announcement)
            }
            return
        }

        if locationManager.currentStepIndex != self.lastProcessedStep {
            self.lastProcessedStep = locationManager.currentStepIndex
            self.lastAnnouncedThreshold = Double.infinity
        }

        for threshold in distanceThresholds
        where distance <= threshold && threshold < lastAnnouncedThreshold {
            lastAnnouncedThreshold = threshold
            lastDistanceAnnouncementTime = currentTime

            let announcement = formatAnnouncementForDistance(
                currentStep.instructions, distance: threshold)
            if !announcement.isEmpty {
                speechManager.addToQueue(announcement)
            }
            break
        }
    }

    private func simplifiedInstruction(_ instruction: String) -> String {
        let simplifiedInstruction = instruction.simplifiedForNavigation()

        if simplifiedInstruction.contains("walk straight forward") {
            return "walk straight forward"
        }
        return simplifiedInstruction
    }

    private func createRouteInfoText() -> String {
        let destination = locationManager.targetLocation.address
        let distance = formatDistanceForSpeech(locationManager.remainingDistance)
        let time = locationManager.formatEstimatedArrivalTime()

        return
            "Starting navigation to \(destination). Total distance is \(distance). You should arrive around \(time). I'll guide you with turn-by-turn directions as you walk."
    }

    private func formatAnnouncementForDistance(_ instruction: String, distance: Double) -> String {
        if isSpecialCaseDestination {
            let currentStepIndex = locationManager.currentStepIndex

            if currentStepIndex == 0 && instruction.lowercased().contains("start on cornwall") {
                return "Start on Cornwall Street, go straight forward along Cornwall Street"
            }

            if currentStepIndex == 1 {
                if instruction.lowercased().contains("bear right") {
                    if distance >= 180 && distance <= 220 {
                        return "After 200 meters, bear right onto Cornwall Street"
                    } else if distance >= 90 && distance <= 110 {
                        return "In 100 meters, bear right onto Cornwall Street"
                    } else if distance >= 40 && distance <= 60 {
                        return
                            "In 50 meters, bear right onto Cornwall Street and cross the road. Be careful."
                    } else if distance < 30 {
                        return
                            "Bear right onto Cornwall Street and cross the road. Be careful. Your destination is near you in \(Int(locationManager.distanceToNextStep)) meters"
                    }
                }
            }

            if currentStepIndex == 2 && instruction.lowercased().contains("destination") {
                return "Your destination, Run Run Shaw Creative Media Centre, is on your right"
            }
        }

        let simplifiedInstruction = instruction.simplifiedForNavigation()
        let distanceString = formatDistanceForSpeech(distance)

        if instruction.lowercased().contains("start on") {
            return instruction
        }

        if distance < 30 {
            return simplifiedInstruction
        }

        if simplifiedInstruction.contains("walk straight forward") {
            if distance >= 180 && distance <= 220 {
                return "Continue walking straight forward for about \(distanceString)"
            } else if distance >= 40 && distance <= 60 {
                return "Keep walking straight forward for another \(distanceString)"
            } else {
                return ""
            }
        }

        if distance < 50 {
            return "Very soon, \(simplifiedInstruction)"
        } else if distance < 80 {
            return "Get ready to \(simplifiedInstruction) in \(distanceString)"
        } else if distance < 150 {
            return "In \(distanceString), prepare to \(simplifiedInstruction)"
        } else {
            return "In \(distanceString), \(simplifiedInstruction)"
        }
    }

    private func formatDistanceForSpeech(_ distance: CLLocationDistance) -> String {
        if distance >= 1000 {
            let km = distance / 1000
            return "\(Int(km)) kilometer\(km >= 2 ? "s" : "")"
        } else {
            let roundedMeters = 5 * Int((distance / 5.0).rounded())
            return "\(roundedMeters) meters"
        }
    }

    private func handleDestinationArrival() {
        let announcement =
            "You have arrived at your destination, \(locationManager.targetLocation.address). Navigation completed successfully."

        speechManager.clearQueueAndSpeak(announcement)

        shouldDismiss = true
    }

    private func announceNavigationEnded() {
        speechManager.clearQueueAndSpeak("Navigation ended.")
    }

    private func enterImmersiveMode() {
        Task {
            switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
            case .opened:
                isInImmersiveMode = true
                realityKitModel.immersiveSpaceIsShown = true
            case .error, .userCancelled:
                isInImmersiveMode = false
                realityKitModel.immersiveSpaceIsShown = false
            @unknown default:
                break
            }
        }
    }

    private func exitImmersiveMode() {
        Task {
            await dismissImmersiveSpace()
            isInImmersiveMode = false
            realityKitModel.immersiveSpaceIsShown = false
        }
    }

    private var navigationContentView: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: {
                    locationManager.stopNavigation()
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.black)
                }

                Spacer()

                Text("Walking Navigation")
                    .font(.headline)
                    .foregroundColor(appModel.almostWhite)

                Spacer()

                Button(action: {
                    locationManager.voiceGuidanceEnabled.toggle()
                }) {
                    Image(
                        systemName: locationManager.voiceGuidanceEnabled
                            ? "speaker.wave.2.fill" : "speaker.slash.fill"
                    )
                    .font(.title2)
                    .foregroundColor(.black)
                }
            }
            .padding()
            .background(appModel.outdoorColor)
            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("Destination")
                    .font(.subheadline)
                    .foregroundColor(appModel.almostWhite)

                Text(locationManager.targetLocation.address)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundColor(appModel.almostWhite)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(appModel.outdoorColor)

            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Remaining Distance")
                        .font(.caption)
                        .foregroundColor(appModel.almostWhite)

                    Text(locationManager.formatDistance(locationManager.remainingDistance))
                        .font(.headline)
                        .foregroundColor(appModel.almostWhite)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("Estimated Arrival")
                        .font(.caption)
                        .foregroundColor(appModel.almostWhite)

                    Text(locationManager.formatEstimatedArrivalTime())
                        .font(.headline)
                        .foregroundColor(appModel.almostWhite)
                }
            }
            .padding()
            .background(appModel.outdoorColor)
            .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)

            RouteMapView()
                .frame(height: 250)
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)

            ScrollView {
                VStack(spacing: 0) {
                    if locationManager.isNavigating && !locationManager.routeSteps.isEmpty {
                        ForEach(
                            locationManager.currentStepIndex..<locationManager.routeSteps.count,
                            id: \.self
                        ) { stepIndex in
                            let step = locationManager.routeSteps[stepIndex]
                            let isCurrentStep = stepIndex == locationManager.currentStepIndex

                            NavigationStepView(
                                step: step,
                                isCurrentStep: isCurrentStep,
                                stepNumber: stepIndex + 1,
                                distance: isCurrentStep
                                    ? locationManager.distanceToNextStep : step.distance
                            )
                            .padding(.vertical, 10)
                            .padding(.horizontal)
                            .background(
                                isCurrentStep ? appModel.sandColor : appModel.outdoorColor)
                        }
                    } else {
                        Text("Preparing your route...")
                            .foregroundColor(appModel.almostWhite)
                            .padding()
                    }
                }
            }
            .background(appModel.outdoorColor)

            VStack(spacing: 12) {
                Text(locationManager.currentInstruction)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(appModel.almostWhite)
                    .foregroundColor(.black)
                    .cornerRadius(8)
                    .accessibilityLabel("Current instruction")
                    .accessibilityValue(locationManager.currentInstruction)
                    .accessibilityAddTraits(.startsMediaSession)
                    .accessibilityHint("Your next navigation step")

                HStack {
                    Button(action: {
                        speechManager.stopSpeaking()

                        if locationManager.currentStepIndex < locationManager.routeSteps.count {
                            let currentStep = locationManager.routeSteps[
                                locationManager.currentStepIndex]
                            let distance = locationManager.distanceToNextStep

                            let announcement =
                                "Current instruction: \(currentStep.instructions). Distance remaining: \(formatDistanceForSpeech(distance))."

                            speechManager.addToQueue(announcement)
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Replay Instruction")
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                    }
                    .accessibilityLabel("Replay current instruction")
                    .accessibilityHint("Hear the current navigation instruction again")

                    Button(action: {
                        announceNavigationEnded()

                        exitImmersiveMode()

                        locationManager.stopNavigation()

                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }) {
                        HStack {
                            Image(systemName: "xmark")
                            Text("End Navigation")
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .foregroundColor(Color.red)
                        .cornerRadius(8)
                    }
                }
            }
            .padding()
            .background(appModel.outdoorColor)
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: -2)
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(true)
        .background(appModel.outdoorColor.ignoresSafeArea())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Navigation in progress")
        .accessibilityValue(
            "Current instruction: \(locationManager.currentInstruction). Distance: \(locationManager.formatDistance(locationManager.distanceToNextStep))"
        )
        .accessibilityHint("Double tap to hear the current instruction again")
    }

    struct NavigationStepView: View {
        let step: MKRoute.Step
        let isCurrentStep: Bool
        let stepNumber: Int
        let distance: CLLocationDistance

        var body: some View {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isCurrentStep ? Color.blue : .white)
                        .frame(width: 36, height: 36)

                    Text("\(stepNumber)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(isCurrentStep ? .black : .black)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(step.instructions.simplifiedForNavigation())
                        .font(.body)
                        .fontWeight(isCurrentStep ? .semibold : .regular)
                        .foregroundColor(isCurrentStep ? .black : .white)
                        .fixedSize(horizontal: false, vertical: true)

                    if distance > 0 {
                        HStack {
                            Image(systemName: "arrow.forward")
                                .font(.caption)

                            Text(formatDistance(distance))
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                    }
                }

                Spacer()

                directionIcon()
                    .font(.title3)
                    .foregroundColor(isCurrentStep ? .blue : .white)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Navigation step \(stepNumber)")
            .accessibilityValue(step.instructions)
            .accessibilityHint(
                isCurrentStep
                    ? "Current step, \(formatDistanceForAccessibility(distance)) remaining"
                    : "Upcoming step")
        }

        private func formatDistanceForAccessibility(_ distance: CLLocationDistance) -> String {
            if distance >= 1000 {
                let km = distance / 1000
                return "\(Int(km)) kilometer\(km >= 2 ? "s" : "")"
            } else {
                return "\(Int(distance)) meters"
            }
        }

        private func directionIcon() -> some View {
            let instructions = step.instructions.lowercased()

            if instructions.contains("turn right") || instructions.contains("right turn") {
                return Image(systemName: "arrow.turn.up.right")
            } else if instructions.contains("turn left") || instructions.contains("left turn") {
                return Image(systemName: "arrow.turn.up.left")
            } else if instructions.contains("continue") || instructions.contains("straight") {
                return Image(systemName: "arrow.up")
            } else if instructions.contains("arrive") || instructions.contains("destination") {
                return Image(systemName: "mappin.circle")
            } else {
                return Image(systemName: "arrow.up")
            }
        }

        private func formatDistance(_ distance: CLLocationDistance) -> String {
            if distance >= 1000 {
                return String(format: "%.1f km", distance / 1000)
            } else {
                return String(format: "%.0f m", distance)
            }
        }
    }
}
