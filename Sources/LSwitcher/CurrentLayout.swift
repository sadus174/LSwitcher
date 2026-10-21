import Foundation
import Carbon
import LSwitcherCore

enum CurrentLayout {
    static var presentation: LayoutPresentation {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return LayoutPresentation(language: "", sourceID: "")
        }
        var language = "", identifier = ""
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) {
            let languages = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as NSArray
            language = languages.firstObject as? String ?? ""
        }
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            identifier = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
        }
        return LayoutPresentation(language: language, sourceID: identifier)
    }
}
