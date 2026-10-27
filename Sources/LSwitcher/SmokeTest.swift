import AppKit
import ApplicationServices
import Carbon

private enum SmokeFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

@MainActor
extension AppModel {
    func runSmokeTest() {
        if testEditorID == "com.apple.Spotlight" { runSpotlightSmokeTest(); return }
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
            let originalWords = neverCorrect
            let originalHint = showLayoutHint
            defer {
                engine.smokeTerminalBundleID = nil
                engine.smokeSearchBundleID = nil
                engine.reset()
                Preferences.shared.exclusions = originalExclusions
                loadExclusions()
                setEnabled(originalEnabled)
                setAutomatic(originalAutomatic)
                setShiftMode(originalShiftMode)
                setNeverCorrect(originalWords)
                setShowLayoutHint(originalHint)
                testing = false
                refresh()
            }
            do {
                setEnabled(true); setAutomatic(true); setShiftMode("both"); setNeverCorrect("")
                Preferences.shared.exclusions = originalExclusions.split(whereSeparator: \.isNewline)
                    .filter { $0.trimmingCharacters(in: .whitespaces) != testEditorID }.joined(separator: "\n")
                loadExclusions()
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LSwitcher-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let marker = "LSwitcher test \(UUID().uuidString)"
                let browser = testEditorID != "com.apple.TextEdit"
                guard ["com.apple.TextEdit", "com.apple.Safari", "com.google.Chrome"].contains(testEditorID) else {
                    throw SmokeFailure.message("Неподдерживаемый тестовый редактор")
                }
                let file = directory.appendingPathComponent(browser ? "LSwitcher test.html" : "LSwitcher test.txt")
                let content = browser ? "<!doctype html><meta charset='utf-8'><title>LSwitcher Input Test</title><h1>LSwitcher · Temporary input test</h1><textarea autofocus spellcheck='false' autocorrect='off' autocapitalize='off' style='width:90vw;height:70vh;font:20px monospace'>\(marker)</textarea>" : marker
                try content.write(to: file, atomically: true, encoding: .utf8)
                guard let editor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: testEditorID) else {
                    throw SmokeFailure.message("Тестовое приложение не установлено")
                }
                _ = try await NSWorkspace.shared.open([file], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
                AccessibilityFocus.prepare(NSWorkspace.shared.frontmostApplication)
                var candidate: AXUIElement?
                for _ in 0..<40 {
                    try await delay(0.25)
                    if let focused = try? testField(), let value = try? read(focused), value.contains(marker) {
                        candidate = focused; break
                    }
                }
                guard let field = candidate else { throw SmokeFailure.message("Тестовое поле не готово или потеряло фокус. Ввод не отправлен; повторите после загрузки редактора.") }
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
                setShowLayoutHint(true)
                focusHint.reset(); focusHint.refresh()
                guard focusHint.visible, CFEqual(field, try testField()) else {
                    throw SmokeFailure.message("Флаг не появился или поле потеряло фокус")
                }
                testResults += "✓ Флаг при фокусе без перехвата ввода\n"; checks += 1
                setShowLayoutHint(false)
                guard !focusHint.visible else { throw SmokeFailure.message("Флаг не отключился") }
                testResults += "✓ Отключение флага в настройках\n"; checks += 1
                setShowLayoutHint(true)
                focusHint.refresh()
                try await type("x", field: field)
                try await delay(0.1)
                guard !focusHint.visible else { throw SmokeFailure.message("Флаг не скрылся при вводе") }
                testResults += "✓ Флаг скрывается после первого ввода\n"; checks += 1

                guard let delegate = NSApp.delegate as? AppDelegate else { throw SmokeFailure.message("Нет делегата приложения") }
                setEnabled(false)
                guard operationStatus == .disabled, delegate.statusPresentationMatchesModel else {
                    throw SmokeFailure.message("Статус выключения расходится в интерфейсе")
                }
                setEnabled(true); setAutomatic(false)
                guard operationStatus == .manualOnly, delegate.statusPresentationMatchesModel else {
                    throw SmokeFailure.message("Статус ручного режима расходится в интерфейсе")
                }
                setAutomatic(true)
                engine.stop(); refresh()
                guard operationStatus == .handlerUnavailable, delegate.statusPresentationMatchesModel else {
                    throw SmokeFailure.message("Статус недоступного обработчика расходится в интерфейсе")
                }
                engine.start(); refresh()
                guard operationStatus == .automatic, delegate.statusPresentationMatchesModel else {
                    throw SmokeFailure.message("Статус доступности не восстановился")
                }
                testResults += "✓ Согласованные статусы меню и настроек\n"; checks += 1
                for (sleep, wake, name) in [
                    (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, "сон/пробуждение"),
                    (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, "блокировка/разблокировка")
                ] {
                    let handler = engine.generation, status = delegate.statusGeneration
                    NSWorkspace.shared.notificationCenter.post(name: sleep, object: nil)
                    checkHealth()
                    guard !engine.running, sessionSuspended, engine.generation == handler,
                          operationStatus == .suspended else {
                        throw SmokeFailure.message("Обработчик не остановился на время сна")
                    }
                    NSWorkspace.shared.notificationCenter.post(name: wake, object: nil)
                    guard engine.running, !sessionSuspended, engine.generation > handler,
                          delegate.statusGeneration > status, delegate.statusItemPresent,
                          operationStatus != .suspended, delegate.statusPresentationMatchesModel else {
                        throw SmokeFailure.message("Не восстановились обработчик и значок")
                    }
                    testResults += "✓ Восстановление: \(name)\n"; checks += 1
                }
                engine.stop()
                checkHealth()
                guard engine.running else { throw SmokeFailure.message("Контроль состояния не восстановил обработчик") }
                testResults += "✓ Автовосстановление недействующего обработчика\n"; checks += 1

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

                try await press(51, field: field)
                try await verify("Backspace отменяет автозамену", expected: "ghbdtn ")
                guard let offered = engine.exclusionCandidate() else { throw SmokeFailure.message("После отмены нет предложения исключения") }
                delegate.prepareWordExclusionMenu()
                guard engine.exclusionCandidate()?.id == offered.id, delegate.performWordExclusionMenuAction(),
                      Preferences.shared.protects("ghbdtn") else {
                    throw SmokeFailure.message("Меню не сохранило слово после отмены")
                }
                testResults += "✓ Меню: слово после отмены добавлено явно\n"; checks += 1
                try await press(51, field: field)
                try await verify("Повторный Backspace удаляет символ", expected: "ghbdtn")
                try await clear(field)
                try await type("ghbdtn ", field: field)
                try await verify("Меню: сохранённое слово не исправляется автоматически", expected: "ghbdtn ")
                try await shiftPair(right: true, field: field)
                try await verify("Меню: ручной Shift доступен для сохранённого слова", expected: "привет ")
                setNeverCorrect("")
                try await clear(field)
                try await type("ghbdtn ", field: field)
                try await press(51, field: field)
                delegate.prepareWordExclusionMenu()
                _ = engine.exclusionCandidate(at: ProcessInfo.processInfo.systemUptime + 60)
                guard !delegate.performWordExclusionMenuAction(), neverCorrect.isEmpty else {
                    throw SmokeFailure.message("Устаревший пункт меню сохранил слово")
                }
                testResults += "✓ Меню: просроченное предложение отклонено\n"; checks += 1
                try await clear(field)
                try await type("hello", field: field)
                try await press(51, field: field)
                guard engine.exclusionCandidate() == nil else { throw SmokeFailure.message("Обычный Backspace создал предложение") }
                try await verify("Обычный Backspace не предлагает исключение", expected: "hell")

                setNeverCorrect("GHBDTN")
                try await clear(field)
                try await type("ghbdtn ", field: field)
                try await verify("Личное исключение слова", expected: "ghbdtn ")
                setNeverCorrect("")

                for input in ["https://ghbdtn ", "user@ghbdtn ", "/tmp/ghbdtn ", "id123ghbdtn "] {
                    try await clear(field)
                    try await type(input, field: field)
                    try await verify("Адрес или путь без автозамены", expected: input)
                }

                try await clear(field)
                try await type("ghbdtn", field: field)
                try await press(123, field: field)
                try await type(" ", field: field)
                try await verify("Перемещение курсора сбрасывает слово", expected: "ghbdt n")

                engine.suspend(); engine.start()
                try await clear(field)
                try await type("ghbdtn ", field: field)
                try await verify("Обработчик восстановлен после приостановки", expected: "привет ")
                engine.reset()
                try await press(51, field: field)
                try await verify("Сброс контекста отменяет возможность отката", expected: "привет")

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

                guard delegate.performExclusionMenuAction(), excludedIDs.contains(testEditorID) else {
                    throw SmokeFailure.message("Меню не добавило тестовый редактор в исключения")
                }
                guard case .excludedApplication = operationStatus else { throw SmokeFailure.message("Статус исключения не обновился") }
                try await clear(field)
                try await type("ghbdtn ", field: field)
                try await verify("Меню: автоисправление отключено исключением", expected: "ghbdtn ")
                try await shiftPair(right: true, field: field)
                try await verify("Ручное исправление в исключении и после пробела", expected: "привет ")
                guard delegate.performExclusionMenuAction(), !excludedIDs.contains(testEditorID) else {
                    throw SmokeFailure.message("Меню не сняло исключение тестового редактора")
                }
                try await clear(field)
                try await type("ghbdtn ", field: field)
                try await verify("Меню: снятие исключения возвращает автоисправление", expected: "привет ")

                try await clear(field)
                setAutomatic(false)
                try await type("ghbdtn vbh", field: field)
                try await selectAll(field)
                try await shiftPair(right: true, field: field)
                try await verify("Исправление выделенного текста", expected: "привет мир")
                setAutomatic(true)

                try await clear(field)
                try await type("hello ", field: field)
                try await verify("Правильное слово не изменяется", expected: "hello ")
                // Exercise the same AX-free input path as Termius in a disposable editor.
                engine.smokeTerminalBundleID = testEditorID
                for right in [true, false] {
                    try await clear(field)
                    try await type("ghbdtn", field: field)
                    try await shiftPair(right: right, field: field)
                    try await verify("Терминальный режим: двойной \(right ? "правый" : "левый") Shift", expected: "привет")
                }
                try await clear(field)
                try await type("ghbdtn", field: field)
                try await press(123, field: field)
                try await shiftPair(right: true, field: field)
                try await verify("Терминальный режим: сброс при перемещении курсора", expected: "ghbdtn")
                Preferences.shared.exclusions = ""
                try await clear(field)
                try await type("ghbdtn ", field: field)
                try await verify("Терминальный режим: автоисправление", expected: "привет ")
                engine.smokeTerminalBundleID = nil
                if testEditorID == "com.apple.TextEdit" {
                    engine.smokeSearchBundleID = testEditorID
                    for right in [true, false] {
                        try await clear(field)
                        try await type("ghbdtn", field: field)
                        try await shiftPair(right: right, field: field)
                        try await verify("Поиск: двойной \(right ? "правый" : "левый") Shift", expected: "привет")
                    }
                    try await clear(field)
                    try await type("ghbdtn", field: field)
                    // Model the selected suggestion inserted by a search provider.
                    guard AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, "ghbdtn suggestion" as CFString) == .success else {
                        throw SmokeFailure.message("Не удалось подготовить поисковую подсказку")
                    }
                    try await delay(0.2)
                    var completionRange = CFRange(location: 6, length: 11)
                    guard let completion = AXValueCreate(.cfRange, &completionRange),
                          AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, completion) == .success else {
                        throw SmokeFailure.message("Не удалось выделить поисковую подсказку")
                    }
                    try await delay(0.2)
                    try await shiftPair(right: true, field: field)
                    try await verify("Поиск: подсказка не оставляет лишние буквы", expected: "привет")
                    try await type("!", field: field)
                    try await verify("Поиск: курсор после исправленного слова", expected: "привет!")

                    try await clear(field)
                    setAutomatic(false)
                    try await type("ghbdtn vbh", field: field)
                    try await selectAll(field)
                    try await shiftPair(right: true, field: field)
                    try await verify("Поиск: выделенный запрос целиком", expected: "привет мир")
                    setAutomatic(true)
                    try await clear(field)
                    try await type("ghbdtn ", field: field)
                    try await verify("Поиск: автоисправление с пробелом одной операцией", expected: "привет ")
                    try await press(51, field: field)
                    try await verify("Поиск: отмена без серии Backspace", expected: "ghbdtn ")
                    engine.smokeSearchBundleID = nil
                }
                testResults += "\nВсе \(checks) проверок пройдены. Настройки восстановлены."
            } catch { testResults += "\n\(error.localizedDescription)" }
        }
    }

    private func runSpotlightSmokeTest() {
        guard !testing else { return }
        refresh()
        guard ready else { testResults = "Сначала разрешите доступ и запустите обработчик."; return }
        testing = true
        testResults = "Открываю Spotlight. Ввод разрешён только в пустую проверенную строку поиска…"
        Task { @MainActor in
            let originalEnabled = enabled, originalAutomatic = automatic, originalShift = shiftMode
            let originalLayout = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
            defer {
                engine.reset()
                setEnabled(originalEnabled); setAutomatic(originalAutomatic); setShiftMode(originalShift)
                if let originalLayout { TISSelectInputSource(originalLayout) }
                testing = false; refresh()
            }
            do {
                setEnabled(true); setAutomatic(false); setShiftMode("both")
                // Global hotkeys must enter the HID stream, rather than an app-targeted queue.
                for down in [true, false] {
                    let event = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: down)!
                    event.flags = .maskCommand
                    event.post(tap: .cghidEventTap)
                    try await delay(0.05)
                }
                var candidate: AXUIElement?
                for _ in 0..<30 {
                    try await delay(0.1)
                    if let field = try? testField() { candidate = field; break }
                }
                guard let field = candidate else { throw SmokeFailure.message("Spotlight не получил доступный фокус. Тестовый ввод не отправлен.") }
                guard try read(field).isEmpty else {
                    throw SmokeFailure.message("Строка Spotlight не пуста. Очистите её вручную и повторите тест. Текущий запрос не изменён.")
                }
                testResults = ""
                let filter = [kTISPropertyInputSourceCategory!: kTISCategoryKeyboardInputSource!,
                              kTISPropertyInputSourceIsSelectCapable!: true] as CFDictionary
                guard let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
                      let english = sources.first(where: { source in
                        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return false }
                        return (Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as NSArray).contains("en")
                      }) else { throw SmokeFailure.message("Для теста нужна английская раскладка") }
                for right in [true, false] {
                    TISSelectInputSource(english)
                    try await delay(0.2)
                    try await clear(field)
                    for code: CGKeyCode in [5, 4, 11, 34, 17, 45] { try await press(code, field: field) }
                    try await delay(0.3)
                    guard try searchTypedPrefix(field) == "ghbdtn" else {
                        throw SmokeFailure.message("Spotlight не принял тестовое слово. Текст запроса не включён в диагностику.")
                    }
                    try await shiftPair(right: right, field: field)
                    try await delay(0.5)
                    guard try searchTypedPrefix(field) == "привет" else {
                        throw SmokeFailure.message("Spotlight: результат замены отличается от ожидаемого. Механизм: \(engine.diagnostic). Текст запроса не включён в диагностику.")
                    }
                    testResults += "✓ Реальный Spotlight: \(right ? "правый" : "левый") Shift\n"
                }
                try await clear(field)
                testResults += "Проверки реального Spotlight пройдены. Настройки и раскладка восстановлены."
            } catch { testResults += "\n\(error.localizedDescription)" }
        }
    }

    private func searchTypedPrefix(_ field: AXUIElement) throws -> String {
        let text = try read(field)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return text }
        var range = CFRange()
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cfRange, &range),
              range.location >= 0, range.length > 0, range.location <= text.utf16.count,
              range.length == text.utf16.count - range.location,
              let selected = Range(NSRange(location: range.location, length: range.length), in: text) else { return text }
        return String(text[..<selected.lowerBound])
    }

    private func delay(_ seconds: Double) async throws { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    private func testField() throws -> AXUIElement {
        guard let app = AccessibilityFocus.keyboardApplication(timeout: 1), app.bundleIdentifier == testEditorID else {
            throw SmokeFailure.message("Фокус ушёл из тестового редактора. Тест остановлен, ввод не отправлен.")
        }
        let result = AccessibilityFocus.element(app: app, timeout: 1)
        guard let element = result.element else {
            throw SmokeFailure.message("Нет доступа к тестовому полю: AX \(result.error.rawValue), PID \(app.processIdentifier), trusted=\(AXIsProcessTrusted())")
        }
        return element
    }
    private func read(_ field: AXUIElement) throws -> String {
        guard CFEqual(field, try testField()) else { throw SmokeFailure.message("Тестовое поле потеряло фокус") }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(field, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String else { throw SmokeFailure.message("Редактор не предоставил текст результата") }
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
