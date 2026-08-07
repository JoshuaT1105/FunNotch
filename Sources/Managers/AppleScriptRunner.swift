//
//  AppleScriptRunner.swift
//  FunNotch
//
//  NSAppleScript is not thread safe and blocks for tens of milliseconds, so all
//  scripts run on one dedicated thread with its own run loop and never on the
//  main thread.
//
//  Every failure is recorded. This used to be the opposite — errors were handed
//  to callers that ignored them, and callers all had a fallback — which meant a
//  script that could never run looked exactly like a missing permission. One
//  such script (`execute javascript "…" in tab 1`, which is not Chrome's word
//  order) failed on every poll for the whole life of the project and said so to
//  nobody.
//

import AppKit
import Foundation

/// The last failure per application, for the Diagnostics pane.
enum ScriptErrors {
    struct Failure {
        let application: String
        let message: String
        let date: Date
    }

    nonisolated(unsafe) private static var failures: [String: Failure] = [:]
    private static let lock = NSLock()

    static func record(source: String, message: String) {
        let application = applicationName(in: source) ?? "AppleScript"
        let failure = Failure(application: application, message: message, date: Date())

        lock.lock()
        let previous = failures[application]
        failures[application] = failure
        lock.unlock()

        // Polls repeat every couple of seconds; only say it when it changes,
        // otherwise the log is useless for anything else.
        guard previous?.message != message else { return }
        DiagnosticLog.write("script", "\(application): \(message)")
    }

    static func clear(application: String) {
        lock.lock()
        let existed = failures.removeValue(forKey: application) != nil
        lock.unlock()
        if existed {
            DiagnosticLog.write("script", "\(application): recovered")
        }
    }

    static var current: [Failure] {
        lock.lock()
        defer { lock.unlock() }
        return failures.values.sorted { $0.application < $1.application }
    }

    /// Pulls `Google Chrome` out of `tell application "Google Chrome"`.
    static func applicationName(in source: String) -> String? {
        guard let range = source.range(of: "tell application \"") else { return nil }
        let rest = source[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }
}

final class AppleScriptRunner: NSObject {
    static let shared = AppleScriptRunner()

    private let thread: Thread
    private var compiled: [String: NSAppleScript] = [:]
    private let lock = NSLock()

    private override init() {
        thread = ScriptThread()
        super.init()
        thread.name = "com.funnotch.applescript"
        thread.stackSize = 1 << 19
        thread.start()
    }

    private final class ScriptThread: Thread {
        override func main() {
            // Keep the run loop alive so `perform(_:on:)` always has a target.
            let port = Port()
            RunLoop.current.add(port, forMode: .default)
            while !isCancelled {
                RunLoop.current.run(mode: .default, before: .distantFuture)
            }
        }
    }

    private final class Box: NSObject {
        let source: String
        let completion: (NSAppleEventDescriptor?, String?) -> Void
        init(source: String, completion: @escaping (NSAppleEventDescriptor?, String?) -> Void) {
            self.source = source
            self.completion = completion
        }
    }

    /// Runs `source` asynchronously; the completion fires on the main queue.
    func run(_ source: String, completion: @escaping (NSAppleEventDescriptor?, String?) -> Void) {
        let box = Box(source: source) { descriptor, error in
            // Recorded here rather than at the call sites: every caller has a
            // fallback, so every caller was throwing these away.
            if let error {
                ScriptErrors.record(source: source, message: error)
            } else if let application = ScriptErrors.applicationName(in: source) {
                ScriptErrors.clear(application: application)
            }
            DispatchQueue.main.async { completion(descriptor, error) }
        }
        perform(#selector(executeOnScriptThread(_:)), on: thread, with: box, waitUntilDone: false)
    }

    /// Convenience for scripts whose result is a single string.
    func runForString(_ source: String, completion: @escaping (String?) -> Void) {
        run(source) { descriptor, _ in
            completion(descriptor?.stringValue)
        }
    }

    /// Fire-and-forget, for commands like play/pause.
    func execute(_ source: String) {
        run(source) { _, _ in }
    }

    @objc private func executeOnScriptThread(_ argument: Any) {
        guard let box = argument as? Box else { return }

        let script: NSAppleScript?
        lock.lock()
        if let cached = compiled[box.source] {
            script = cached
        } else if let fresh = NSAppleScript(source: box.source) {
            compiled[box.source] = fresh
            script = fresh
        } else {
            script = nil
        }
        lock.unlock()

        guard let script else {
            box.completion(nil, "could not compile script")
            return
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "unknown AppleScript error"
            box.completion(nil, message)
        } else {
            box.completion(result, nil)
        }
    }

    /// True when the app with this bundle identifier is currently running.
    static func isRunning(_ bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}
