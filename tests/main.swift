import Foundation
var failures = 0
func check(_ value: Bool, _ message: String) { print("\(value ? "PASS" : "FAIL"): \(message)"); if !value { failures += 1 } }
var detector = ScratchDetector()
check(!detector.update(time: 0, hands: [:]), "No hand does not alert")
let hand = ["left": MotionPoint(x: 0.4, y: 0.8)]
check(detector.update(time: 0.06, hands: hand), "First near-head frame alerts immediately")
check(!detector.update(time: 0.12, hands: hand), "Cooldown prevents duplicate alerts")
check(detector.update(time: 4.06, hands: hand), "Persistent proximity repeats after four seconds")
check(!detector.update(time: 10, hands: [:]), "Hands away never alerts")
detector.reset()
check(detector.update(time: 10.06, hands: hand), "Restart is immediately ready")
exit(failures == 0 ? 0 : 1)
