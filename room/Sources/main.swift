// Concierge Pokój - entry point: a background app (no Dock icon) that runs the room assistant.
import AppKit

final class RoomApp: NSObject, NSApplicationDelegate {
    let room = Room()

    func applicationDidFinishLaunching(_ notification: Notification) {
        room.start()
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("fun.gzowo.concierge.room-test"), object: nil, queue: .main) { [weak self] note in
            if let path = note.object as? String { self?.room.playTest(path) }
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("fun.gzowo.concierge.room-shot"), object: nil, queue: .main) { [weak self] note in
            if let path = note.object as? String { self?.room.snapshot(path) }
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("fun.gzowo.concierge.room-record"), object: nil, queue: .main) { [weak self] note in
            if let spec = note.object as? String { self?.room.record(spec) }
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("fun.gzowo.concierge.room-ear"), object: nil, queue: .main) { [weak self] note in
            if let line = note.object as? String { self?.room.earCommand(line) }
        }
    }
}

let app = NSApplication.shared
let delegate = RoomApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
