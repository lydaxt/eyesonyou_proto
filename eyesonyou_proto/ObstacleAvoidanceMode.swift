import AVFoundation
import RealityKit
import SwiftUI

struct ObstacleAvoidanceMode: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    @State private var realityKitModel = RealityKitModel()
    @State private var isInImmersiveMode = false
    @State private var hasAnnouncedInstructions = false

    private static let sharedSpeechSynthesizer = AVSpeechSynthesizer()
    private var speechSynthesizer: AVSpeechSynthesizer { Self.sharedSpeechSynthesizer }

    private let obstacleColor = Color(red: 0.4, green: 0.35, blue: 0.3)

    var body: some View {
        ZStack {
            obstacleColor.ignoresSafeArea()

            VStack(spacing: 25) {
                TitleView()

                VisualizationButton(
                    isInImmersiveMode: $isInImmersiveMode,
                    onTap: toggleImmersiveMode
                )

                SettingsPanelView(realityKitModel: $realityKitModel)
            }
        }
        .navigationTitle("Obstacle Avoidance")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: appModel.immersiveSpaceState) { _, newValue in
            isInImmersiveMode = (newValue == .open)
        }
        .onAppear {
            realityKitModel.wireframe = false
            realityKitModel.proximityWarnings = true
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("Failed to configure audio session: \(error)")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                announceObstacleAvoidanceInstructions()
            }
        }
        .onDisappear {
            hasAnnouncedInstructions = false
        }
    }

    private func announceObstacleAvoidanceInstructions() {
        print("Attempting to announce instructions...")

        if !hasAnnouncedInstructions {
            if speechSynthesizer.isSpeaking {
                speechSynthesizer.stopSpeaking(at: .immediate)
            }

            let instructionText =
                "This is Obstacle Avoidance Mode. Select the center button to enter Enviroment Mapping, which will detect objects around you and provide audio warnings about obstacles in your path."

            print("Speaking instructions: \(instructionText)")

            DispatchQueue.main.async {
                self.speak(instructionText)
                self.hasAnnouncedInstructions = true
            }
        }
    }

    private func toggleImmersiveMode() {
        Task {
            if !isInImmersiveMode {
                switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                case .opened:
                    isInImmersiveMode = true
                    realityKitModel.immersiveSpaceIsShown = true
                    realityKitModel.proximityWarnings = realityKitModel.proximityWarnings

                    DispatchQueue.main.async {
                        self.announceVisualizationModeStarted()
                    }
                case .error, .userCancelled:
                    isInImmersiveMode = false
                    realityKitModel.immersiveSpaceIsShown = false
                @unknown default:
                    break
                }
            } else {
                await dismissImmersiveSpace()
                isInImmersiveMode = false
                realityKitModel.immersiveSpaceIsShown = false

                DispatchQueue.main.async {
                    self.announceVisualizationModeEnded()
                }
            }
        }
    }

    private func announceVisualizationModeStarted() {
        let announcement =
            "Enviroment Mapping started. You will receive audio warnings about obstacles in your path."
        speak(announcement)
    }

    private func announceVisualizationModeEnded() {
        speak("Enviroment Mapping ended.")
    }

    private func speak(_ text: String) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.speak(text)
            }
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.6
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        print("Starting speech: \(text)")
        speechSynthesizer.speak(utterance)
    }
}

struct TitleView: View {
    var body: some View {
        Text("Obstacle Avoidance Mode")
            .font(.largeTitle)
            .foregroundStyle(.white)
            .padding()
    }
}

struct VisualizationButton: View {
    @Binding var isInImmersiveMode: Bool
    var onTap: () -> Void
    @State private var isPressed = false

    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(isInImmersiveMode ? .red.opacity(0.8) : .blue.opacity(0.8))
            .frame(width: 300, height: 200)
            .overlay(
                VStack {
                    Image(systemName: isInImmersiveMode ? "eyeglasses.slash" : "eyeglasses")
                        .font(.system(size: 50))
                    Text(isInImmersiveMode ? "Exit Enviroment Mapping" : "Enter Enviroment Mapping")
                        .font(.title2)
                }
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
                        onTap()
                    }
            )
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

struct SettingsPanelView: View {
    @Binding var realityKitModel: RealityKitModel
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Environment Mapping Settings")
                .font(.headline)
                .foregroundStyle(.white)

            Toggle(
                isOn: Binding(
                    get: { self.realityKitModel.wireframe },
                    set: { value in
                        self.realityKitModel.wireframe = value

                        if let arModel = self.realityKitModel.arModel {
                            arModel.updateProximityMaterialProperties(self.realityKitModel)
                        }
                    })
            ) {
                Text("Display Polygons")
                    .foregroundStyle(.white)
            }

            Toggle(isOn: $realityKitModel.proximityWarnings) {
                Text("Proximity Warnings")
                    .foregroundStyle(.white)
            }

            Button("Exit environment mapping") {
                Task {
                    realityKitModel.immersiveSpaceIsShown = false
                }
            }
            .padding(.top, 20)
            .foregroundStyle(.red)
        }
        .padding()
        .background(Color(red: 0.3, green: 0.25, blue: 0.2))
        .cornerRadius(15)
        .padding(.horizontal)
    }
}
