import Foundation
import IOKit

/// An external monitor Tally Mic can send DDC/CI commands to over its video cable (SPEC 7.7).
///
/// On Apple silicon the cable is reached through `IOAVService`, which isn't public API:
/// MonitorControl, BetterDisplay, Lunar and m1ddc all use it, and it has stayed the same since
/// 2020. Its functions are looked up at run time, so if a macOS update removes them the feature
/// just finds no monitors.
///
/// Each exchange takes tens of milliseconds, so it all runs on one serial queue, off the main thread.
final class MonitorDDC: @unchecked Sendable {
    let vendorID: UInt32
    let productID: UInt32
    let name: String
    /// The `IOAVService`. Only used on `queue`.
    private let service: CFTypeRef

    static let queue = DispatchQueue(label: "dev.marcus.tally-mic.ddc", qos: .userInitiated)

    private init(vendorID: UInt32, productID: UInt32, name: String, service: CFTypeRef) {
        self.vendorID = vendorID
        self.productID = productID
        self.name = name
        self.service = service
    }

    var description: String { "\(name.isEmpty ? "unnamed display" : name) (vendor \(vendorID), product \(productID))" }

    // MARK: Finding monitors

    /// Every connected external display's DDC channel. Call on `queue`.
    ///
    /// The registry lists each display's framebuffer (with its vendor, product and name) and,
    /// further down, its `DCPAVServiceProxy`. Walking it in order and pairing each external proxy
    /// with the framebuffer before it is how MonitorControl matches them.
    static func externalDisplays() -> [MonitorDDC] {
        guard let create = AVService.create else {
            Log.error("Monitor volume: IOAVService isn't available on this macOS")
            return []
        }
        var iterator = io_iterator_t()
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var found: [MonitorDDC] = []
        var framebuffer: (vendor: UInt32, product: UInt32, name: String)?
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            let className = IOObjectCopyClass(entry)?.takeRetainedValue() as String?
            switch className {
            case "IOMobileFramebufferShim", "AppleCLCD2":
                framebuffer = attributes(of: entry)
            case "DCPAVServiceProxy":
                guard property(entry, "Location") as? String == "External" else { continue }
                guard let service = create(kCFAllocatorDefault, entry)?.takeRetainedValue() else { continue }
                let ids = framebuffer ?? (0, 0, "")
                found.append(MonitorDDC(vendorID: ids.vendor, productID: ids.product, name: ids.name, service: service))
                framebuffer = nil
            default:
                break
            }
        }
        return found
    }

    /// The display a sound output belongs to, by the IDs in its UID; or, failing that, the only
    /// external display there is. Call on `queue`.
    static func display(forOutputUID uid: String) -> MonitorDDC? {
        let displays = externalDisplays()
        if let ids = DisplayAudio.displayIDs(fromOutputUID: uid),
           let match = displays.first(where: { $0.vendorID == ids.vendor && $0.productID == ids.product }) {
            return match
        }
        return displays.count == 1 ? displays[0] : nil
    }

    private static func attributes(of entry: io_registry_entry_t) -> (UInt32, UInt32, String)? {
        guard let attributes = property(entry, "DisplayAttributes") as? [String: Any],
              let product = attributes["ProductAttributes"] as? [String: Any] else { return nil }
        let vendor = (product["LegacyManufacturerID"] as? Int).flatMap(UInt32.init(exactly:)) ?? 0
        let productID = (product["ProductID"] as? Int).flatMap(UInt32.init(exactly:)) ?? 0
        return (vendor, productID, product["ProductName"] as? String ?? "")
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    // MARK: Talking to it

    /// Reads a VCP value, such as the volume. Tries a few times: DDC is slow and sometimes drops
    /// a reply. Call on `queue`.
    func read(_ code: UInt8) -> (current: UInt16, max: UInt16)? {
        for attempt in 0..<6 {
            var request = DDC.getRequest(code, standard: attempt % 2 == 1)
            usleep(10_000)
            guard send(&request) else { usleep(20_000); continue }
            usleep(50_000)
            var reply = [UInt8](repeating: 0, count: 11)
            guard let read = AVService.read,
                  read(service, DDC.address, UInt32(DDC.hostAddress), &reply, UInt32(reply.count)) == kIOReturnSuccess,
                  let value = DDC.parseReply(reply, code: code) else {
                usleep(20_000)
                continue
            }
            return value
        }
        return nil
    }

    /// Sets a VCP value. Sent twice, as MonitorControl does, because some monitors miss one.
    /// Call on `queue`.
    @discardableResult
    func write(_ code: UInt8, _ value: UInt16) -> Bool {
        var request = DDC.setRequest(code, value)
        var sent = false
        for _ in 0..<2 {
            usleep(10_000)
            sent = send(&request) || sent
        }
        return sent
    }

    private func send(_ bytes: inout [UInt8]) -> Bool {
        guard let write = AVService.write else { return false }
        return write(service, DDC.address, UInt32(DDC.hostAddress), &bytes, UInt32(bytes.count)) == kIOReturnSuccess
    }
}

/// IOAVService's functions, found at run time (they're in IOKit but not in its headers).
private enum AVService {
    typealias Create = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    typealias Transfer = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    static let create: Create? = symbol("IOAVServiceCreateWithService")
    static let read: Transfer? = symbol("IOAVServiceReadI2C")
    static let write: Transfer? = symbol("IOAVServiceWriteI2C")

    private static func symbol<T>(_ name: String) -> T? {
        // RTLD_DEFAULT: IOKit is already loaded.
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}
