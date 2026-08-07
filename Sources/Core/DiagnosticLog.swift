//
//  DiagnosticLog.swift
//  FunNotch
//
//  Appends to ~/Library/Logs/FunNotch/funnotch.log. Drag and drop can
//  only really be exercised by a human hand on a mouse, so the drop path leaves
//  a trail that can be read afterwards.
//
//  The file has a ceiling. It is a debugging aid, not an archive: drags, drops,
//  media keys and Bluetooth events all write here, so left alone it grew for as
//  long as the app stayed installed — and the Diagnostics screen reads it back
//  to show the last few lines.
//

import Foundation

enum DiagnosticLog {
    private static let queue = DispatchQueue(label: "com.funnotch.log")

    /// Past `maxBytes` the file is trimmed back to roughly `keepBytes`, oldest
    /// lines first. A few hundred kilobytes is far more history than any bug
    /// report needs and still bounded.
    private static let maxBytes = 512 * 1024
    private static let keepBytes = 256 * 1024

    /// Checking the file size on every single line would mean a stat() per
    /// drag event, so it is only checked once a meaningful amount has been
    /// written. Only ever touched on `queue`, which is serial.
    private static var bytesSinceSizeCheck = 0

    /// Built once. Creating a date formatter is famously expensive, and the old
    /// code created one per line.
    private static let stamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let fileURL: URL = {
        let directory = FileManager.default
            .standardDirectory(.libraryDirectory, fallback: "Library")
            .appendingPathComponent("Logs/FunNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("funnotch.log")
    }()

    static func write(_ category: String, _ message: String) {
        // The instant is captured here so the line still carries the time the
        // event happened; the formatting itself is what moves off the caller.
        let when = Date()

        queue.async {
            let line = "\(stamp.string(from: when)) [\(category)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }

            bytesSinceSizeCheck += data.count
            if bytesSinceSizeCheck >= 64 * 1024 {
                bytesSinceSizeCheck = 0
                trimIfNeeded()
            }
        }
    }

    /// Starts a fresh log, so a reproduction is not buried in old lines.
    static func reset() {
        queue.async {
            try? FileManager.default.removeItem(at: fileURL)
            bytesSinceSizeCheck = 0
        }
    }

    /// The last `limit` bytes of the file, without reading the rest of it.
    /// The Diagnostics screen only ever shows the tail, and it asks on the main
    /// thread — so the whole file must never be pulled into memory to get it.
    static func tail(bytes limit: Int) -> String {
        guard let size = fileSize() else { return "" }
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return "" }
        defer { try? handle.close() }

        if size > limit {
            try? handle.seek(toOffset: UInt64(size - limit))
        }
        guard let data = try? handle.readToEnd() else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Private

    private static func fileSize() -> Int? {
        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize
    }

    /// Rewrites the file with only its tail. Runs on `queue`, never the main
    /// thread, so a trim cannot stall the UI.
    private static func trimIfNeeded() {
        guard let size = fileSize(), size > maxBytes else { return }
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }

        try? handle.seek(toOffset: UInt64(size - keepBytes))
        let tail = try? handle.readToEnd()
        try? handle.close()

        guard var data = tail else { return }

        // Seeking by byte lands mid-line, so drop the partial one — a log that
        // starts halfway through a sentence reads like corruption.
        if let newline = data.firstIndex(of: UInt8(ascii: "\n")) {
            data = Data(data[data.index(after: newline)...])
        }
        try? data.write(to: fileURL, options: .atomic)
    }
}
