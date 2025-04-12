import AVFoundation
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @StateObject private var locationManager = LocationManager()

    enum Destination { case outdoor, obstacle }
    @State private var navigationPath = NavigationPath()
    @State private var isFirstAppear = true

    private let speechSynthesizer = AVSpeechSynthesizer()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {

                appModel.backgroundColor
                    .ignoresSafeArea()

                VStack(spacing: 50) {
                    NavigationButton(
                        color: appModel.outdoorColor,
                        text: "Outdoor Navigation",
                        action: {
                            navigationPath.append(Destination.outdoor)
                        }
                    )
                    .accessibilityLabel("Outdoor Navigation Button")
                    .accessibilityHint("Tap to start outdoor navigation mode")

                    NavigationButton(
                        color: appModel.obstacleColor,
                        text: "Obstacle Avoidance",
                        action: {
                            navigationPath.append(Destination.obstacle)
                        }
                    )
                    .accessibilityLabel("Obstacle Avoidance Button")
                    .accessibilityHint("Tap to start obstacle avoidance mode")
                }
            }
            .navigationTitle("Mode Selection")
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .outdoor:
                    NavigationMode()
                        .environment(appModel)
                        .environmentObject(locationManager)
                case .obstacle:
                    ObstacleAvoidanceMode()
                        .environment(appModel)
                        .environmentObject(locationManager)
                }
            }
            .onAppear {
                if isFirstAppear {

                    speakWelcomeMessage()
                    isFirstAppear = false
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Eyes On You App")
            .accessibilityHint("Select one of the two navigation modes")
        }
    }

    private func speakWelcomeMessage() {

        if !UIAccessibility.isVoiceOverRunning {
            let welcomeText =
                "Welcome to Eyes On You. This is an outdoor navigation assistance app with safety feedback. You can select the top button for Outdoor Navigation, or the bottom button for Obstacle Avoidance."

            let utterance = AVSpeechUtterance(string: welcomeText)
            utterance.rate = 0.6
            utterance.pitchMultiplier = 1.0
            utterance.volume = 1.0
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

            speechSynthesizer.speak(utterance)
        }
    }
}

struct NavigationButton: View {
    let color: Color
    let text: String
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(color)
            .frame(width: 400, height: 200)
            .overlay(
                Text(text)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(isPressed ? 0.95 : 1.0)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.interactiveSpring(), value: isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in
                        isPressed = false
                        action()
                    }
            )
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
        .environmentObject(LocationManager())
}
