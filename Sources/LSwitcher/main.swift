import AppKit
@preconcurrency import ApplicationServices
import Carbon
import LSwitcherCore
import UniformTypeIdentifiers

private let injectedEventTag: Int64 = 0x4C535749

@MainActor
final class Preferences {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard
    var automatic: Bool {
        get { defaults.object(forKey: "automatic") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "automatic") }
    }
    var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled") }
    }
    var showLayoutHint: Bool {
        get { defaults.object(forKey: "showLayoutHint") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showLayoutHint") }
    }
    var shiftMode: String {
        get { defaults.string(forKey: "shiftMode") ?? "both" }
        set { defaults.set(newValue, forKey: "shiftMode") }
    }
    var exclusions: String {
        get { defaults.string(forKey: "exclusions") ?? "com.apple.Terminal\ncom.googlecode.iterm2\ncom.agilebits.onepassword7\ncom.1password.1password" }
        set { defaults.set(newValue, forKey: "exclusions") }
    }
    var neverCorrect: String {
        get { defaults.string(forKey: "neverCorrect") ?? "" }
        set { defaults.set(newValue, forKey: "neverCorrect"); personalWords = PersonalWords.normalized(newValue) }
    }
    private lazy var personalWords = PersonalWords.normalized(neverCorrect)
    func protects(_ word: String) -> Bool { PersonalWords.contains(word, in: personalWords) }
    func excludes(_ identifier: String) -> Bool {
        AutomaticExclusions.contains(identifier, in: exclusions)
    }
}

@MainActor
final class KeyboardEngine {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var word = ""
    private var protectedToken = false
    private var undo: CorrectionUndo?
    private var undoElement: AXUIElement?
    private var focusedElement: AXUIElement?
    private var lastPID: pid_t = 0
    private var doubleShift = DoubleShiftDetector()
    private var leftDoubleShift = DoubleShiftDetector()
    private(set) var eventsReceived = 0
    private(set) var shiftEvents = 0
    private(set) var manualCorrections = 0
    private(set) var automaticCorrections = 0
    private(set) var diagnostic = "Ожидание ввода"
    var statusChanged: (() -> Void)?
    var typingObserved: (() -> Void)?
    var running: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func start() {
        if let tap, !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
        guard tap == nil, AXIsProcessTrusted() else { statusChanged?(); return }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue) | (1 << CGEventType.otherMouseDown.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                // The source is installed only on the main run loop. Return a Sendable
                // decision across this boundary, keeping the CGEvent in the callback.
                let suppress = MainActor.assumeIsolated {
                    let engine = Unmanaged<KeyboardEngine>.fromOpaque(context).takeUnretainedValue()
                    return engine.handle(type: type, event: event) == nil
                }
                return suppress ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        statusChanged?()
    }

    func reset() { word = ""; protectedToken = false; undo = nil; undoElement = nil; focusedElement = nil; doubleShift.cancel(); leftDoubleShift.cancel() }

