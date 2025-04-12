import ARKit
import AVFoundation
import RealityKit
import Vision

enum MeshClassificationType: Int {
    case none = 0
    case wall = 1
    case floor = 2
    case ceiling = 3
    case table = 4
    case seat = 5
    case window = 6
    case door = 7
    case unknown = 8
}

@Observable final class ARKitModel {
    private let arSession = ARKitSession()
    private let sceneReconstructionProvider = SceneReconstructionProvider(modes: [.classification])

    let entity = Entity()

    private var activeShaderMaterial: Material?
    private var meshEntities: [UUID: OccludedEntityPair] = [:]

    private let speechManager = SpeechManager.shared
    private var lastWarningTime: TimeInterval = 0
    private let warningCooldown: TimeInterval = 3.0
    private let proximityThreshold: Float = 2.0
    private var enableProximityWarnings = false

    private var potentialHumans: [UUID: TimeInterval] = [:]
    private let humanConfirmationTime: TimeInterval = 1.0

    private var material: Material {
        let useWireframe = self.cachedSettings?.wireframe ?? false

        if var material = self.activeShaderMaterial as? ShaderGraphMaterial {
            material.triangleFillMode = useWireframe ? .lines : .fill
            return material
        } else {
            var material = SimpleMaterial(color: .red.withAlphaComponent(0.7), isMetallic: false)
            material.triangleFillMode = useWireframe ? .lines : .fill
            return material
        }
    }

    private var cachedSettings: RealityKitModel?

    func start(_ model: RealityKitModel) async {
        guard SceneReconstructionProvider.isSupported else {
            print("SceneReconstructionProvider not supported.")
            return
        }

        do {
            self.activeShaderMaterial = try await ShaderGraphMaterial(
                named: "/Root/ProximityMaterial", from: "Materials")
        } catch {
            print(error)
        }

        do {
            try await self.arSession.run([self.sceneReconstructionProvider])
            print("Started ARKit")

            self.setProximityWarnings(model.proximityWarnings)
            print("Proximity warnings set to: \(model.proximityWarnings)")

            self.updateProximityMaterialProperties(model)

            Task {
                await detectMovingObjects()
            }

            for await update in self.sceneReconstructionProvider.anchorUpdates {
                if Task.isCancelled {
                    print("Quit ARKit task")
                    return
                }

                await processMeshAnchorUpdate(update)
            }
        } catch {
            print("ARKit error \(error)")
        }
    }

    func updateProximityMaterialProperties(_ model: RealityKitModel) {
        guard var material = self.activeShaderMaterial as? ShaderGraphMaterial,
            material.name == "ProximityMaterial"
        else {
            print("Incorrect material")
            return
        }

        self.cachedSettings = model

        self.setProximityWarnings(model.proximityWarnings)

        do {
            print("Applying wireframe setting: \(model.wireframe)")
            material.triangleFillMode = model.wireframe ? .lines : .fill

            try material.setParameter(name: "Ripple", value: .bool(model.ripple))
            try material.setParameter(name: "UseCustomColor", value: .bool(false))
        } catch {
            print("Error setting material parameters: \(error)")
        }

        for pair in self.meshEntities.values {
            pair.primaryEntity.model?.materials = [material]
        }
    }

    func setProximityWarnings(_ enabled: Bool) {
        self.enableProximityWarnings = enabled
    }

    @MainActor
    private func processMeshAnchorUpdate(_ update: AnchorUpdate<MeshAnchor>) async {
        let meshAnchor = update.anchor

        let transform = Transform(matrix: meshAnchor.originFromAnchorTransform)

        switch update.event {
        case .added:
            let (primaryMesh, occlusionMesh) = try! self.generateMeshes(from: meshAnchor.geometry)

            let primaryEntity = ModelEntity(mesh: primaryMesh, materials: [self.material])

            let occlusionEntity = ModelEntity(
                mesh: occlusionMesh,
                materials: [OcclusionMaterial(), SimpleMaterial(color: .blue, isMetallic: false)])

            primaryEntity.transform = transform

            occlusionEntity.transform = transform

            self.meshEntities[meshAnchor.id] = OccludedEntityPair(
                primaryEntity: primaryEntity, occlusionEntity: occlusionEntity)
            self.entity.addChild(primaryEntity)
            self.entity.addChild(occlusionEntity)

            if let cachedSettings = self.cachedSettings {
                self.updateProximityMaterialProperties(cachedSettings)
            }

        case .updated:
            guard let pair = self.meshEntities[meshAnchor.id] else {
                return
            }

            pair.primaryEntity.transform = transform
            pair.occlusionEntity.transform = transform

            let (primaryMesh, occlusionMesh) = try! self.generateMeshes(from: meshAnchor.geometry)

            pair.primaryEntity.model?.mesh = primaryMesh
            pair.occlusionEntity.model?.mesh = occlusionMesh

        case .removed:
            if let pair = self.meshEntities[meshAnchor.id] {
                pair.primaryEntity.removeFromParent()
                pair.occlusionEntity.removeFromParent()
            }

            self.meshEntities.removeValue(forKey: meshAnchor.id)
        }

        checkProximityWarning(meshAnchor: meshAnchor)
    }

