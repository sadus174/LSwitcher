import AppKit
import Combine
import ServiceManagement
import SwiftUI
import Carbon

@MainActor
protocol LoginLaunchService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSettings()
}

@MainActor
private struct SystemLoginLaunchService: LoginLaunchService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

@MainActor
final class LoginLaunch: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var errorMessage: String?
    private let service: any LoginLaunchService

    init(service: (any LoginLaunchService)? = nil) {
        self.service = service ?? SystemLoginLaunchService()
        refresh()
    }
    var enabled: Bool { status == .enabled }
    var explanation: String {
        switch status {
        case .enabled: "LSwitcher запускается при входе без окна настроек."
        case .notRegistered: "Запускайте LSwitcher автоматически при входе в систему."
        case .requiresApproval: "Нужно разрешение в системном разделе «Объекты входа»."
        case .notFound: "macOS не нашла приложение для автозапуска. Запустите установленную копию и повторите попытку."
        @unknown default: "Не удалось определить системное состояние автозапуска."
        }
    }
    func refresh() {
        let current = service.status
        if current != status { errorMessage = nil }
        status = current
    }
    func setEnabled(_ enabled: Bool) {
        refresh()
        errorMessage = nil
        do {
            if enabled {
                if status != .enabled && status != .requiresApproval { try service.register() }
            } else if status != .notRegistered { try service.unregister() }
        } catch { errorMessage = "Не удалось изменить автозапуск: \(error.localizedDescription)" }
        refresh()
    }
    func openSettings() { service.openSettings() }
}

enum LaunchReason {
    static func isLoginLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event, event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?
            .paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem))?.booleanValue == true
            || event.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem))?.booleanValue == true
    }
}

struct LoginLaunchSettings: View {
    @ObservedObject var login: LoginLaunch
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Запускать при входе в систему", isOn: Binding(get: { login.enabled }, set: login.setEnabled))
                .toggleStyle(.switch).font(.system(size: 13, weight: .semibold))
            Text(login.explanation).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = login.errorMessage { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
            if login.status == .requiresApproval {
                HStack {
                    Button("Открыть объекты входа", action: login.openSettings)
                    Button("Отменить запрос") { login.setEnabled(false) }
                }.font(.system(size: 11))
            }
        }.onAppear { login.refresh() }
    }
}
