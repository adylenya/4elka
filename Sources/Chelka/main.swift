import AppKit
import ChelkaCore

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = ChelkaAppDelegate()
app.delegate = delegate
app.run()
