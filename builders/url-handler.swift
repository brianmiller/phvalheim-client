import Cocoa

// Minimal macOS URL scheme handler for phvalheim://
// Receives the URL via Apple Event (GetURL), opens a Terminal window running
// phvalheim-client so the user can see loading progress.

class URLHandlerDelegate: NSObject, NSApplicationDelegate {
    var receivedURL = false

    func application(_ application: NSApplication, open urls: [URL]) {
        receivedURL = true
        for url in urls {
            // Write a temp shell script and open it in Terminal — gives the user
            // a visible progress window identical to the Linux/Windows experience.
            let scriptPath = "/tmp/phvalheim-launch-\(ProcessInfo.processInfo.processIdentifier).sh"
            let scriptContent = "#!/bin/bash\n/usr/local/bin/phvalheim-client \"\(url.absoluteString)\"\n"
            let scriptURL = URL(fileURLWithPath: scriptPath)
            try? scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", "Terminal", scriptPath]
            try? task.run()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
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
