import AppKit

final class AppLaunchActivationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Xcode may briefly keep focus while attaching the debugger, so retry activation a few times.
        let delays: [DispatchTimeInterval] = [.milliseconds(0), .milliseconds(120), .milliseconds(350)]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NSApplication.shared.setActivationPolicy(.regular)
                _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
                NSApplication.shared.activate(ignoringOtherApps: true)
                for window in NSApplication.shared.windows {
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                }
            }
        }
    }
}
