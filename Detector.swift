import Foundation

struct MotionPoint {
    var x: Double
    var y: Double
}

// Alert on the first frame containing a hand in the head region.
// Vision filters landmarks by confidence before passing them here.
struct ScratchDetector {
    var lastAlert = -Double.infinity
    var sensitivity = 0.5
    var cooldown = 4.0
    mutating func reset() { lastAlert = -Double.infinity }
    mutating func update(time: Double, hands: [String: MotionPoint]) -> Bool {
        guard !hands.isEmpty, time - lastAlert + 0.000001 >= cooldown else { return false }
        lastAlert = time
        return true
    }
}
