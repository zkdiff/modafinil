import Foundation
import VigilShared

final class DaemonService: NSObject, NSXPCListenerDelegate {
    private let listener = NSXPCListener(machServiceName: VigilConstants.daemonMachServiceName)
    private let stateQueue = DispatchQueue(label: "com.narcotic.vigil.daemon.state")
    private let policy = SleepPolicy()
    private let lidMonitor = LidMonitor()
    private let reassertInterval: TimeInterval = 60
    private var reassertTimer: DispatchSourceTimer?
    private var policyActive = false

    override init() {
        super.init()
        listener.setConnectionCodeSigningRequirement(VigilConstants.appSigningRequirement)
        listener.delegate = self
    }

    func run() {
        do {
            try lidMonitor.start()
        } catch {
            NSLog("VigilDaemon could not start lid monitor: \(error.localizedDescription)")
        }

        // Re-apply only if we already own the policy (marker on disk).
        // Fresh install waits for the app to call ensurePolicyApplied; explicit
        // disable removes the marker so a restart must not turn prevention back on.
        stateQueue.sync {
            if self.policy.isMarkerPresent {
                self.applyPolicyLocked(reason: "startup")
            } else {
                NSLog("VigilDaemon started without active policy marker")
            }
        }

        startReassertTimer()
        listener.resume()
        NSLog("VigilDaemon listening")
        RunLoop.current.run()
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        let session = DaemonSession(service: self)
        newConnection.exportedInterface = NSXPCInterface(with: VigilDaemonProtocol.self)
        newConnection.exportedObject = session
        newConnection.resume()
        return true
    }

    fileprivate func ensurePolicyApplied(withReply reply: @escaping (Bool, String?) -> Void) {
        stateQueue.async {
            do {
                try self.policy.ensureApplied()
                self.policyActive = true
                self.lidMonitor.setEnabled(true)
                self.lidMonitor.turnDisplayOffIfNeeded()
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    fileprivate func getPolicyStatus(withReply reply: @escaping (Bool, Bool, String?) -> Void) {
        stateQueue.async {
            do {
                let disabled = try self.policy.isSleepCurrentlyDisabled()
                let active = disabled && self.policy.isMarkerPresent
                reply(true, active, nil)
            } catch {
                reply(false, false, error.localizedDescription)
            }
        }
    }

    fileprivate func disablePolicy(withReply reply: @escaping (Bool, String?) -> Void) {
        stateQueue.async {
            do {
                try self.policy.disableAndRestore()
                self.policyActive = false
                self.lidMonitor.setEnabled(false)
                NSLog("VigilDaemon disabled permanent sleep-prevention policy")
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    private func applyPolicyLocked(reason: String) {
        do {
            try policy.ensureApplied()
            policyActive = true
            lidMonitor.setEnabled(true)
            lidMonitor.turnDisplayOffIfNeeded()
            NSLog("VigilDaemon applied sleep-prevention policy (%@)", reason)
        } catch {
            policyActive = false
            NSLog("VigilDaemon failed to apply policy (%@): %@", reason, error.localizedDescription)
        }
    }

    private func startReassertTimer() {
        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now() + reassertInterval, repeating: reassertInterval, leeway: .seconds(5))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            // Keep asserting while we own the machine. Do not "clean up" on idle.
            if self.policy.isMarkerPresent || self.policyActive {
                self.applyPolicyLocked(reason: "reassert")
            }
        }
        reassertTimer = timer
        timer.resume()
    }
}

private final class DaemonSession: NSObject, VigilDaemonProtocol {
    private weak var service: DaemonService?

    init(service: DaemonService) {
        self.service = service
    }

    func ensurePolicyApplied(withReply reply: @escaping (Bool, String?) -> Void) {
        guard let service else {
            reply(false, "The daemon service is unavailable.")
            return
        }
        service.ensurePolicyApplied(withReply: reply)
    }

    func getPolicyStatus(withReply reply: @escaping (Bool, Bool, String?) -> Void) {
        guard let service else {
            reply(false, false, "The daemon service is unavailable.")
            return
        }
        service.getPolicyStatus(withReply: reply)
    }

    func disablePolicy(withReply reply: @escaping (Bool, String?) -> Void) {
        guard let service else {
            reply(false, "The daemon service is unavailable.")
            return
        }
        service.disablePolicy(withReply: reply)
    }
}
