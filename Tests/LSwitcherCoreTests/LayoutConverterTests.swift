import LSwitcherCore
import Foundation
import Dispatch

if let mode = CommandLine.arguments.first(where: { $0.hasPrefix("--storage=") }) {
    let start = DispatchTime.now().uptimeNanoseconds
    let lexicon = CompactLexicon.load()!
    let keys = try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: "benchmarks/lookup-keys.json")))
    var table: [String: CompactLexicon.Entry] = [:]
    let hash = mode == "--storage=hash"
    if hash {
        table.reserveCapacity(lexicon.count)
        lexicon.forEach { table[$0] = $1 }
    }
    let buildTime = DispatchTime.now().uptimeNanoseconds - start
    var hits = 0
    let queryStart = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<100 {
        for key in keys {
            let entry = hash ? table[key] : lexicon.lookup(Array(key.utf8))
            if entry != nil { hits += 1 }
        }
    }
    let queryTime = DispatchTime.now().uptimeNanoseconds - queryStart
    let output: [String: Any] = ["mode": hash ? "hash" : "compact", "entries": lexicon.count,
        "startup_ms": Double(buildTime)/1e6, "lookup_ns": Double(queryTime)/Double(100*keys.count), "hits": hits]
    print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), as: UTF8.self))
    exit(0)
}

let coldStart = DispatchTime.now().uptimeNanoseconds
guard LayoutConverter.prepareLexicon() else { fatalError("Packaged lexicon could not be loaded") }
let coldLoadMilliseconds = Double(DispatchTime.now().uptimeNanoseconds-coldStart)/1e6

// Standalone checks also run with Command Line Tools, without XCTest/Xcode.
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
expect(LayoutConverter.convert("Ghbdtn") == "Привет", "English to Russian, mixed case")
expect(LayoutConverter.convert("Руддщ") == "Hello", "Russian to English, mixed case")
expect(LayoutConverter.convert("ghbdtn vbh") == "привет мир", "Multiple words")
expect(LayoutConverter.convert("Ghbdtn 123 👋") == "Привет 123 👋", "Preserve digits and emoji")
expect(LayoutConverter.automaticReplacement(for: "ghbdtn") == "привет", "Automatic Russian")
expect(LayoutConverter.automaticReplacement(for: "руддщ") == "hello", "Automatic English")
expect(LayoutConverter.automaticReplacement(for: "ghbkj;tybt") == "приложение", "Physical semicolon maps to ж")
expect(LayoutConverter.automaticReplacement(for: "hfphf,jnrf") == "разработка", "Physical comma maps to б")
expect(LayoutConverter.automaticReplacement(for: "gthtrk.xtybt") == "переключение", "Physical period maps to ю")
expect(LayoutConverter.automaticReplacement(for: "Hfphf,jnrf") == "Разработка", "Case with unshifted punctuation")
for word in ["hello", "привет", "Swift", "https://example.com", "abc123", "a", "foobar"] {
    expect(LayoutConverter.automaticReplacement(for: word) == nil, "Do not replace: \(word)")
}
var detector = DoubleShiftDetector()
expect(!detector.update(isDown: true, time: 1), "First press")
expect(!detector.update(isDown: false, time: 1.05), "First release")
expect(!detector.update(isDown: true, time: 1.15), "Second press")
expect(detector.update(isDown: false, time: 1.2), "Double tap triggers on release")
expect(!detector.update(isDown: false, time: 1.21), "Duplicate release ignored")
expect(!detector.update(isDown: true, time: 2), "Hold starts")
expect(!detector.update(isDown: false, time: 3), "Holding is not a tap")
expect(!detector.update(isDown: true, time: 3.1), "Tap after hold")
expect(!detector.update(isDown: false, time: 3.15), "Hold did not arm shortcut")
detector.cancel()
_ = detector.update(isDown: true, time: 4)
_ = detector.update(isDown: false, time: 4.05)
_ = detector.update(isDown: true, time: 4.8)
expect(!detector.update(isDown: false, time: 4.85), "Slow taps do not trigger")
detector.cancel()
_ = detector.update(isDown: true, time: 5)
detector.cancel() // Any ordinary key or left Shift interrupts the gesture.
expect(!detector.update(isDown: false, time: 5.05), "Typing while holding Shift cancels")
_ = detector.update(isDown: true, time: 5.1)
expect(!detector.update(isDown: false, time: 5.15), "Capitalized word is not a double tap")
_ = detector.update(isDown: true, time: 5.2, otherModifiers: true)
expect(!detector.update(isDown: false, time: 5.25), "Other modifiers cancel")
expect(AutomaticExclusions.contains("com.apple.TextEdit", in: "\n com.apple.TextEdit \ncom.apple.Terminal"), "Whitespace in exclusion list")
expect(!AutomaticExclusions.contains("com.apple.TextEditHelper", in: "com.apple.TextEdit"), "Exact Bundle ID only")
expect(!AutomaticExclusions.contains("com.apple.TextEdit", in: ""), "Empty exclusion list")
let context = WordContext.beforeCursor(in: "👋 ghbdtn  ", utf16Offset: "👋 ghbdtn  ".utf16.count)
expect(context?.word == "ghbdtn" && context?.suffix == "  ", "Word after emoji and spaces")
expect(WordContext.beforeCursor(in: "hello\n", utf16Offset: 6) == nil, "Never cross a newline")
expect(WordContext.beforeCursor(in: "hello", utf16Offset: 0) == nil, "Empty prefix")
expect(WordContext.beforeCursor(in: "hello", utf16Offset: 50) == nil, "Invalid range")
expect(WordContext.beforeCursor(in: "ghbdtn world", utf16Offset: 6)?.word == "ghbdtn", "Word at moved cursor")
print("Passed layout conversion, gesture, exclusion and cursor-context checks.")

