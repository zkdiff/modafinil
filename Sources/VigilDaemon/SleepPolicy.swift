import Foundation
import VigilShared

/// Permanent sleep-prevention policy. Unlike Modafinil, this never auto-disables.
struct SleepPolicy {
    private let fileManager = FileManager.default
    private let markerURL = URL(fileURLWithPath: VigilConstants.policyEnabledMarkerPath)
    private let savedSettingsURL = URL(fileURLWithPath: VigilConstants.savedSettingsPath)

    /// Keys we manage under `pmset -a`. Display sleep is intentionally left alone
    /// so the panel can turn off with the lid closed.
    private let managedKeys = [
        "disablesleep",
        "sleep",
        "disksleep",
        "standby",
        "autopoweroff"
    ]

    private let enforcedValues: [String: String] = [
        "disablesleep": "1",
        "sleep": "0",
        "disksleep": "0",
        "standby": "0",
        "autopoweroff": "0"
    ]

    var isMarkerPresent: Bool {
        fileManager.fileExists(atPath: markerURL.path)
    }

    func isSleepCurrentlyDisabled() throws -> Bool {
        let output = try Shell.run("/usr/bin/pmset", ["-g"])
        return output
            .split(separator: "\n")
            .first { $0.contains("SleepDisabled") }?
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .last == "1"
    }

    func ensureApplied() throws {
        if !isMarkerPresent {
            try saveCurrentSettingsIfNeeded()
        }

        try applyEnforcedSettings()
        try writeMarker()
    }

    func disableAndRestore() throws {
        try restoreSavedSettingsOrDefaults()
        removeMarker()
        removeSavedSettings()
    }

    private func applyEnforcedSettings() throws {
        for (key, value) in enforcedValues {
            try Shell.run("/usr/bin/pmset", ["-a", key, value])
        }
    }

    private func saveCurrentSettingsIfNeeded() throws {
        if fileManager.fileExists(atPath: savedSettingsURL.path) {
            return
        }

        let custom = try readCustomSettings()
        var snapshot: [String: String] = [:]
        for key in managedKeys {
            if let value = custom[key] {
                snapshot[key] = value
            }
        }

        let directory = savedSettingsURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: savedSettingsURL, options: .atomic)
    }

    private func restoreSavedSettingsOrDefaults() throws {
        let snapshot = loadSavedSettings() ?? [:]

        // Always clear the hard "never sleep" bit first.
        try Shell.run("/usr/bin/pmset", ["-a", "disablesleep", snapshot["disablesleep"] ?? "0"])

        let defaults: [String: String] = [
            "sleep": "1",
            "disksleep": "10",
            "standby": "1",
            "autopoweroff": "1"
        ]

        for key in managedKeys where key != "disablesleep" {
            let value = snapshot[key] ?? defaults[key] ?? "0"
            try Shell.run("/usr/bin/pmset", ["-a", key, value])
        }
    }

    private func loadSavedSettings() -> [String: String]? {
        guard let data = try? Data(contentsOf: savedSettingsURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else {
            return nil
        }
        return object
    }

    private func readCustomSettings() throws -> [String: String] {
        let output = try Shell.run("/usr/bin/pmset", ["-g", "custom"])
        var result: [String: String] = [:]

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasSuffix(":"), !trimmed.hasPrefix("Battery"), !trimmed.hasPrefix("AC") else {
                continue
            }

            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2 else { continue }
            let key = String(parts[0])
            let value = String(parts[1])
            result[key] = value
        }

        return result
    }

    private func writeMarker() throws {
        let directory = markerURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: markerURL, options: .atomic)
    }

    private func removeMarker() {
        try? fileManager.removeItem(at: markerURL)
    }

    private func removeSavedSettings() {
        try? fileManager.removeItem(at: savedSettingsURL)
    }
}
