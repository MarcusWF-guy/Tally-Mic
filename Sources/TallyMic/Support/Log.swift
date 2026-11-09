import Foundation
import os

/// Logs to the unified log (subsystem dev.marcus.tally-mic) and to
/// ~/Library/Logs/Tally Mic/tally-mic.log, which rolls over at 2 MB (SPEC 10).
enum Log {
    static func debug(_ message: String) { write(message, level: "DEBUG", type: .debug) }
    static func info(_ message: String) { write(message, level: "INFO", type: .info) }
    static func error(_ message: String) { write(message, level: "ERROR", type: .error) }

    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Tally Mic/tally-mic.log")

    static let bundleID = "dev.marcus.tally-mic"
    private static let logger = Logger(subsystem: bundleID, category: "app")
    private static let queue = DispatchQueue(label: "\(bundleID).log")
    private static let maxBytes: UInt64 = 2 * 1024 * 1024

    /// Only the app writes the log file, so test runs never add to the real log.
    private static let writesFile = Bundle.main.bundleIdentifier == bundleID

    /// The last lines of the log file, oldest first, for Copy Diagnostics.
    static func lastLines(_ count: Int) -> [String] {
        queue.sync {}  // Let pending writes land first.
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return Array(text.split(separator: "\n", omittingEmptySubsequences: true).suffix(count).map(String.init))
    }

    private static func write(_ message: String, level: String, type: OSLogType) {
        logger.log(level: type, "\(message, privacy: .public)")
        guard writesFile else { return }
        let line = "\(Date().formatted(.iso8601)) \(level) \(message)\n"
        queue.async { append(line) }
    }

    private static func append(_ line: String) {
        let manager = FileManager.default
        try? manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if let size = try? manager.attributesOfItem(atPath: fileURL.path)[.size] as? UInt64, size > maxBytes {
            let previous = fileURL.appendingPathExtension("1")
            try? manager.removeItem(at: previous)
            try? manager.moveItem(at: fileURL, to: previous)
        }
        if !manager.fileExists(atPath: fileURL.path) {
            manager.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }
}
