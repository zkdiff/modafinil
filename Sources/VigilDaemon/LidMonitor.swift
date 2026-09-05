import Foundation
import CoreGraphics
import IOKit
import IOKit.pwr_mgt
import VigilShared

private func errSystem(_ value: UInt32) -> UInt32 {
    (value & 0x3f) << 26
}

private func errSub(_ value: UInt32) -> UInt32 {
    (value & 0xfff) << 14
}

private func iokitFamilyMessage(subsystem: UInt32, message: UInt32) -> UInt32 {
    errSystem(0x38) | subsystem | message
}

private let vigilIOPMMessageClamshellStateChange = natural_t(
    iokitFamilyMessage(subsystem: errSub(13), message: 0x100)
)

/// Turns the display off when the lid closes while the system stays awake.
final class LidMonitor {
    private var rootDomain: io_service_t = IO_OBJECT_NULL
    private var notificationPort: IONotificationPortRef?
    private var notifier: io_object_t = IO_OBJECT_NULL
    private var displayPolicy = LidDisplayPolicy()

    deinit {
        stop()
    }

    func start() throws {
        guard rootDomain == IO_OBJECT_NULL else { return }

        rootDomain = Self.findRootDomain()
        guard rootDomain != IO_OBJECT_NULL else {
            throw MonitorError.rootDomainUnavailable
        }

        let port = IONotificationPortCreate(kIOMainPortDefault)
        guard let port else {
            IOObjectRelease(rootDomain)
            rootDomain = IO_OBJECT_NULL
            throw MonitorError.notificationPortUnavailable
        }
        notificationPort = port

        guard let runLoopSource = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() else {
            stop()
            throw MonitorError.runLoopSourceUnavailable
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let result = IOServiceAddInterestNotification(
            port,
            rootDomain,
            kIOGeneralInterest,
            { refcon, _, messageType, messageArgument in
                guard let refcon else { return }
                let monitor = Unmanaged<LidMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handlePowerMessage(messageType: messageType, messageArgument: messageArgument)
            },
            refcon,
            &notifier
        )

        guard result == KERN_SUCCESS else {
            stop()
            throw MonitorError.interestNotificationFailed(result)
        }
    }

    func stop() {
        if notifier != IO_OBJECT_NULL {
            IOObjectRelease(notifier)
            notifier = IO_OBJECT_NULL
        }

        if let notificationPort {
            IONotificationPortDestroy(notificationPort)
            self.notificationPort = nil
        }

        if rootDomain != IO_OBJECT_NULL {
            IOObjectRelease(rootDomain)
            rootDomain = IO_OBJECT_NULL
        }
    }

    func setEnabled(_ enabled: Bool) {
        // IOKit delivers lid events on the main run loop. Serialize activation
        // with those events so a policy refresh preserves the last lid state.
        DispatchQueue.main.async {
            if self.displayPolicy.setEnabled(enabled, lidClosed: self.isLidClosed()) {
                self.turnDisplayOffForLidClosure()
            }
        }
    }

    func isLidClosed() -> Bool? {
        guard rootDomain != IO_OBJECT_NULL else { return nil }

        guard let property = IORegistryEntryCreateCFProperty(
            rootDomain,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }

        guard CFGetTypeID(property) == CFBooleanGetTypeID() else {
            return nil
        }

        return CFBooleanGetValue((property as! CFBoolean))
    }

    private func handlePowerMessage(messageType: natural_t, messageArgument: UnsafeMutableRawPointer?) {
        guard messageType == vigilIOPMMessageClamshellStateChange else { return }

        let bits = UInt(bitPattern: messageArgument)
        let isClosed = (bits & UInt(kClamshellStateBit)) != 0

        if displayPolicy.lidChanged(isClosed: isClosed) {
            turnDisplayOffForLidClosure()
        }
    }

    private static func hasExternalDisplay() -> Bool {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
            return false
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &displays, &displayCount) == .success else {
            return false
        }

        return displays.prefix(Int(displayCount)).contains { display in
            Self.isExternalDisplay(display)
        }
    }

    private static func isExternalDisplay(_ display: CGDirectDisplayID) -> Bool {
        CGDisplayIsBuiltin(display) == 0
    }

    private func turnDisplayOffForLidClosure() {
        guard !Self.hasExternalDisplay() else { return }

        do {
            try Shell.run("/usr/bin/pmset", ["displaysleepnow"])
        } catch {
            NSLog("VigilDaemon failed to turn off the display: \(error.localizedDescription)")
        }
    }

    private static func findRootDomain() -> io_service_t {
        let matched = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )

        if matched != IO_OBJECT_NULL {
            return matched
        }

        return IORegistryEntryFromPath(
            kIOMainPortDefault,
            "IOService:/IOResources/IOPowerConnection/IOPMrootDomain"
        )
    }

    enum MonitorError: LocalizedError {
        case rootDomainUnavailable
        case notificationPortUnavailable
        case runLoopSourceUnavailable
        case interestNotificationFailed(kern_return_t)

        var errorDescription: String? {
            switch self {
            case .rootDomainUnavailable:
                return "Could not find IOPMrootDomain."
            case .notificationPortUnavailable:
                return "Could not create an IOKit notification port."
            case .runLoopSourceUnavailable:
                return "Could not create an IOKit run loop source."
            case .interestNotificationFailed(let code):
                return "Could not subscribe to clamshell notifications: 0x\(String(code, radix: 16))."
            }
        }
    }
}
