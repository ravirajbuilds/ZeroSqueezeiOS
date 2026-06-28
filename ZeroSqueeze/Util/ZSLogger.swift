import Foundation
import os

/// Redacted logger wrapper. Strips health PII from log statements before they reach
/// crash reporting. **Log the EVENT, never the VALUE.**
enum ZSLogCategory: String {
    case ppg    = "ZeroSqueeze/PPG"
    case ui     = "ZeroSqueeze/UI"
    case data   = "ZeroSqueeze/Data"
}

enum ZSLogLevel: String {
    case error = "ERROR"
    case warn  = "WARN"
    case info  = "INFO"
    case debug = "DEBUG"
}

enum ZSLogger {

    private static let stateLock = NSLock()
    // `nonisolated(unsafe)` here is the explicit "I am hand-synchronizing
    // this" annotation — every access below funnels through `stateLock`.
    nonisolated(unsafe) private static var _crashReportingEnabled = true
    nonisolated(unsafe) private static var _lastCrashReportEntry: CrashReportEntry?

    /// Whether crash reporting forwarding is enabled. Disable in tests.
    /// Lock-protected because logging APIs can be called from any thread.
    static var crashReportingEnabled: Bool {
        get { stateLock.withLock { _crashReportingEnabled } }
        set { stateLock.withLock { _crashReportingEnabled = newValue } }
    }

    /// Whether this is a debug build. Compile-time constant — safe across threads.
    static let isDebugBuild: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    private static func logger(for category: ZSLogCategory) -> Logger {
        Logger(subsystem: "com.zerosqueeze.zerosqueeze", category: category.rawValue)
    }

    static func error(
        _ category: ZSLogCategory,
        _ message: String,
        error: Error? = nil,
        file: String = #file,
        line: Int = #line
    ) {
        let decorated = decorateMessage(message, error: error, file: file, line: line)
        logger(for: category).error("\(decorated, privacy: .public)")
        if !isDebugBuild && crashReportingEnabled {
            forwardToCrashReporting(category, .error, decorated, error: error)
        }
    }

    static func warn(
        _ category: ZSLogCategory,
        _ message: String,
        error: Error? = nil,
        file: String = #file,
        line: Int = #line
    ) {
        let decorated = decorateMessage(message, error: error, file: file, line: line)
        logger(for: category).warning("\(decorated, privacy: .public)")
        if !isDebugBuild && crashReportingEnabled {
            forwardToCrashReporting(category, .warn, decorated, error: error)
        }
    }

    static func info(
        _ category: ZSLogCategory,
        _ message: String,
        file: String = #file,
        line: Int = #line
    ) {
        let decorated = decorateMessage(message, error: nil, file: file, line: line)
        logger(for: category).info("\(decorated, privacy: .public)")
    }

    static func debug(
        _ category: ZSLogCategory,
        _ message: String,
        file: String = #file,
        line: Int = #line
    ) {
        guard isDebugBuild else { return }
        let decorated = decorateMessage(message, error: nil, file: file, line: line)
        logger(for: category).debug("\(decorated, privacy: .public)")
    }

    // ── Redaction helpers ──────────────────────────────────────────────

    /// Generic redaction sentinel. Use for any value type that shouldn't leak
    /// to OSLog or crash reports. Per-type helpers (heart rate, MAC address,
    /// etc.) were carried over from ZeroSqueeze and removed once unused; add new
    /// ones only when a real call site requires the distinct label.
    static func redact(_ value: Any?) -> String { "[redacted]" }

    // ── Internal ───────────────────────────────────────────────────────

    private static func decorateMessage(
        _ message: String, error: Error?, file: String, line: Int
    ) -> String {
        let filename = (file as NSString).lastPathComponent
        let location = "\(filename):\(line) — "
        if let error {
            return "\(location)\(message) | error: \(type(of: error))(\(error.localizedDescription))"
        }
        return "\(location)\(message)"
    }

    struct CrashReportEntry {
        let level: ZSLogLevel
        let category: ZSLogCategory
        let message: String
        let error: Error?
    }

    /// Lock-protected — written by `forwardToCrashReporting` (any thread),
    /// read by test assertions.
    static var lastCrashReportEntry: CrashReportEntry? {
        stateLock.withLock { _lastCrashReportEntry }
    }

    private static func forwardToCrashReporting(
        _ category: ZSLogCategory,
        _ level: ZSLogLevel,
        _ message: String,
        error: Error?
    ) {
        // TODO: integrate Firebase Crashlytics or Sentry.
        stateLock.withLock {
            _lastCrashReportEntry = CrashReportEntry(level: level, category: category, message: message, error: error)
        }
    }

    static func resetTestState() {
        stateLock.withLock { _lastCrashReportEntry = nil }
    }
}
