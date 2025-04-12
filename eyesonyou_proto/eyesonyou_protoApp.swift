//
//  eyesonyou_protoApp.swift
//  eyesonyou_proto
//
//  Created by Tat Yan Lam on 14/11/2024.
//

import SwiftUI

@main
struct eyesonyou_protoApp: App {
    @State private var appModel = AppModel()
    @State private var realityKitModel = RealityKitModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .frame(
                    minWidth: 800, maxWidth: 800,
                    minHeight: 1000, maxHeight: 1000)
        }
        .windowStyle(.plain)
        .defaultSize(width: 800, height: 1000)
        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView(realityKitModel: $realityKitModel)
                .environment(appModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)

        WindowGroup(id: "settings-panel") {
            SettingsPanelView(realityKitModel: $realityKitModel)
                .environment(appModel)
                .frame(minWidth: 400, minHeight: 300)
                .padding()
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultSize(width: 400, height: 300)
    }
}
