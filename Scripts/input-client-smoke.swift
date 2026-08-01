#!/usr/bin/env swift

import AppKit
import Carbon
import Foundation

let application = NSApplication.shared
application.setActivationPolicy(.regular)

let window = NSWindow(
    contentRect: NSRect(x: 100, y: 100, width: 480, height: 180),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
let textView = NSTextView(frame: window.contentView?.bounds ?? .zero)
textView.autoresizingMask = [.width, .height]
window.contentView = textView
window.makeKeyAndOrderFront(nil)
application.activate(ignoringOtherApps: true)

for _ in 0..<5 {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
}

let sourceFilter = [
    kTISPropertyInputSourceID: "org.macwubi.inputmethod.MacWubi" as CFString
] as CFDictionary
guard let sources = TISCreateInputSourceList(sourceFilter, false)?.takeRetainedValue()
        as? [TISInputSource],
      let source = sources.first,
      TISSelectInputSource(source) == noErr else {
    FileHandle.standardError.write(Data("could not select MacWubi for smoke client\n".utf8))
    exit(1)
}
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
window.makeFirstResponder(textView)
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))

let keys: [(String, UInt16)] = [("w", 13), ("q", 12), ("v", 9), ("b", 11), (" ", 49)]
var handled = [Bool]()
for (character, keyCode) in keys {
    guard let event = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        characters: character,
        charactersIgnoringModifiers: character,
        isARepeat: false,
        keyCode: keyCode
    ) else {
        FileHandle.standardError.write(Data("could not construct key event\n".utf8))
        exit(1)
    }
    application.sendEvent(event)
    handled.append(true)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
}

print("handled=\(handled.map { $0 ? "1" : "0" }.joined())")
print("commitMatched=\(textView.string == "你好" ? 1 : 0)")
print("committedUTF16Length=\(textView.string.utf16.count)")
window.close()
