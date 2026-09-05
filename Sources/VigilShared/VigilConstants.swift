import Foundation

public enum VigilConstants {
    public static let appBundleIdentifier = "com.narcotic.vigil"
    public static let daemonMachServiceName = "com.narcotic.vigil.daemon"
    public static let daemonPlistName = "com.narcotic.vigil.daemon.plist"
    // Must match the Team ID that signs Vigil.app (codesign -dv --verbose=4 … | grep TeamIdentifier).
    // Production / narcotic-sh: "3LF26Z4G2R". Local Apple Development (Daniel): "24MCKXYENJ".
    public static let teamIdentifier = "24MCKXYENJ"
    public static let appSigningRequirement = """
    anchor apple generic and identifier "\(appBundleIdentifier)" and certificate leaf[subject.OU] = "\(teamIdentifier)"
    """
    public static let supportDirectoryPath = "/Library/Application Support/Vigil"
    public static let policyEnabledMarkerPath = "\(supportDirectoryPath)/policy.enabled"
    public static let savedSettingsPath = "\(supportDirectoryPath)/saved-pmset.json"
}
