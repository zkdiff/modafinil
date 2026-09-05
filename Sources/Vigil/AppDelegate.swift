import AppKit
import ServiceManagement
import VigilShared

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let daemonClient = PrivilegedDaemonClient()
    private let installer = PrivilegedDaemonInstaller()

    private var statusItem: NSStatusItem!
    private var isPolicyActive = false
    private var isBusy = false
    private var lastError: String?
    private var daemonStatus: SMAppService.Status = .notRegistered
    private var isTerminatingAfterCleanup = false
    private var statusGeneration = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("Vigil applicationDidFinishLaunching")

        guard ensureRunningFromApplicationsAtLaunch() else {
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeft
            button.imageScaling = .scaleProportionallyDown
        }

        bootstrap()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isTerminatingAfterCleanup {
            return .terminateNow
        }

        // Quitting the menu bar app must NOT restore sleep — that is the permanent policy.
        isTerminatingAfterCleanup = true
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        daemonClient.invalidate()
    }

    @objc private func statusItemClicked() {
        showMenu()
    }

    private func bootstrap() {
        lastError = nil
        refreshDaemonStatus()
        ensureLoginItemRegistered()
        ensureDaemonRegisteredThenActivate()
    }

    private func ensureLoginItemRegistered() {
        guard installer.loginItemStatus != .enabled else { return }

        do {
            try installer.registerLoginItem()
        } catch {
            // Approval may still be required; surface later via status / settings.
            NSLog("Vigil could not register login item: \(error.localizedDescription)")
        }
    }

    private func ensureDaemonRegisteredThenActivate() {
        refreshDaemonStatus()

        if daemonStatus != .enabled {
            do {
                try installer.registerDaemon()
            } catch {
                if installer.daemonStatus != .enabled {
                    lastError = error.localizedDescription
                }
            }
            refreshDaemonStatus()
        }

        if daemonStatus == .requiresApproval {
            lastError = "Allow Vigil in Login Items & Extensions, then reopen if needed."
            refreshIcon()
            return
        }

        guard daemonStatus == .enabled else {
            lastError = lastError ?? "Vigil daemon is not enabled."
            refreshIcon()
            return
        }

        activatePolicy()
    }

    private func activatePolicy() {
        guard !isBusy else { return }
        isBusy = true
        statusGeneration += 1
        let generation = statusGeneration
        refreshIcon()

        daemonClient.ensurePolicyApplied { [weak self] result in
            guard let self else { return }
            guard generation == self.statusGeneration else { return }

            self.isBusy = false
            switch result {
            case .success:
                self.isPolicyActive = true
                self.lastError = nil
            case .failure(let error):
                self.isPolicyActive = false
                self.lastError = error.localizedDescription
            }
            self.refreshIcon()
        }
    }

    private func refreshStatus() {
        refreshDaemonStatus()
        statusGeneration += 1
        let generation = statusGeneration

        guard daemonStatus == .enabled else {
            isPolicyActive = false
            refreshIcon()
            return
        }

        daemonClient.getPolicyStatus { [weak self] result in
            guard let self else { return }
            guard generation == self.statusGeneration else { return }

            switch result {
            case .success(let active):
                self.isPolicyActive = active
                if !active {
                    // Policy drifted — re-apply. Permanent utility always wants on.
                    self.activatePolicy()
                    return
                }
            case .failure(let error):
                self.lastError = error.localizedDescription
            }
            self.refreshIcon()
        }
    }

    private func refreshDaemonStatus() {
        daemonStatus = installer.daemonStatus
    }

    private func refreshIcon() {
        let symbolName = isPolicyActive ? "bolt.fill" : "bolt.slash.fill"
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: isPolicyActive ? "Vigil active" : "Vigil inactive"
        )?.withSymbolConfiguration(configuration)
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true

        statusItem.button?.image = image
        statusItem.button?.imageScaling = .scaleProportionallyDown
        statusItem.button?.title = image == nil ? "A" : ""
        statusItem.length = NSStatusItem.squareLength
        statusItem.button?.toolTip = isPolicyActive
            ? "Mac will not sleep (Vigil)"
            : "Vigil is not active"
    }

    private func showMenu() {
        refreshDaemonStatus()
        refreshStatus()

        let menu = NSMenu()
        menu.autoenablesItems = false

        let statusText: String
        if isPolicyActive {
            statusText = "Status: Never Sleep (permanent)"
        } else if daemonStatus == .requiresApproval {
            statusText = "Status: Needs approval"
        } else {
            statusText = "Status: Not active"
        }

        let stateItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        let detailItem = NSMenuItem(
            title: "Sleep blocked on battery, AC, and all power sources",
            action: nil,
            keyEquivalent: ""
        )
        detailItem.isEnabled = false
        menu.addItem(detailItem)

        if let lastError {
            let errorItem = NSMenuItem(title: "Error: \(lastError)", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }

        menu.addItem(.separator())

        if !isPolicyActive {
            let activateItem = NSMenuItem(
                title: "Activate Never Sleep",
                action: #selector(activateFromMenu),
                keyEquivalent: ""
            )
            activateItem.target = self
            activateItem.isEnabled = !isBusy
            menu.addItem(activateItem)
        }

        let settingsItem = NSMenuItem(
            title: "Open Login Items & Extensions…",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let uninstallItem = NSMenuItem(
            title: "Disable & Uninstall Vigil…",
            action: #selector(uninstallApp),
            keyEquivalent: ""
        )
        uninstallItem.target = self
        uninstallItem.isEnabled = !isBusy
        menu.addItem(uninstallItem)

        let quitItem = NSMenuItem(
            title: "Quit Menu (keep never-sleep)",
            action: #selector(quitMenuOnly),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func activateFromMenu() {
        ensureDaemonRegisteredThenActivate()
    }

    @objc private func openSettings() {
        installer.openApprovalSettings()
    }

    @objc private func quitMenuOnly() {
        // Explicit: leave permanent policy running.
        isTerminatingAfterCleanup = true
        NSApp.terminate(nil)
    }

    @objc private func uninstallApp() {
        let alert = NSAlert()
        alert.messageText = "Disable & Uninstall Vigil?"
        alert.informativeText = """
        This turns sleep prevention off, restores normal power management, removes the background daemon and login item, and deletes Vigil from Applications.

        Until you do this, your Mac will not sleep — even after reboot.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Disable & Uninstall")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        lastError = nil
        isBusy = true
        setControlsEnabled(false)
        refreshIcon()

        let finishFailure: (Error) -> Void = { [weak self] error in
            guard let self else { return }
            self.isBusy = false
            self.lastError = error.localizedDescription
            self.setControlsEnabled(true)
            self.refreshDaemonStatus()
            self.refreshIcon()
            self.showError(title: "Uninstall Failed", message: error.localizedDescription)
        }

        let proceedWithUnregisterAndDelete: () -> Void = { [weak self] in
            guard let self else { return }

            do {
                try self.unregisterServicesIfNeeded()
                self.deleteAppBundleIfInstalledInApplications()
                self.isTerminatingAfterCleanup = true
                NSApp.terminate(nil)
            } catch {
                finishFailure(error)
            }
        }

        refreshDaemonStatus()
        if daemonStatus == .enabled {
            daemonClient.disablePolicy { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    self.isPolicyActive = false
                    proceedWithUnregisterAndDelete()
                case .failure(let error):
                    finishFailure(error)
                }
            }
        } else {
            proceedWithUnregisterAndDelete()
        }
    }

    private func unregisterServicesIfNeeded() throws {
        switch installer.daemonStatus {
        case .enabled, .requiresApproval:
            try installer.unregisterDaemon()
        case .notRegistered, .notFound:
            break
        @unknown default:
            break
        }

        switch installer.loginItemStatus {
        case .enabled, .requiresApproval:
            try installer.unregisterLoginItem()
        case .notRegistered, .notFound:
            break
        @unknown default:
            break
        }
    }

    private func setControlsEnabled(_ enabled: Bool) {
        statusItem?.button?.isEnabled = enabled
    }

    private func deleteAppBundleIfInstalledInApplications() {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        let applicationsURL = Self.applicationsDirectoryURL

        guard bundleURL.path.hasPrefix(applicationsURL.path + "/") else {
            return
        }

        let remover = Process()
        remover.executableURL = URL(fileURLWithPath: "/bin/sh")
        remover.arguments = [
            "-c",
            "sleep 1; /bin/rm -rf \"$1\"",
            "vigil-remover",
            bundleURL.path
        ]

        do {
            try remover.run()
        } catch {
            NSLog("Vigil could not start app bundle remover: \(error.localizedDescription)")
        }
    }

    private func ensureRunningFromApplicationsAtLaunch() -> Bool {
        if isRunningFromApplications {
            return true
        }

        let alert = NSAlert()
        alert.messageText = "Move Vigil to Applications"
        alert.informativeText = "Vigil must be run from /Applications. Move Vigil.app to /Applications, then open it again."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Quit")
        alert.runModal()

        isTerminatingAfterCleanup = true
        NSApp.terminate(nil)
        return false
    }

    private var isRunningFromApplications: Bool {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        let applicationsURL = Self.applicationsDirectoryURL.resolvingSymlinksInPath()
        return bundleURL.path.hasPrefix(applicationsURL.path + "/")
    }

    private static let applicationsDirectoryURL = URL(
        fileURLWithPath: "/Applications",
        isDirectory: true
    ).standardizedFileURL

    private func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
