import AppKit
import ApplicationServices

private enum SmokeFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

@MainActor
extension AppModel {
    func runSmokeTest() {
        guard !testing else { return }
        refresh()
        guard ready else { testResults = "Сначала разрешите доступ и запустите обработчик."; return }
        testing = true
        testResults = "Открываю отдельный временный документ…"
        Task { @MainActor in
            let originalExclusions = Preferences.shared.exclusions
            let originalEnabled = enabled
            let originalAutomatic = automatic
            let originalShiftMode = shiftMode
            defer {
                Preferences.shared.exclusions = originalExclusions
                setEnabled(originalEnabled)
                setAutomatic(originalAutomatic)
                setShiftMode(originalShiftMode)
                testing = false
                refresh()
            }
            do {
                setEnabled(true); setAutomatic(true); setShiftMode("both")
                Preferences.shared.exclusions = originalExclusions.split(whereSeparator: \.isNewline)
                    .filter { $0.trimmingCharacters(in: .whitespaces) != "com.apple.TextEdit" }.joined(separator: "\n")
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LSwitcher-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let marker = "LSwitcher test \(UUID().uuidString)"
                let file = directory.appendingPathComponent("LSwitcher test.txt")
                try marker.write(to: file, atomically: true, encoding: .utf8)
                guard let editor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else {
                    throw SmokeFailure.message("TextEdit не найден")
                }
                _ = try await NSWorkspace.shared.open([file], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
                try await delay(1.5)
                let field = try testField()
                guard try read(field).contains(marker) else { throw SmokeFailure.message("Не найден временный тестовый документ. Проверка остановлена.") }
                testResults = ""
                var checks = 0
                @MainActor func verify(_ name: String, expected: String) async throws {
                    try await delay(0.3)
                    let actual = try read(field)
                    guard actual.lowercased() == expected.lowercased() else {
                        testResults += "✕ \(name)\n"
                        throw SmokeFailure.message("Результат отличается от ожидаемого. См. счётчики событий выше.")
                    }
                    testResults += "✓ \(name)\n"
                    checks += 1
                }
                try await clear(field)
                try await type("ghbdtn", field: field)
                try await shiftPair(right: true, field: field)
                try await verify("Двойной правый Shift", expected: "привет")

                try await clear(field)
                try await type("ghbdtn", field: field)
                try await shiftPair(right: false, field: field)
                try await verify("Двойной левый Shift", expected: "привет")

                try await clear(field)
                try await type("ghbdtn ", field: field)
                try await verify("Автоисправление RU", expected: "привет ")

                try await clear(field)
                try await type("руддщ ", field: field)
                try await verify("Автоисправление EN", expected: "hello ")

                for (input, expected, name) in [
                    ("ghbkj;tybt ", "приложение ", "Новый словарь: ж"),
                    ("hfphf,jnrf ", "разработка ", "Новый словарь: б"),
                    ("gthtrk.xtybt ", "переключение ", "Новый словарь: ю"),
                    ("hf,jnfkf ", "работала ", "Словоформа OpenCorpora")
                ] {
                    try await clear(field)
                    try await type(input, field: field)
                    try await verify(name, expected: expected)
                }

                Preferences.shared.exclusions += "\ncom.apple.TextEdit"
                try await clear(field)
                try await type("ghbdtn ", field: field)
                try await verify("Автоисправление отключено исключением", expected: "ghbdtn ")
                try await shiftPair(right: true, field: field)
                try await verify("Ручное исправление в исключении и после пробела", expected: "привет ")

                try await clear(field)
                try await type("ghbdtn vbh", field: field)
                try await selectAll(field)
                try await shiftPair(right: true, field: field)
                try await verify("Исправление выделенного текста", expected: "привет мир")

                try await clear(field)
                try await type("hello ", field: field)
                try await verify("Правильное слово не изменяется", expected: "hello ")
                testResults += "\nВсе \(checks) проверок пройдены. Настройки восстановлены."
            } catch { testResults += "\n\(error.localizedDescription)" }
        }
    }

    private func delay(_ seconds: Double) async throws { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    private func testField() throws -> AXUIElement {
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == "com.apple.TextEdit" else {
            throw SmokeFailure.message("Фокус ушёл из TextEdit. Тест остановлен, ввод не отправлен.")
        }
        let result = AccessibilityFocus.element(app: app, timeout: 1)
        guard let element = result.element else {
            throw SmokeFailure.message("Нет доступа к тестовому полю TextEdit: AX \(result.error.rawValue), PID \(app.processIdentifier), trusted=\(AXIsProcessTrusted())")
        }
        return element
    }
    private func read(_ field: AXUIElement) throws -> String {
        guard CFEqual(field, try testField()) else { throw SmokeFailure.message("Тестовое поле потеряло фокус") }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(field, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String else { throw SmokeFailure.message("TextEdit не предоставил текст результата") }
        return text
    }
    private func press(_ code: CGKeyCode, text: String? = nil, modifiers: CGEventFlags = [], field: AXUIElement) async throws {
        guard CFEqual(field, try testField()) else { throw SmokeFailure.message("Тестовое поле потеряло фокус") }
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
            event.flags = modifiers
            if let text { let units = Array(text.utf16); event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units) }
            event.post(tap: .cghidEventTap)
            try await delay(0.025)
        }
    }
    private func type(_ text: String, field: AXUIElement) async throws {
        for character in text { try await press(character == " " ? 49 : 0, text: String(character), field: field) }
    }
    private func clear(_ field: AXUIElement) async throws {
        // AX setters can acknowledge before TextEdit has applied its selection.
        // Prefer replacing the value of this verified, disposable test field.
        if AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, "" as CFString) == .success {
            for _ in 0..<10 {
                try await delay(0.05)
                if try read(field).isEmpty { engine.reset(); return }
            }
        }
        try await selectAll(field)
        try await press(51, field: field)
        try await delay(0.1)
        guard try read(field).isEmpty else { throw SmokeFailure.message("Тестовое поле не очистилось — проверка остановлена") }
        engine.reset()
    }
    private func selectAll(_ field: AXUIElement) async throws {
        var range = CFRange(location: 0, length: try read(field).utf16.count)
        guard let value = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, value) == .success else {
            throw SmokeFailure.message("Не удалось выделить содержимое тестового поля")
        }
        try await delay(0.2)
    }
    private func shiftPair(right: Bool, field: AXUIElement) async throws {
        for _ in 0..<2 {
            guard CFEqual(field, try testField()) else { throw SmokeFailure.message("Тестовое поле потеряло фокус") }
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: right ? 60 : 56, keyDown: down)!
                event.type = .flagsChanged
                event.flags = down ? CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | (right ? 4 : 2)) : []
                event.post(tap: .cghidEventTap)
                try await delay(0.05)
            }
        }
    }
}
