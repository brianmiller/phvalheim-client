import Cocoa

// Minimal macOS URL scheme handler for phvalheim://
// Receives the URL via Apple Event (GetURL), forwards it to phvalheim-client as a CLI argument.

class URLHandlerDelegate: NSObject, NSApplicationDelegate {
    var receivedURL = false

    func application(_ application: NSApplication, open urls: [URL]) {
        receivedURL = true
        for url in urls {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/local/bin/phvalheim-client")
            task.arguments = [url.absoluteString]
            try? task.run()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Exit if no URL event arrives within 3 seconds (e.g. accidental direct launch)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            if !(self?.receivedURL ?? false) {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

let delegate = URLHandlerDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
