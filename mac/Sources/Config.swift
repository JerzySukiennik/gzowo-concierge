// Gzowo Concierge for macOS - shared constants.
import AppKit

enum Config {
    static let base = ProcessInfo.processInfo.environment["CONCIERGE_BASE"] ?? "http://localhost:2040"
    static let host = URL(string: base)!
    static let sidebarWidth: CGFloat = 288
    static let inset: CGFloat = 10
    static let dragHeight: CGFloat = 12
    static let defaultSize = NSSize(width: 1180, height: 780)
    static let minSize = NSSize(width: 800, height: 580)
    static let localHosts: Set<String> = ["localhost", "127.0.0.1"]
}
