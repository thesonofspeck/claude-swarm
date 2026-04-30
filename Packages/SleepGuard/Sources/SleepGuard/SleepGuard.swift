import Foundation
import IOKit
import IOKit.pwr_mgt
import IOKit.ps

/// Holds a PreventUserIdleSystemSleep assertion for as long as it is
/// `engaged` AND the policy says it should be on. Policy: assertion is held
/// when ≥1 paired device is active AND the Mac is on AC power (don't drain
/// laptop batteries). Caller toggles `engaged`; SleepGuard handles release.
public actor SleepGuard {
    public struct State: Equatable, Sendable {
        public var engaged: Bool        // are any iOS devices paired/online?
        public var onACPower: Bool
        public var honourBattery: Bool  // when false, hold even on battery
        public var heldAssertion: Bool  // observable for the UI
    }

    public private(set) var state: State

    private var assertionId: IOPMAssertionID = 0
    private var powerSource: CFRunLoopSource?
    private let reason: String

    public init(reason: String = "Claude Swarm — paired iPhone is online", honourBattery: Bool = true) {
        self.state = State(
            engaged: false,
            onACPower: SleepGuard.checkACPower(),
            honourBattery: honourBattery,
            heldAssertion: false
        )
        self.reason = reason
        startObservingPower()
    }

    deinit {
        if assertionId != 0 {
            IOPMAssertionRelease(assertionId)
        }
    }

    public func setEngaged(_ engaged: Bool) {
        state.engaged = engaged
        reconcile()
    }

    public func setHonourBattery(_ value: Bool) {
        state.honourBattery = value
        reconcile()
    }

    private func reconcile() {
        let shouldHold = state.engaged && (!state.honourBattery || state.onACPower)
        if shouldHold && !state.heldAssertion {
            assertionId = createAssertion(reason: reason)
            state.heldAssertion = (assertionId != 0)
        } else if !shouldHold && state.heldAssertion {
            IOPMAssertionRelease(assertionId)
            assertionId = 0
            state.heldAssertion = false
        }
    }

    // MARK: - Power source observation

    private nonisolated static func checkACPower() -> Bool {
        guard let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snap)?.takeRetainedValue() as? [CFTypeRef] else {
            return true   // assume yes; better to keep awake than not
        }
        for src in sources {
            if let info = IOPSGetPowerSourceDescription(snap, src)?.takeUnretainedValue() as? [String: Any],
               let state = info[kIOPSPowerSourceStateKey] as? String {
                if state == kIOPSACPowerValue { return true }
            }
        }
        return false
    }

    private func startObservingPower() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { ctx in
            guard let ctx else { return }
            let me = Unmanaged<SleepGuard>.fromOpaque(ctx).takeUnretainedValue()
            Task { await me.refreshACPower() }
        }
        if let runLoopSource = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
            self.powerSource = runLoopSource
        }
    }

    private func refreshACPower() {
        state.onACPower = SleepGuard.checkACPower()
        reconcile()
    }

    private func createAssertion(reason: String) -> IOPMAssertionID {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        return result == kIOReturnSuccess ? id : 0
    }
}