expect(LayoutConverter.lexiconEntryCount >= 70_000, "Expanded dictionary is packaged")
expect(CompactLexicon(data: Data()) == nil, "Reject empty dictionary")
expect(CompactLexicon(data: Data(repeating: 255, count: 24)) == nil, "Reject invalid dictionary")
if CommandLine.arguments.contains("--evaluate") {
    struct Case: Decodable {
        let input: String
        let expected: String?
        let decision: String?
        let kind: String
        let split: String
    }
    let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: URL(fileURLWithPath: "benchmarks/evaluation-cases.json")))
    var parityFailures = 0, truePositive = 0, falsePositive = 0
    var times: [UInt64] = []
    times.reserveCapacity(cases.count)
    for item in cases {
        let start = DispatchTime.now().uptimeNanoseconds
        let actual = LayoutConverter.automaticReplacement(for: item.input)
        times.append(DispatchTime.now().uptimeNanoseconds - start)
        if actual != item.decision {
            if parityFailures < 10 { print("Decision mismatch:",item.input, actual ?? "<abstain>", item.decision ?? "<abstain>") }
            parityFailures += 1
        }
        if item.expected == nil && actual != nil { falsePositive += 1 }
        if item.expected != nil && actual == item.expected { truePositive += 1 }
    }
    times.sort()
    let output: [String: Any] = ["cases":cases.count,"parity_failures":parityFailures,
        "true_positive":truePositive,"false_positive":falsePositive,
        "cold_load_ms":coldLoadMilliseconds,"p50_us":Double(times[times.count/2])/1000,
        "p95_us":Double(times[times.count*95/100])/1000,"p99_us":Double(times[times.count*99/100])/1000,
        "entries":LayoutConverter.lexiconEntryCount,"decoded_bytes":LayoutConverter.lexiconDecodedBytes]
    try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted,.sortedKeys])
        .write(to: URL(fileURLWithPath: "benchmarks/native-results.json"))
    print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), as: UTF8.self))
    expect(parityFailures == 0, "Native decisions must match selected offline policy")
    expect(times[times.count*99/100] < 1_000_000, "Warm p99 correction must stay below 1ms")
}
