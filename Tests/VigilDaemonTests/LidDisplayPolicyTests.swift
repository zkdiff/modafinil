import XCTest
@testable import VigilDaemon

final class LidDisplayPolicyTests: XCTestCase {
    func testClosedLidActivationSleepsOnceAcrossRepeatedRefreshes() {
        var policy = LidDisplayPolicy()
        XCTAssertTrue(policy.setEnabled(true, lidClosed: true))
        for _ in 0..<10 {
            XCTAssertFalse(policy.setEnabled(true, lidClosed: true))
            XCTAssertFalse(policy.lidChanged(isClosed: true))
        }
    }

    func testOpenLidActivationAndEachSubsequentClosure() {
        var policy = LidDisplayPolicy()
        XCTAssertFalse(policy.setEnabled(true, lidClosed: false))
        XCTAssertTrue(policy.lidChanged(isClosed: true))
        XCTAssertFalse(policy.lidChanged(isClosed: true))
        XCTAssertFalse(policy.lidChanged(isClosed: false))
        XCTAssertTrue(policy.lidChanged(isClosed: true))
    }

    func testDisabledMonitorTracksLidWithoutSleeping() {
        var policy = LidDisplayPolicy()
        XCTAssertFalse(policy.lidChanged(isClosed: true))
        XCTAssertFalse(policy.lidChanged(isClosed: false))
        XCTAssertFalse(policy.lidChanged(isClosed: true))
        XCTAssertTrue(policy.setEnabled(true, lidClosed: true))
    }

    func testExplicitReactivationAppliesClosedLidPolicyOnce() {
        var policy = LidDisplayPolicy()
        XCTAssertTrue(policy.setEnabled(true, lidClosed: true))
        XCTAssertFalse(policy.setEnabled(false, lidClosed: true))
        XCTAssertFalse(policy.lidChanged(isClosed: true))
        XCTAssertTrue(policy.setEnabled(true, lidClosed: true))
        XCTAssertFalse(policy.setEnabled(true, lidClosed: true))
    }

    func testUnknownLidStateWaitsForFirstClosedEvent() {
        var policy = LidDisplayPolicy()
        XCTAssertFalse(policy.setEnabled(true, lidClosed: nil))
        XCTAssertTrue(policy.lidChanged(isClosed: true))
        XCTAssertFalse(policy.lidChanged(isClosed: true))
    }
}
