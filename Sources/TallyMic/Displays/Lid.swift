import IOKit

/// The MacBook lid (SPEC 6.2). With the lid shut, Apple silicon MacBooks disconnect the built-in
/// mic in hardware, but macOS keeps listing it, so Tally Mic reads the lid itself.
enum Lid {
    /// True when the lid is closed. Nil on Macs without a lid or if IOKit doesn't say.
    static func isClosed() -> Bool? {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != 0 else { return nil }
        defer { IOObjectRelease(rootDomain) }
        let value = IORegistryEntryCreateCFProperty(
            rootDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return value?.takeRetainedValue() as? Bool
    }
}

/// Calls `onChange` when the lid opens or closes (SPEC 7.4). The power manager sends its general
/// messages (lid, sleep, wake) to anyone interested; on each, the lid state is read again and
/// compared, rather than relying on one message code.
@MainActor
final class LidMonitor {
    var onChange: ((Bool) -> Void)?
    private(set) var isClosed: Bool
    private var port: IONotificationPortRef?
    private var notification: io_object_t = 0

    init() {
        isClosed = Lid.isClosed() ?? false
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        IONotificationPortSetDispatchQueue(port, .main)
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != 0 else { return }
        defer { IOObjectRelease(rootDomain) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = IOServiceAddInterestNotification(port, rootDomain, kIOGeneralInterest, { context, _, _, _ in
            guard let context else { return }
            let monitor = Unmanaged<LidMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.check() }
        }, context, &notification)
        if status != KERN_SUCCESS { Log.error("Couldn't watch the lid (status \(status))") }
    }

    private func check() {
        guard let closed = Lid.isClosed(), closed != isClosed else { return }
        isClosed = closed
        Log.info("Lid \(closed ? "closed" : "opened")")
        onChange?(closed)
    }
}
