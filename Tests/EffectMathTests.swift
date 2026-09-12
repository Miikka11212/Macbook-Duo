import Foundation

@main struct EffectMathTests {
    static func main() {
        precondition(EffectMath.decode([1, 119, 0]) == 119)
        precondition(EffectMath.decode([1, 180, 0]) == 180)
        precondition(EffectMath.decode([1, 181, 0]) == nil)
        precondition(EffectMath.decode([7, 112, 46, 0, 0]) == nil)
        precondition(EffectMath.decode([1]) == nil)
        precondition(EffectMath.progress(angle: 0, endpoint: 120) == 0)
        precondition(EffectMath.progress(angle: 60, endpoint: 120) == 0.5)
        precondition(EffectMath.progress(angle: 120, endpoint: 120) == 1)
        precondition(EffectMath.progress(angle: 160, endpoint: 120) == 1)
        precondition(EffectMath.progress(angle: -5, endpoint: 120) == 0)
        precondition(EffectMath.progress(angle: .nan, endpoint: 120) == 1)
        precondition(EffectMath.progress(angle: 0, endpoint: 0).isFinite)
        var previous = 0.0
        for angle in 0...180 {
            let p = EffectMath.eased(EffectMath.progress(angle: Double(angle), endpoint: 120))
            precondition(p >= previous && p <= 1)
            previous = p
        }
        print("PASS: HID decoding, invalid reports, endpoint mapping, clamping, monotonic transition.")
    }
}
