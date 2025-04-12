import ARKit

extension GeometrySource {
    @MainActor func asArray<T>(ofType: T.Type) -> [T] {
        assert(
            MemoryLayout<T>.stride == stride,
            "Invalid stride \(MemoryLayout<T>.stride); expected \(stride)")
        return (0..<self.count).map {
            buffer.contents().advanced(by: offset + stride * Int($0)).assumingMemoryBound(
                to: T.self
            ).pointee
        }
    }
    @MainActor func asSIMD3<T>(ofType: T.Type) -> [SIMD3<T>] {
        return asArray(ofType: (T, T, T).self).map { .init($0.0, $0.1, $0.2) }
    }
}
