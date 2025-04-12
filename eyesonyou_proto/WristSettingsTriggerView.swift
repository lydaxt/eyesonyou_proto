import SwiftUI

struct WristSettingsTriggerView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Button {

            self.dismissWindow(id: "main")

            Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in

                self.openWindow(id: "settings-panel")
            }
        } label: {
            VStack {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white)

                Text("Settings")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding()
            .background(Color.blue.opacity(0.8))
            .cornerRadius(15)
        }
        .buttonStyle(.plain)
        .frame(width: 200, height: 100)
    }
}
