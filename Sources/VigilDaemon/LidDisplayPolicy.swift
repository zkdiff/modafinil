/// Emits one display-sleep request per activation or open-to-closed transition.
/// Periodic sleep-prevention refreshes preserve a remotely awakened display.
struct LidDisplayPolicy {
    private var enabled = false
    private var lidClosed: Bool?

    mutating func setEnabled(_ newValue: Bool, lidClosed currentLidClosed: Bool?) -> Bool {
        guard newValue != enabled else { return false }
        enabled = newValue
        lidClosed = currentLidClosed
        return enabled && currentLidClosed == true
    }

    mutating func lidChanged(isClosed: Bool) -> Bool {
        let wasClosed = lidClosed
        lidClosed = isClosed
        return enabled && isClosed && wasClosed != true
    }
}
