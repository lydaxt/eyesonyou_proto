import RealityKit
import SwiftUI

struct ImmersiveView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(AppModel.self) private var appModel

    @State private var model = ARKitModel()
    @State private var wristAnchor: AnchorEntity?

    @State private var internalRealityKitModel = RealityKitModel()
    var externalModel: Binding<RealityKitModel>?

    private var realityKitModel: RealityKitModel {
        externalModel?.wrappedValue ?? internalRealityKitModel
    }

    init() {
        self._internalRealityKitModel = State(initialValue: RealityKitModel())
        self.externalModel = nil
    }

    init(realityKitModel: Binding<RealityKitModel>) {
        self.externalModel = realityKitModel
    }

    var body: some View {
        RealityView { content, attachments in
            content.add(self.model.entity)

            createSettingsAnchor(content: content, attachments: attachments)
        } update: { content, attachments in
            self.wristAnchor?.removeFromParent()
            createSettingsAnchor(content: content, attachments: attachments)
        } attachments: {
            Attachment(id: "window") {
                WristSettingsTriggerView()
            }
        }
        .task {
            await self.model.start(realityKitModel)
        }
        .onAppear {
            if externalModel != nil {
                externalModel!.wrappedValue.arModel = self.model
            } else {
                internalRealityKitModel.arModel = self.model
            }

            appModel.immersiveSpaceState = .open
        }
        .onDisappear {
            appModel.immersiveSpaceState = .closed
        }
    }

    func createSettingsAnchor(content: RealityViewContent, attachments: RealityViewAttachments) {
        guard let attachment = attachments.entity(for: "window") else {
            print("Could not find attachment")
            return
        }

        let anchor = AnchorEntity(.hand(.left, location: .wrist), trackingMode: .continuous)
        var transform = Transform()
        transform.translation.y = 0.1
        anchor.transform = transform

        anchor.addChild(attachment)

        content.add(anchor)
        self.wristAnchor = anchor
    }
}
