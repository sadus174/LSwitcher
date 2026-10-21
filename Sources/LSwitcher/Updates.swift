import AppKit
import Combine
import LSwitcherCore

@MainActor
final class Updates: ObservableObject {
    static let repository = URL(string: "https://github.com/sadus174/LSwitcher")!
    static let releases = repository.appendingPathComponent("releases/latest")
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.5.0" }
    @Published private(set) var checking = false
    @Published private(set) var message = "Проверьте, доступна ли новая версия."
    @Published private(set) var available = false

    @Published private(set) var downloading = false
    @Published private(set) var readyToInstall = false
    @Published private(set) var canDownload = false
    private var package: UpdatePackage?
    private var work: URL?
    private static func asset(version: String, name: String) -> URL {
        repository.appendingPathComponent("releases/download/v\(version)/\(name)")
    }
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 90
        return URLSession(configuration: configuration)
    }

    func check() {
        guard !checking, !downloading, !readyToInstall else { return }
        checking = true
        available = false
        canDownload = false; package = nil
        message = "Проверяем GitHub Releases…"
        Task {
            defer { checking = false }
            do {
                let session = session()
                defer { session.invalidateAndCancel() }
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/sadus174/LSwitcher/releases/latest")!)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 1_000_000 else {
                    message = "GitHub сейчас недоступен. Попробуйте позже или откройте релизы."
                    return
                }
                let release = try JSONDecoder().decode(Release.self, from: data)
                guard !release.draft, !release.prerelease,
                      let latest = release.tag_name.first == "v" ? String(release.tag_name.dropFirst()) : Optional(release.tag_name),
                      latest.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil else {
                    message = "Не удалось определить версию релиза. Откройте список релизов."
                    return
                }
                available = latest.compare(Self.version, options: .numeric) == .orderedDescending
                message = available ? "Доступна версия \(latest)." : "У вас актуальная версия: \(Self.version)."
                if available {
                    let (manifest, response) = try await session.data(from: Self.asset(version: latest, name: "update.json"))
                    guard (response as? HTTPURLResponse)?.statusCode == 200, manifest.count < 16_384 else {
                        message = "Доступна версия \(latest). Для этого релиза используйте ручную установку."
                        return
                    }
                    let package = try JSONDecoder().decode(UpdatePackage.self, from: manifest)
                    try package.validate(current: Self.version)
                    guard package.version == latest else { throw UpdatePackage.Failure.invalidPackage }
                    self.package = package
                    canDownload = true
                }
            } catch {
                message = "Не удалось проверить обновления. Проверьте подключение и попробуйте снова."
            }
        }
    }
    func download() {
        guard let package, !downloading, !checking, !readyToInstall else { return }
        downloading = true
        message = "Скачиваем и проверяем подпись обновления…"
        Task {
            var directory: URL?
            defer { downloading = false }
            do {
                let session = session()
                defer { session.invalidateAndCancel() }
                let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("LSwitcher-update-\(UUID().uuidString)")
                directory = folder
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                let (temporary, response) = try await session.download(from: Self.asset(version: package.version, name: package.filename))
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdatePackage.Failure.invalidPackage }
                let archive = folder.appendingPathComponent(package.filename)
                try FileManager.default.moveItem(at: temporary, to: archive)
                try package.verify(archive: archive, current: Self.version)
                try JSONEncoder().encode(package).write(to: folder.appendingPathComponent("update.json"), options: .atomic)
                work = folder
                readyToInstall = true
                message = "Версия \(package.version) скачана. Подпись и целостность подтверждены."
            } catch {
                if let directory { try? FileManager.default.removeItem(at: directory) }
                message = "Не удалось скачать или проверить обновление. Можно повторить попытку или открыть релизы."
            }
        }
    }

    func install() {
        guard readyToInstall, let work else { return }
        let target = Bundle.main.bundleURL.resolvingSymlinksInPath()
        guard !target.path.hasPrefix("/Volumes/"),
              FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path),
              let helper = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("LSwitcherUpdater"),
              FileManager.default.isExecutableFile(atPath: helper.path) else {
            message = "Для обновления перенесите приложение в доступную для записи папку Applications или установите DMG вручную."
            return
        }
        let alert = NSAlert()
        alert.messageText = "Установить обновление и перезапустить LSwitcher?"
        alert.informativeText = "Текущая версия будет сохранена для восстановления. После обновления macOS может потребовать повторную выдачу разрешений."
        alert.addButton(withTitle: "Установить и перезапустить")
        alert.addButton(withTitle: "Отмена")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            // Copy the signed helper outside the bundle before replacing that bundle.
            let detached = work.appendingPathComponent("LSwitcherUpdater")
            if FileManager.default.fileExists(atPath: detached.path) { try FileManager.default.removeItem(at: detached) }
            try FileManager.default.copyItem(at: helper, to: detached)
            let process = Process()
            process.executableURL = detached
            process.arguments = [target.path, work.path, String(ProcessInfo.processInfo.processIdentifier), "--launch"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            NSApp.terminate(nil)
        } catch {
            message = "Не удалось запустить установку. Текущая версия сохранена; используйте DMG."
        }
    }
    private struct Release: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
    }
}
