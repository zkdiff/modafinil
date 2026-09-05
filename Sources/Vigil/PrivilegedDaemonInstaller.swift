import Foundation
import ServiceManagement
import VigilShared

final class PrivilegedDaemonInstaller {
    private let daemonService = SMAppService.daemon(plistName: VigilConstants.daemonPlistName)
    private let loginItemService = SMAppService.mainApp

    var daemonStatus: SMAppService.Status {
        daemonService.status
    }

    var loginItemStatus: SMAppService.Status {
        loginItemService.status
    }

    func registerDaemon() throws {
        try daemonService.register()
    }

    func unregisterDaemon() throws {
        try daemonService.unregister()
    }

    func registerLoginItem() throws {
        try loginItemService.register()
    }

    func unregisterLoginItem() throws {
        try loginItemService.unregister()
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
