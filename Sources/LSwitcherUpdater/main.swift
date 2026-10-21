import AppKit
import LSwitcherCore
import Darwin

// This helper is launched only after an explicit Install and Restart action.
// It never elevates privileges, disables Gatekeeper or changes TCC permissions.
func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw UpdatePackage.Failure.invalidPackage }
}
func install(target: URL, work: URL, parent: Int32, launch: Bool) throws {
    let fm = FileManager.default
    guard target.lastPathComponent == "LSwitcher.app", !target.path.hasPrefix("/Volumes/"),
          target == target.resolvingSymlinksInPath(),
          fm.isWritableFile(atPath: target.deletingLastPathComponent().path),
          let old = Bundle(url: target), old.bundleIdentifier == "com.lswitcher.app",
          let current = old.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
        throw UpdatePackage.Failure.invalidPackage
    }
    let manifest = try Data(contentsOf: work.appendingPathComponent("update.json"))
    guard manifest.count < 16_384 else { throw UpdatePackage.Failure.invalidPackage }
    let package = try JSONDecoder().decode(UpdatePackage.self, from: manifest)
    let archive = work.appendingPathComponent(package.filename)
    try package.verify(archive: archive, current: current)
    let extraction = work.appendingPathComponent("extracted-\(UUID().uuidString)")
    try fm.createDirectory(at: extraction, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: extraction) }
    try run("/usr/bin/ditto", ["-x", "-k", archive.path, extraction.path])
    let candidate = extraction.appendingPathComponent("LSwitcher.app")
    guard let bundle = Bundle(url: candidate), bundle.bundleIdentifier == "com.lswitcher.app",
          bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == package.version,
          let executable = bundle.executableURL,
          executable.resolvingSymlinksInPath().path.hasPrefix(candidate.path + "/") else {
        throw UpdatePackage.Failure.invalidPackage
    }
    try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", candidate.path])
    let staged = target.deletingLastPathComponent().appendingPathComponent(".LSwitcher-new-\(UUID().uuidString).app")
    let backup = target.deletingLastPathComponent().appendingPathComponent(".LSwitcher-backup-\(UUID().uuidString).app")
    try fm.copyItem(at: candidate, to: staged)
    defer { try? fm.removeItem(at: staged) }
    try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])
    // Do not replace a live app, including when shutdown was cancelled.
    let deadline = Date().addingTimeInterval(60)
    while kill(parent, 0) == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
    guard kill(parent, 0) != 0 else { throw UpdatePackage.Failure.invalidPackage }
    try fm.moveItem(at: target, to: backup)
    do { try fm.moveItem(at: staged, to: target) }
    catch { try? fm.moveItem(at: backup, to: target); throw error }
    if launch {
        do { try run("/usr/bin/open", [target.path]) }
        catch {
            try? fm.moveItem(at: target, to: staged)
            try? fm.moveItem(at: backup, to: target)
            try? run("/usr/bin/open", [target.path])
            throw error
        }
    }
    // Keep one local previous version for recovery; no typed data is included.
    let previous = work.appendingPathComponent("Previous-LSwitcher.app")
    try? fm.moveItem(at: backup, to: previous)
}
let args = CommandLine.arguments
if args.count == 5, let pid = Int32(args[3]), pid > 1,
   args[4] == "--launch" || args[4] == "--test-no-launch" {
    do {
        try install(target: URL(fileURLWithPath: args[1]).standardizedFileURL,
                    work: URL(fileURLWithPath: args[2]).standardizedFileURL, parent: pid, launch: args[4] == "--launch")
    } catch {
        if args[4] == "--launch" {
            let alert = NSAlert()
            alert.messageText = "Не удалось установить обновление LSwitcher"
            alert.informativeText = "Предыдущая версия сохранена. Установите обновление вручную со страницы GitHub Releases."
            alert.runModal()
            try? run("/usr/bin/open", [args[1]])
        }
        exit(1)
    }
} else { exit(2) }