    func suspend() {
        reset()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reset()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.eventSourceUserData) != injectedEventTag else {
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown, event.flags.intersection([.maskCommand, .maskControl]).isEmpty,
           ![48, 115, 116, 119, 121, 123, 124, 125, 126].contains(Int(event.getIntegerValueField(.keyboardEventKeycode))) {
            typingObserved?()
        }
        eventsReceived += 1
        guard type == .keyDown || type == .flagsChanged else { reset(); return Unmanaged.passUnretained(event) }
        let preferences = Preferences.shared
        guard preferences.enabled,
              let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              !(app.bundleIdentifier ?? "").hasPrefix("com.1password."),
              app.bundleIdentifier != "com.agilebits.onepassword7",
              !IsSecureEventInputEnabled() else {
            reset(); return Unmanaged.passUnretained(event)
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let modifiers = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        if type == .flagsChanged {
            undo = nil; undoElement = nil
            if code == 60 || code == 56 {
                shiftEvents += 1
                let right = code == 60
                let isDown = event.flags.rawValue & (right ? 0x4 : 0x2) != 0
                let other = !modifiers.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty
                    || event.flags.rawValue & (right ? 0x2 : 0x4) != 0
                let allowed = preferences.shiftMode == "both" || preferences.shiftMode == (right ? "right" : "left")
                let triggered: Bool
                if right {
                    leftDoubleShift.cancel()
                    triggered = doubleShift.update(isDown: isDown, time: Double(event.timestamp) / 1_000_000_000, otherModifiers: other || !allowed)
                } else {
                    doubleShift.cancel()
                    triggered = leftDoubleShift.update(isDown: isDown, time: Double(event.timestamp) / 1_000_000_000, otherModifiers: other || !allowed)
                }
                if triggered {
                    undo = nil; undoElement = nil
                    diagnostic = "Двойной \(right ? "правый" : "левый") Shift распознан"
                    // Release the event tap before making cross-process Accessibility calls.
                    DispatchQueue.main.async { [weak self] in
                        guard let self, Preferences.shared.enabled, !IsSecureEventInputEnabled(),
                              NSWorkspace.shared.frontmostApplication?.isEqual(app) == true,
                              let element = self.focusedInput(for: app) else { return }
                        self.correctManually(element: element)
                    }
                }
            } else { doubleShift.cancel(); leftDoubleShift.cancel() }
            return Unmanaged.passUnretained(event)
        }
        doubleShift.cancel()
        leftDoubleShift.cancel()
        guard let element = focusedInput(for: app) else { word = ""; return Unmanaged.passUnretained(event) }
        if lastPID != app.processIdentifier || focusedElement.map({ !CFEqual($0, element) }) != false {
            word = ""; protectedToken = false; undo = nil; undoElement = nil
        }
        lastPID = app.processIdentifier
        focusedElement = element
        if !modifiers.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
            word = ""; undo = nil; undoElement = nil; return Unmanaged.passUnretained(event)
        }
        if code == 51, modifiers.isEmpty, let pending = undo, let undoElement, CFEqual(undoElement, element),
           let state = textState(element), pending.matches(text: state.text, caret: state.range.location,
                selectionLength: state.range.length, time: ProcessInfo.processInfo.systemUptime) {
            undo = nil; self.undoElement = nil
            replace(count: pending.replacement.count + pending.delimiter.count, with: pending.original + pending.delimiter)
            selectLayout(for: pending.original)
            word = ""; protectedToken = false
            diagnostic = "Автоисправление отменено"
            return nil
        }
        undo = nil; undoElement = nil
        if code == 51 {
            if !word.isEmpty { word.removeLast() }
            return Unmanaged.passUnretained(event)
        }
        var length = 0
        var characters = [UniChar](repeating: 0, count: 16)
        event.keyboardGetUnicodeString(maxStringLength: characters.count, actualStringLength: &length, unicodeString: &characters)
        let text = String(utf16CodeUnits: characters, count: length)
        guard !text.isEmpty, !text.unicodeScalars.contains(where: { $0.value < 32 && $0 != "\r" && $0 != "\t" && $0 != "\n" }) else {
            word = ""; return Unmanaged.passUnretained(event)
        }
        if text.contains(where: { $0.isNumber || "@:/\\_-=+".contains($0) }) { protectedToken = true }
        if text.allSatisfy({ $0.isLetter || "[];',`.".contains($0) }) {
            word += text
            if word.count > 80 { word = "" }
        } else {
            if preferences.automatic, !protectedToken, !preferences.protects(word), !preferences.excludes(app.bundleIdentifier ?? ""),
               text == " " || text == "\r" || text == "\t",
               let replacement = LayoutConverter.automaticReplacement(for: word) {
                // Only offer undo when the caret and source suffix can be verified.
                if text == " ", let state = textState(element), state.range.length == 0,
                   let end = String.Index(utf16Offset: state.range.location, in: state.text).samePosition(in: state.text),
                   state.text[..<end].suffix(word.count).lowercased() == word.lowercased() {
                    undo = CorrectionUndo(original: word, replacement: replacement, delimiter: text,
                        caret: state.range.location - word.utf16.count + replacement.utf16.count + text.utf16.count,
                        time: ProcessInfo.processInfo.systemUptime)
                    undoElement = element
                }
                replace(count: word.count, with: replacement)
                automaticCorrections += 1
                diagnostic = undo == nil ? "Автоисправление отправлено" : "Автоисправление отправлено · Backspace отменяет"
                event.setIntegerValueField(.eventSourceUserData, value: injectedEventTag)
                event.post(tap: .cghidEventTap)
                selectLayout(for: replacement)
                word = ""
                return nil
            }
            word = ""
            if text.contains(where: \.isWhitespace) { protectedToken = false }
        }
        return Unmanaged.passUnretained(event)
    }

