import Foundation

enum EffectMath {
    static func progress(angle: Double, endpoint: Double) -> Double {
        guard angle.isFinite, endpoint.isFinite else { return 1 }
        return min(1, max(0, angle / max(20, endpoint)))
    }
    static func eased(_ value: Double) -> Double { value * value * (3 - 2 * value) }
    static func decode(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 3, bytes[0] == 1 else { return nil }
        let value = Int(bytes[1]) | (Int(bytes[2]) << 8)
        return (0...180).contains(value) ? Double(value) : nil
    }
}
