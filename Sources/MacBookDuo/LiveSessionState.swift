import Foundation

/// User intent survives capture teardown; independent sleep notifications are balanced.
struct LiveSessionState {
    enum Suspension: Hashable { case system, display, session }
    private(set) var enabled: Bool
    var automaticResume: Bool
    private(set) var suspensions = Set<Suspension>()
    private(set) var recoveryPending: Bool

    init(enabled: Bool = false, automaticResume: Bool = true) {
        self.enabled = enabled
        self.automaticResume = automaticResume
        self.recoveryPending = enabled
    }
    var suspended: Bool { !suspensions.isEmpty }
    var canRecover: Bool { enabled && automaticResume && recoveryPending && !suspended }
    mutating func enable() { enabled = true; recoveryPending = true }
    mutating func disable() { enabled = false; recoveryPending = false }
    mutating func suspend(_ reason: Suspension) {
        suspensions.insert(reason)
        if !automaticResume { disable() }
        else { recoveryPending = enabled }
    }
    mutating func resume(_ reason: Suspension) { suspensions.remove(reason) }
    mutating func interrupted() { recoveryPending = enabled }
    mutating func streaming() { recoveryPending = false }
}
