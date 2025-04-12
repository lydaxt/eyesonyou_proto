import SwiftUI

@Observable class RealityKitModel {
    weak var arModel: ARKitModel?

    var immersiveSpaceIsShown = false
    var ripple: Bool = false {
        didSet {
            self.arModel?.updateProximityMaterialProperties(self)
            UserDefaults.standard.setValue(self.ripple, forKey: "ripple")
        }
    }

    var wireframe = false {
        didSet {
            print("Wireframe changed to: \(wireframe)")
            self.arModel?.updateProximityMaterialProperties(self)
            UserDefaults.standard.setValue(self.wireframe, forKey: "wireframe")
        }
    }

    var proximityWarnings: Bool = true {
        didSet {
            self.arModel?.setProximityWarnings(self.proximityWarnings)
            UserDefaults.standard.setValue(self.proximityWarnings, forKey: "proximityWarnings")
        }
    }

    init() {
        self.wireframe = UserDefaults.standard.value(forKey: "wireframe") as? Bool ?? false
        self.proximityWarnings =
            UserDefaults.standard.value(forKey: "proximityWarnings") as? Bool ?? true
    }
}
