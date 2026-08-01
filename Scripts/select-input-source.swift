#!/usr/bin/env swift

import Carbon
import Foundation

let sourceID = "org.macwubi.inputmethod.MacWubi" as CFString
let filter = [kTISPropertyInputSourceID: sourceID] as CFDictionary
guard let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
      sources.count == 1,
      let source = sources.first else {
    FileHandle.standardError.write(Data("expected exactly one MacWubi input source\n".utf8))
    exit(1)
}
guard TISEnableInputSource(source) == noErr,
      TISSelectInputSource(source) == noErr else {
    FileHandle.standardError.write(Data("could not enable and select MacWubi input source\n".utf8))
    exit(1)
}
let selected = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
let selectedID = TISGetInputSourceProperty(selected, kTISPropertyInputSourceID)
    .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? "unknown"
print("sourceCount=\(sources.count)")
print("selectedSourceID=\(selectedID)")
