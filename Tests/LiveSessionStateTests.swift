import Foundation

@main struct LiveSessionStateTests {
    static func main() {
        var session = LiveSessionState()
        precondition(!session.canRecover)
        session.enable(); session.streaming()
        precondition(session.enabled && !session.canRecover)
        session.suspend(.display)
        session.suspend(.system)
        session.suspend(.system) // duplicate notifications must be idempotent
        session.suspend(.session)
        precondition(session.enabled && session.suspended && !session.canRecover)
        session.resume(.system)
        precondition(!session.canRecover, "Device wake alone must not capture a sleeping display")
        session.resume(.display)
        precondition(!session.canRecover, "Must wait until the user session is available")
        session.resume(.session)
        precondition(session.canRecover)
        session.streaming()
        session.resume(.display)
        precondition(!session.canRecover, "A second wake notification must not restart a live stream")

        session.interrupted()
        precondition(session.canRecover, "Temporary capture/sensor loss must recover")
        session.disable()
        session.resume(.system)
        session.resume(.display)
        session.interrupted()
        precondition(!session.canRecover && !session.enabled, "Emergency stop must survive queued retries")

        session.enable(); session.suspend(.system); session.disable(); session.resume(.system)
        precondition(!session.canRecover, "Manual stop during suspension must cancel wake intent")

        var optedOut = LiveSessionState(enabled: true, automaticResume: false)
        optedOut.suspend(.display); optedOut.resume(.display)
        precondition(!optedOut.enabled && !optedOut.canRecover)

        let relaunched = LiveSessionState(enabled: true)
        precondition(relaunched.canRecover, "Saved live intent must restore on app launch")
        precondition(!LiveSessionState(enabled: false).canRecover)
        print("PASS: combined sleep/session notifications, duplicate wake, automatic reconnect, stop cancellation, opt-out, saved intent.")
    }
}
