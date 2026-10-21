import AppKit

// NSApplication holds its delegate weakly, so keep a strong reference for the app's lifetime.
let appDelegate = AppDelegate()
NSApplication.shared.delegate = appDelegate
NSApplication.shared.run()
