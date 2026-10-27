import AppKit
import ServiceManagement
import Carbon

private enum LoginCheckFailure: Error { case failed(String), simulated }

@MainActor
private final class FakeLoginService: LoginLaunchService {
    var status: SMAppService.Status = .notRegistered
    var fail = false
    var requests = 0
    func register() throws {
        requests += 1
        if fail { throw LoginCheckFailure.simulated }
        status = .enabled
    }
    func unregister() throws {
        requests += 1
        if fail { throw LoginCheckFailure.simulated }
        status = .notRegistered
    }
    func openSettings() {}
}

@MainActor
func checkLoginLaunch() throws {
    let fake = FakeLoginService()
    let login = LoginLaunch(service: fake)
    guard fake.requests == 0, !login.enabled else { throw LoginCheckFailure.failed("opt-in") }
    login.setEnabled(true)
    guard login.enabled else { throw LoginCheckFailure.failed("enabled") }
    fake.status = .requiresApproval; login.refresh()
    guard !login.enabled, !login.explanation.isEmpty else { throw LoginCheckFailure.failed("approval") }
    fake.status = .notFound; login.refresh()
    guard !login.enabled else { throw LoginCheckFailure.failed("not found") }
    fake.fail = true
    login.setEnabled(true)
    guard login.errorMessage != nil, !login.enabled else { throw LoginCheckFailure.failed("registration error") }
    fake.fail = false
    login.setEnabled(false)
    guard login.status == .notRegistered, login.errorMessage == nil else { throw LoginCheckFailure.failed("unregister") }
    guard !LaunchReason.isLoginLaunch(nil) else { throw LoginCheckFailure.failed("ordinary launch") }
    let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
        targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    let properties = NSAppleEventDescriptor.record()
    properties.setDescriptor(NSAppleEventDescriptor(boolean: true), forKeyword: AEKeyword(keyAELaunchedAsLogInItem))
    event.setParam(properties, forKeyword: AEKeyword(keyAEPropData))
    guard LaunchReason.isLoginLaunch(event) else { throw LoginCheckFailure.failed("login event") }
    print("Login launch: opt-in, system statuses, external changes, error handling and launch-event routing passed (no system registration)")
}
