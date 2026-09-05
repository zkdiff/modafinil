import Foundation

@objc(VigilDaemonProtocol)
public protocol VigilDaemonProtocol {
    /// Ensures permanent sleep-prevention policy is applied.
    @objc(ensurePolicyAppliedWithReply:)
    func ensurePolicyApplied(withReply reply: @escaping (Bool, String?) -> Void)

    /// Returns whether the system currently has sleep disabled under our policy.
    @objc(getPolicyStatusWithReply:)
    func getPolicyStatus(withReply reply: @escaping (Bool, Bool, String?) -> Void)

    /// Disables the permanent policy and restores prior sleep settings when possible.
    @objc(disablePolicyWithReply:)
    func disablePolicy(withReply reply: @escaping (Bool, String?) -> Void)
}
