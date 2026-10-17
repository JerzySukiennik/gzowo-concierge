// Gzowo Concierge for macOS - entry point.
import AppKit

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let appDelegate = AppDelegate()
    application.delegate = appDelegate
    let islandOnly = CommandLine.arguments.contains("--island") && (UserDefaults.standard.object(forKey: "notchEnabled") as? Bool ?? true)
    application.setActivationPolicy(islandOnly ? .accessory : .regular)
    withExtendedLifetime(appDelegate) { application.run() }
}
