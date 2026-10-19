import CoreGraphics
import Foundation

private final class CheckOutput: ProbeOutput {
    var receivedDown = 0
    var receivedUp = 0
    var healthy = true
    var acknowledge = true
    var held = false
    var downs = 0
    var ups = 0
    func prepare(_ mode: ProbeMode) -> Bool { receivedDown = 0; receivedUp = 0; return healthy }
    func press() -> Bool {
        precondition(!held); held = true; downs += 1
        if acknowledge { receivedDown += 1 }; return true
    }
    func release() {
        precondition(held); held = false; ups += 1
        if acknowledge { receivedUp += 1 }
    }
    func close() {}
}

enum ProbeChecks {
    static func run() {
        for scenario in ["complete", "no-ack", "filter-failed", "focus-lost", "stop-held"] {
            var time: TimeInterval = 0
            let output = CheckOutput()
            let session = ProbeSession(output: output, now: { time }, interval: { 0.1 })
            precondition(session.start(.background))
            time = 7.9; session.tick(); precondition(output.downs == 0)
            if scenario == "no-ack" { output.acknowledge = false }
            time = 8; session.tick(); precondition(output.downs == 1)
            if scenario == "filter-failed" { output.healthy = false }
            if scenario == "focus-lost" { session.gate = { _ in "focus" } }
            if scenario == "stop-held" { session.stop() }
            for _ in 0..<2500 { time += 0.01; session.tick() }
            precondition(!session.busy && !output.held && output.downs == output.ups)
            precondition(output.downs == (scenario == "complete" ? 100 : 1))
            precondition(session.passed == (scenario == "complete"))
        }
        let event = CGEvent(keyboardEventSource: nil, virtualKey: ProbeTransport.key, keyDown: true)!
        event.setIntegerValueField(.eventSourceUserData, value: 42)
        precondition(ProbeTransport.matches(event, tag: 42))
        precondition(!ProbeTransport.matches(event, tag: 43))
        event.setIntegerValueField(.keyboardEventKeycode, value: 0)
        precondition(!ProbeTransport.matches(event, tag: 42))
        print("PASS: 100 pairs, missing ack, filter failure, focus loss, held-key stop, selective matching; no events posted.")
    }
}
