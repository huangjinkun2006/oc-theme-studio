import AppKit

// Keep a strong reference: NSApplication.delegate is a weak property.
let appDelegate = AppDelegate()
let application = NSApplication.shared
application.delegate = appDelegate
application.run()
