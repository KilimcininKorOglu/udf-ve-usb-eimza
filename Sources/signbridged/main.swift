import Foundation
import SignCore

// Entry point for the local signing daemon.
// Full server wiring lands in the LoopbackServer step.
print("signbridged \(SignBridgeInfo.version) starting on port \(SignBridgeInfo.port)")