    @MainActor
    private func generateMeshes(from geometry: MeshAnchor.Geometry) throws -> (
        MeshResource, MeshResource
    ) {
        let primaryMesh = try generateMesh(from: geometry)
        let occlusionMesh = try generateMesh(
            from: geometry, with: { vertex, normal in -0.01 * normal + vertex })

        return (primaryMesh, occlusionMesh)
    }

    @MainActor
    private func generateMesh(
        from geometry: MeshAnchor.Geometry,
        with vertexTransform: ((_ vertex: SIMD3<Float>, _ normal: SIMD3<Float>) -> SIMD3<Float>)? =
            nil
    ) throws -> MeshResource {
        var desc = MeshDescriptor()
        let vertices = geometry.vertices.asSIMD3(ofType: Float.self)
        let normalValues = geometry.normals.asSIMD3(ofType: Float.self)

        let modifiedVertices =
            if let vertexTransform = vertexTransform {
                zip(vertices, normalValues).map { vertex, normal in
                    vertexTransform(vertex, normal)
                }
            } else {
                vertices
            }

        desc.positions = .init(modifiedVertices)
        desc.normals = .init(normalValues)
        desc.primitives = .polygons(
            (0..<geometry.faces.count).map { _ in UInt8(3) },
            (0..<geometry.faces.count * 3).map {
                geometry.faces.buffer.contents()
                    .advanced(by: $0 * geometry.faces.bytesPerIndex)
                    .assumingMemoryBound(to: UInt32.self).pointee
            }
        )

        return try MeshResource.generate(from: [desc])
    }

    @MainActor
    private func checkProximityWarning(meshAnchor: MeshAnchor) {
        if !enableProximityWarnings {
            return
        }

        let currentTime = Date().timeIntervalSince1970
        if currentTime - lastWarningTime > warningCooldown {
            let boundingBox = getBoundingBox(meshAnchor: meshAnchor)

            let centerPoint = (boundingBox.0 + boundingBox.1) * 0.5
            let worldCenter =
                meshAnchor.originFromAnchorTransform
                * SIMD4<Float>(centerPoint.x, centerPoint.y, centerPoint.z, 1)
            let objectPosition = SIMD3<Float>(worldCenter.x, worldCenter.y, worldCenter.z)

            let dimensions = boundingBox.1 - boundingBox.0
            let width = dimensions.x
            let height = dimensions.y
            let depth = dimensions.z

            let distanceFromDevice = length(objectPosition)

            let isHumanShaped = checkForHumanForm(meshAnchor: meshAnchor)
            let meshID = meshAnchor.id

            if isHumanShaped {
                if potentialHumans[meshID] == nil {
                    potentialHumans[meshID] = currentTime
                } else if currentTime - potentialHumans[meshID]! >= humanConfirmationTime {
                    speakWarning("Human detected nearby")
                    lastWarningTime = currentTime
                    return
                }
            } else {
                potentialHumans.removeValue(forKey: meshID)
            }

            let isLargeObstacle = (width * height > 1.0)
            let isCloseObstacle = distanceFromDevice < 1.5 && distanceFromDevice > 0.1

            var obstacleType = "obstacle"

            if let classification = getMeshClassification(meshAnchor) {
                obstacleType = getObstacleNameFromClassification(classification)
            }

            if isLargeObstacle && isCloseObstacle {
                let distanceInCm = Int(distanceFromDevice * 100)
                speakWarning("\(obstacleType) detected \(distanceInCm) centimeters ahead")
                lastWarningTime = currentTime
                return
            }

            if distanceFromDevice < proximityThreshold && distanceFromDevice > 0.1 {
                let distanceInCm = Int(distanceFromDevice * 100)

                if distanceInCm <= 200 {
                    speakWarning(
                        "\(obstacleType) detected approximately \(distanceInCm) centimeters away")
                    lastWarningTime = currentTime
                }
            }
        }
    }

    @MainActor
    private func getMeshClassification(_ meshAnchor: MeshAnchor) -> MeshClassificationType? {

        let boundingBox = getBoundingBox(meshAnchor: meshAnchor)
        let dimensions = boundingBox.1 - boundingBox.0
        let width = dimensions.x
        let height = dimensions.y
        let depth = dimensions.z

        if width > 2.0 && height > 2.0 && depth < 0.5 {
            return .wall
        } else if width > 1.0 && height < 0.2 && width > 1.0 {
            return .floor
        } else if width > 1.0 && height < 0.2 && boundingBox.1.y > 2.0 {
            return .ceiling
        } else if height < 1.0 && height > 0.7 && width > 0.5 && depth > 0.5 {
            return .table
        } else if height < 1.0 && height > 0.4 && width < 0.8 && depth < 0.8 {
            return .seat
        }

        return .unknown
    }