    private func focusedInput(for app: NSRunningApplication) -> AXUIElement? {
        let result = AccessibilityFocus.element(app: app, timeout: 0.04)
        guard let element = result.element else {
            diagnostic = "Нет доступа к полю: AX \(result.error.rawValue), PID \(app.processIdentifier)"
            return nil
        }
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        guard subrole as? String != "AXSecureTextField" else {
            diagnostic = "Защищённое поле пропущено"
            return nil
        }
        return element
    }

    private func correctManually(element: AXUIElement) {
        var selected: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected)
        if let text = selected as? String, !text.isEmpty {
            let replacement = LayoutConverter.convert(text)
            insert(replacement)
            selectLayout(for: replacement)
        } else if let preceding = wordBeforeCursor(element: element) {
            let replacement = LayoutConverter.convert(preceding.word)
            replace(count: preceding.word.count + preceding.suffix.count, with: replacement + preceding.suffix)
            selectLayout(for: replacement)
        } else if !word.isEmpty {
            let replacement = LayoutConverter.convert(word)
            replace(count: word.count, with: replacement)
            selectLayout(for: replacement)
        } else { diagnostic = "Нет выделения или слова перед курсором"; NSSound.beep(); return }
        manualCorrections += 1
        diagnostic = "Ручное исправление отправлено"
        word = ""
    }

    private func textState(_ element: AXUIElement) -> (text: String, range: CFRange)? {
        var value: CFTypeRef?, selection: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String,
              AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selection) == .success,
              let selection, CFGetTypeID(selection) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeDowncast(selection, to: AXValue.self), .cfRange, &range),
              range.location >= 0, range.location <= text.utf16.count else { return nil }
        return (text, range)
    }

    private func wordBeforeCursor(element: AXUIElement) -> (word: String, suffix: String)? {
        var value: CFTypeRef?
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String,
              AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeDowncast(rangeValue, to: AXValue.self), .cfRange, &range),
              range.length == 0, range.location >= 0, range.location <= (text as NSString).length else { return nil }
        guard let context = WordContext.beforeCursor(in: text, utf16Offset: range.location) else { return nil }
        return (context.word, context.suffix)
    }

    private func replace(count: Int, with text: String) {
        for _ in 0..<count {
            postKey(51, down: true)
            postKey(51, down: false)
        }
        insert(text)
    }

    private func postKey(_ key: CGKeyCode, down: Bool) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down) else { return }
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: injectedEventTag)
        event.post(tap: .cghidEventTap)
    }

    private func insert(_ text: String) {
        let characters = Array(text.utf16)
        // Keep each Unicode event small enough for applications with short event buffers.
        var offset = 0
        while offset < characters.count {
            var end = min(offset + 20, characters.count)
            if end < characters.count && (0xD800...0xDBFF).contains(characters[end - 1]) { end -= 1 }
            let chunk = Array(characters[offset..<end])
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                event.setIntegerValueField(.eventSourceUserData, value: injectedEventTag)
                event.post(tap: .cghidEventTap)
            }
            offset = end
        }
    }

    private func selectLayout(for text: String) {
        let language = text.contains(where: LayoutConverter.isRussian) ? "ru" : "en"
        let filter = [kTISPropertyInputSourceCategory!: kTISCategoryKeyboardInputSource!,
                      kTISPropertyInputSourceIsSelectCapable!: true] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else { return }
        for source in sources {
            guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { continue }
            let languages = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as NSArray
            if languages.contains(language) { TISSelectInputSource(source); return }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
