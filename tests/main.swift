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
detector.reset()
check(detector.update(time: 20, hands: hand), "Initial touch alerts")
check(!detector.update(time: 20.1, hands: [:]), "Leaving head rearms without alert")
check(detector.update(time: 20.2, hands: hand), "Returning before cooldown immediately alerts")
check(!detector.update(time: 20.3, hands: hand), "Holding hand does not alert every frame")
check(!detector.update(time: 24.1, hands: hand), "Repeat interval starts at latest entry")
check(detector.update(time: 24.2, hands: hand), "Held touch repeats four seconds after entry")
exit(failures == 0 ? 0 : 1)
