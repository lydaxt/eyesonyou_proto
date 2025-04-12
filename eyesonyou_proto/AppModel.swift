import SwiftUI

@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed

    let primaryColor = Color(red: 0.1, green: 0.1, blue: 0.1)
    let accentColor = Color(red: 0, green: 0.6, blue: 1)
    let backgroundColor = Color(red: 0.98, green: 0.98, blue: 0.98)
    let warningColor = Color(red: 0.9, green: 0.3, blue: 0.3)
    let almostWhite = Color(red: 0.95, green: 0.95, blue: 0.95)
    let outdoorColor = Color(red: 0.6, green: 0.45, blue: 0.3)
    let obstacleColor = Color(red: 0.4, green: 0.35, blue: 0.3)

    let sandColor = Color(red: 0.76, green: 0.7, blue: 0.5)
    let clayColor = Color(red: 0.8, green: 0.52, blue: 0.25)
    let soilColor = Color(red: 0.47, green: 0.33, blue: 0.28)
    let stoneColor = Color(red: 0.5, green: 0.5, blue: 0.5)
    let grassColor = Color(red: 0.48, green: 0.67, blue: 0.35)
    let pathColor = Color(red: 0.85, green: 0.8, blue: 0.7)
    let roadColor = Color(red: 0.65, green: 0.65, blue: 0.65)
    let sidewalkColor = Color(red: 0.9, green: 0.9, blue: 0.9)
}