    private func getHighestConfidenceClassification(_ classifications: GeometrySource) -> Int? {
        return 0
    }

    private func getObstacleNameFromClassification(_ classification: MeshClassificationType)
        -> String
    {
        switch classification {
        case .wall:
            return "Wall"
        case .floor:
            return "Floor"
        case .ceiling:
            return "Ceiling"
        case .table:
            return "Table"
        case .seat:
            return "Chair or seat"
        case .window:
            return "Window"
        case .door:
            return "Door"
        default:
            return "Obstacle"
        }
    }

    func cleanup() {
    }

    @MainActor
    private func checkForHumanForm(meshAnchor: MeshAnchor) -> Bool {
        let boundingBox = getBoundingBox(meshAnchor: meshAnchor)
        let height = boundingBox.1.y - boundingBox.0.y
        let width = boundingBox.1.x - boundingBox.0.x
        let depth = boundingBox.1.z - boundingBox.0.z

        if height > 1.2 && height < 2.2
            && width > 0.25 && width < 1.0
            && depth > 0.1 && depth < 0.5
        {
            if let lastSeenTime = potentialHumans[meshAnchor.id] {
                let currentTime = Date().timeIntervalSince1970
                let timeDifference = currentTime - lastSeenTime

                if timeDifference < 1.0 {
                    return true
                }
            }

            return true
        }

        return false
    }

    @MainActor
    private func getBoundingBox(meshAnchor: MeshAnchor) -> (SIMD3<Float>, SIMD3<Float>) {
        let vertices = meshAnchor.geometry.vertices.asSIMD3(ofType: Float.self)

        var minX = Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var maxY = -Float.greatestFiniteMagnitude
        var maxZ = -Float.greatestFiniteMagnitude

        for vertex in vertices {
            minX = min(minX, vertex.x)
            minY = min(minY, vertex.y)
            minZ = min(minZ, vertex.z)
            maxX = max(maxX, vertex.x)
            maxY = max(maxY, vertex.y)
            maxZ = max(maxZ, vertex.z)
        }

        return (SIMD3<Float>(minX, minY, minZ), SIMD3<Float>(maxX, maxY, maxZ))
    }

    private func speakWarning(_ text: String) {
        print("Attempting to queue obstacle warning: \(text)")
        speechManager.addObstacleWarning(text)
    }

    @MainActor
    private func detectMovingObjects() async {
        var previousMeshPositions: [UUID: SIMD3<Float>] = [:]
        var movementScores: [UUID: Float] = [:]

        var meshVolumes: [UUID: Float] = [:]

        let checkInterval: TimeInterval = 0.5
        var lastCheckTime = Date().timeIntervalSince1970

        while !Task.isCancelled {
            let currentTime = Date().timeIntervalSince1970

            if currentTime - lastCheckTime > checkInterval {
                lastCheckTime = currentTime

                for (meshID, pair) in meshEntities {
                    let currentPosition = pair.primaryEntity.transform.translation

                    if meshVolumes[meshID] == nil, let modelMesh = pair.primaryEntity.model?.mesh {
                        let bounds = modelMesh.bounds
                        let dimensions = bounds.max - bounds.min
                        let volume = dimensions.x * dimensions.y * dimensions.z
                        meshVolumes[meshID] = volume
                    }

                    if let previousPosition = previousMeshPositions[meshID] {
                        let movement = length(currentPosition - previousPosition)

                        let currentScore = movementScores[meshID] ?? 0.0
                        let newScore = currentScore * 0.8 + movement * 5.0
                        movementScores[meshID] = newScore

                        let volume = meshVolumes[meshID] ?? 0
                        let isHumanSized = volume > 0.05 && volume < 2.0

                        if newScore > 1.0 && isHumanSized && enableProximityWarnings {
                            if currentTime - lastWarningTime > warningCooldown {
                                let distance = length(currentPosition)
                                if distance < proximityThreshold {
                                    let distanceInCm = Int(distance * 100)
                                    speakWarning(
                                        "Moving person detected \(distanceInCm) centimeters away")
                                    lastWarningTime = currentTime
                                }
                            }
                        } else if newScore > 2.0 && enableProximityWarnings {
                            if currentTime - lastWarningTime > warningCooldown {
                                let distance = length(currentPosition)
                                if distance < proximityThreshold {
                                    let distanceInCm = Int(distance * 100)
                                    speakWarning(
                                        "Moving object detected \(distanceInCm) centimeters away")
                                    lastWarningTime = currentTime
                                }
                            }
                        }
                    }
                    previousMeshPositions[meshID] = currentPosition
                }
                previousMeshPositions = previousMeshPositions.filter { meshEntities[$0.key] != nil }
                movementScores = movementScores.filter { meshEntities[$0.key] != nil }
                meshVolumes = meshVolumes.filter { meshEntities[$0.key] != nil }
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}

private struct OccludedEntityPair {
    let primaryEntity: ModelEntity
    let occlusionEntity: ModelEntity
}
