import AppKit
import Combine

@MainActor
final class Updates: ObservableObject {
    static let repository = URL(string: "https://github.com/sadus174/LSwitcher")!
    static let releases = repository.appendingPathComponent("releases/latest")
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.1" }
    @Published private(set) var checking = false
    @Published private(set) var message = "Проверьте, доступна ли новая версия."
    @Published private(set) var available = false

    func check() {
        guard !checking else { return }
        checking = true
        available = false
        message = "Проверяем GitHub Releases…"
        Task {
            defer { checking = false }
            do {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 15
                let session = URLSession(configuration: configuration)
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
            } catch {
                message = "Не удалось проверить обновления. Проверьте подключение и попробуйте снова."
            }
        }
    }
    private struct Release: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
    }
}
