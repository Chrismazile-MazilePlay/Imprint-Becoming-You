//
//  AppLogger.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/30/26.
//

import Foundation
import os.log
import os.signpost

// MARK: - Log Level

/// Severity levels for log messages.
///
/// Lower levels are more verbose and are typically filtered out in release builds.
enum LogLevel: Int, Comparable, Sendable {
    /// Detailed debugging information (DEBUG only)
    case debug = 0
    
    /// General information about app flow (DEBUG only)
    case info = 1
    
    /// Potentially problematic situations (always logged)
    case warning = 2
    
    /// Errors that don't crash but affect functionality (always logged)
    case error = 3
    
    /// Critical errors that may crash or corrupt data (always logged)
    case critical = 4
    
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    /// The os.log type corresponding to this level
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }
    
    /// Emoji prefix for console output
    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🚨"
        }
    }
}

// MARK: - Log Category

/// Categories for organizing log messages by feature/subsystem.
///
/// Each category creates a separate os.log subsystem for filtering in Console.app.
enum LogCategory: String, Sendable {
    /// App lifecycle, initialization, configuration
    case app = "App"
    
    /// Audio playback, background music, audio session
    case audio = "Audio"
    
    /// Speech recognition and analysis
    case speech = "Speech"
    
    /// Text-to-speech synthesis
    case tts = "TTS"
    
    /// SwiftData operations, repositories
    case data = "Data"
    
    /// Network requests, API calls
    case network = "Network"
    
    /// Practice session flow, state machine
    case practice = "Practice"
    
    /// UI rendering, animations
    case ui = "UI"
    
    /// Memory management, resource cleanup
    case memory = "Memory"
    
    /// Authentication, subscription
    case auth = "Auth"
    
    /// The os.log Logger for this category
    var logger: Logger {
        Logger(subsystem: "com.imprint.app", category: rawValue)
    }
}

// MARK: - App Logger

/// Centralized logging utility for the Imprint app.
///
/// ## Features
/// - Conditional logging based on build configuration
/// - Category-based filtering for Console.app
/// - Consistent formatting across the app
/// - Thread-safe (uses os.log under the hood)
/// - **Performance signposts for Instruments profiling**
///
/// ## Log Levels
/// - `.debug` / `.info`: Only logged in DEBUG builds
/// - `.warning` / `.error` / `.critical`: Always logged
///
/// ## Usage
/// ```swift
/// // Simple logging
/// AppLogger.debug("Starting audio engine", category: .audio)
/// AppLogger.error("Failed to save", category: .data)
///
/// // With context
/// AppLogger.warning("Entity not found", category: .data, context: ["id": affirmationId])
///
/// // Errors
/// AppLogger.error("Save failed", category: .data, error: error)
///
/// // Performance measurement
/// let id = AppLogger.makeSignpostID(for: .tts)
/// AppLogger.beginInterval(.ttsSynthesis, id: id, category: .tts)
/// // ... operation
/// AppLogger.endInterval(.ttsSynthesis, id: id, category: .tts)
///
/// // Or use convenience wrapper
/// try await AppLogger.measureAsync(.ttsSynthesis, category: .tts) {
///     try await synthesizeAudio()
/// }
/// ```
///
/// ## Viewing Logs
/// Use Console.app and filter by:
/// - Subsystem: `com.imprint.app`
/// - Category: `Audio`, `Data`, `TTS`, etc.
///
/// ## Viewing Signposts
/// Use Instruments with the "Points of Interest" or "os_signpost" instrument.
/// Filter by subsystem `com.imprint.app` and category `Performance.*`.
enum AppLogger {
    
    // MARK: - Minimum Log Level
    
    /// Minimum level to log in release builds
    /// Debug/Info are always filtered in release
    #if DEBUG
    private static let minimumLevel: LogLevel = .debug
    #else
    private static let minimumLevel: LogLevel = .warning
    #endif
    
    // MARK: - Logging Methods
    
    /// Logs a debug message (DEBUG builds only).
    ///
    /// Use for detailed debugging information that helps trace execution flow.
    ///
    /// - Parameters:
    ///   - message: The message to log
    ///   - category: The log category
    ///   - context: Optional dictionary of contextual values
    ///   - file: Source file (auto-filled)
    ///   - function: Function name (auto-filled)
    ///   - line: Line number (auto-filled)
    static func debug(
        _ message: String,
        category: LogCategory,
        context: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .debug, message: message, category: category, context: context, error: nil, file: file, function: function, line: line)
    }
    
    /// Logs an info message (DEBUG builds only).
    ///
    /// Use for general information about app flow and state changes.
    ///
    /// - Parameters:
    ///   - message: The message to log
    ///   - category: The log category
    ///   - context: Optional dictionary of contextual values
    ///   - file: Source file (auto-filled)
    ///   - function: Function name (auto-filled)
    ///   - line: Line number (auto-filled)
    static func info(
        _ message: String,
        category: LogCategory,
        context: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .info, message: message, category: category, context: context, error: nil, file: file, function: function, line: line)
    }
    
    /// Logs a warning message (always logged).
    ///
    /// Use for potentially problematic situations that don't prevent operation
    /// but might indicate issues.
    ///
    /// - Parameters:
    ///   - message: The message to log
    ///   - category: The log category
    ///   - context: Optional dictionary of contextual values
    ///   - file: Source file (auto-filled)
    ///   - function: Function name (auto-filled)
    ///   - line: Line number (auto-filled)
    static func warning(
        _ message: String,
        category: LogCategory,
        context: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .warning, message: message, category: category, context: context, error: nil, file: file, function: function, line: line)
    }
    
    /// Logs an error message (always logged).
    ///
    /// Use for errors that don't crash the app but affect functionality.
    ///
    /// - Parameters:
    ///   - message: The message to log
    ///   - category: The log category
    ///   - error: Optional underlying error
    ///   - context: Optional dictionary of contextual values
    ///   - file: Source file (auto-filled)
    ///   - function: Function name (auto-filled)
    ///   - line: Line number (auto-filled)
    static func error(
        _ message: String,
        category: LogCategory,
        error: Error? = nil,
        context: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .error, message: message, category: category, context: context, error: error, file: file, function: function, line: line)
    }
    
    /// Logs a critical error message (always logged).
    ///
    /// Use for critical errors that may cause crashes, data corruption,
    /// or require immediate attention.
    ///
    /// - Parameters:
    ///   - message: The message to log
    ///   - category: The log category
    ///   - error: Optional underlying error
    ///   - context: Optional dictionary of contextual values
    ///   - file: Source file (auto-filled)
    ///   - function: Function name (auto-filled)
    ///   - line: Line number (auto-filled)
    static func critical(
        _ message: String,
        category: LogCategory,
        error: Error? = nil,
        context: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .critical, message: message, category: category, context: context, error: error, file: file, function: function, line: line)
    }
    
    // MARK: - Private Implementation
    
    /// Core logging implementation.
    private static func log(
        level: LogLevel,
        message: String,
        category: LogCategory,
        context: [String: Any]?,
        error: Error?,
        file: String,
        function: String,
        line: Int
    ) {
        // Filter by minimum level
        guard level >= minimumLevel else { return }
        
        // Build the full message
        var fullMessage = message
        
        // Add context if provided
        if let context = context, !context.isEmpty {
            let contextString = context.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            fullMessage += " [\(contextString)]"
        }
        
        // Add error if provided
        if let error = error {
            fullMessage += " | Error: \(error.localizedDescription)"
        }
        
        // Log to os.log
        let logger = category.logger
        logger.log(level: level.osLogType, "\(level.emoji) \(fullMessage)")
        
        // Also print to console in DEBUG for Xcode visibility
        #if DEBUG
        let fileName = (file as NSString).lastPathComponent
        print("\(level.emoji) [\(category.rawValue)] \(fullMessage) (\(fileName):\(line))")
        #endif
    }
}

// MARK: - Convenience Extensions

extension AppLogger {
    
    /// Logs that an entity was not found (common pattern).
    ///
    /// - Parameters:
    ///   - entityType: Type of entity (e.g., "Affirmation")
    ///   - id: The ID that wasn't found
    ///   - category: Log category (defaults to .data)
    static func entityNotFound(
        _ entityType: String,
        id: UUID,
        category: LogCategory = .data
    ) {
        debug("\(entityType) not found", category: category, context: ["id": id.uuidString])
    }
    
    /// Logs a best-effort operation that completed without error handling.
    ///
    /// - Parameters:
    ///   - operation: Description of the operation
    ///   - category: Log category
    static func bestEffort(
        _ operation: String,
        category: LogCategory
    ) {
        debug("Best-effort operation: \(operation)", category: category)
    }
}

// MARK: - Performance Signpost Support

extension AppLogger {
    
    // MARK: - Signpost Names
    
    /// Predefined signpost names for consistent Instruments display.
    ///
    /// Using `StaticString` is required by os_signpost API for performance.
    /// These names appear in Instruments' Points of Interest track.
    enum SignpostName {
        /// TTS engine warm-up (loading ML models)
        static let ttsWarmup: StaticString = "TTS Warmup"
        
        /// Individual TTS synthesis operation
        static let ttsSynthesis: StaticString = "TTS Synthesis"
        
        /// TTS audio playback
        static let ttsPlayback: StaticString = "TTS Playback"
        
        /// Speech recognition initialization
        static let speechRecognitionInit: StaticString = "Speech Recognition Init"
        
        /// Active speech capture duration
        static let speechCapture: StaticString = "Speech Capture"
        
        /// Speech analysis processing
        static let speechAnalysis: StaticString = "Speech Analysis"
        
        /// Full session preparation (Kokoro wait + synthesis)
        static let sessionPreparation: StaticString = "Session Preparation"
        
        /// Audio session configuration
        static let audioSessionConfig: StaticString = "Audio Session Config"
        
        /// SwiftData fetch operation
        static let swiftDataFetch: StaticString = "SwiftData Fetch"
        
        /// Practice flow execution
        static let flowExecution: StaticString = "Flow Execution"
        
        /// Listening phase (preparing + active listening)
        static let listeningPhase: StaticString = "Listening Phase"
    }
    
    // MARK: - Signpost Log
    
    /// Returns the signpost log for a given category.
    ///
    /// Uses `Performance.<Category>` naming for organization in Instruments.
    private static func signpostLog(for category: LogCategory) -> OSLog {
        OSLog(subsystem: "com.imprint.app", category: "Performance.\(category.rawValue)")
    }
    
    // MARK: - Signpost ID Management
    
    /// Creates a unique signpost ID for tracking async operations.
    ///
    /// Use when multiple instances of the same operation may overlap.
    /// The ID correlates begin/end pairs in Instruments.
    ///
    /// ## Example
    /// ```swift
    /// let id = AppLogger.makeSignpostID(for: .tts)
    /// AppLogger.beginInterval(.ttsSynthesis, id: id, category: .tts)
    /// // ... async work
    /// AppLogger.endInterval(.ttsSynthesis, id: id, category: .tts)
    /// ```
    ///
    /// - Parameter category: Log category for the signpost
    /// - Returns: Unique signpost ID
    static func makeSignpostID(for category: LogCategory) -> OSSignpostID {
        OSSignpostID(log: signpostLog(for: category))
    }
    
    // MARK: - Interval Tracking
    
    /// Begins a signpost interval for performance measurement.
    ///
    /// Call `endInterval` with the same name and ID to complete measurement.
    /// Visible in Instruments > Points of Interest track.
    ///
    /// - Parameters:
    ///   - name: Static string name for the interval (use `SignpostName` constants)
    ///   - id: Unique identifier for this interval instance (use `.exclusive` for non-overlapping)
    ///   - category: Log category for organization
    ///
    /// ## Example
    /// ```swift
    /// let signpostID = AppLogger.makeSignpostID(for: .tts)
    /// AppLogger.beginInterval(.ttsSynthesis, id: signpostID, category: .tts)
    /// defer { AppLogger.endInterval(.ttsSynthesis, id: signpostID, category: .tts) }
    /// ```
    static func beginInterval(
        _ name: StaticString,
        id: OSSignpostID = .exclusive,
        category: LogCategory
    ) {
        #if DEBUG
        let log = signpostLog(for: category)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        #endif
    }
    
    /// Ends a signpost interval.
    ///
    /// - Parameters:
    ///   - name: Must match the name used in `beginInterval`
    ///   - id: Must match the ID used in `beginInterval`
    ///   - category: Must match the category used in `beginInterval`
    static func endInterval(
        _ name: StaticString,
        id: OSSignpostID = .exclusive,
        category: LogCategory
    ) {
        #if DEBUG
        let log = signpostLog(for: category)
        os_signpost(.end, log: log, name: name, signpostID: id)
        #endif
    }
    
    /// Emits a single signpost event (not an interval).
    ///
    /// Use for instantaneous events like button taps or state changes.
    ///
    /// - Parameters:
    ///   - name: Event name
    ///   - category: Log category
    ///   - message: Optional descriptive message
    static func event(
        _ name: StaticString,
        category: LogCategory,
        message: String = ""
    ) {
        #if DEBUG
        let log = signpostLog(for: category)
        os_signpost(.event, log: log, name: name, "%{public}s", message)
        #endif
    }
    
    // MARK: - Convenience Measurement Methods
    
    /// Measures the duration of a synchronous closure.
    ///
    /// Automatically emits begin/end signposts around the closure.
    ///
    /// - Parameters:
    ///   - name: Interval name (use `SignpostName` constants)
    ///   - category: Log category
    ///   - operation: Closure to measure
    /// - Returns: Result of the closure
    ///
    /// ## Example
    /// ```swift
    /// let result = AppLogger.measure(.swiftDataFetch, category: .data) {
    ///     try context.fetch(descriptor)
    /// }
    /// ```
    @discardableResult
    static func measure<T>(
        _ name: StaticString,
        category: LogCategory,
        operation: () throws -> T
    ) rethrows -> T {
        let id = makeSignpostID(for: category)
        beginInterval(name, id: id, category: category)
        defer { endInterval(name, id: id, category: category) }
        return try operation()
    }
    
    /// Measures the duration of an async closure.
    ///
    /// Automatically emits begin/end signposts around the closure.
    ///
    /// - Parameters:
    ///   - name: Interval name (use `SignpostName` constants)
    ///   - category: Log category
    ///   - operation: Async closure to measure
    /// - Returns: Result of the closure
    ///
    /// ## Example
    /// ```swift
    /// let audioData = try await AppLogger.measureAsync(.ttsSynthesis, category: .tts) {
    ///     try await kokoroEngine.synthesizeToData(text: text, voiceStyle: style)
    /// }
    /// ```
    @discardableResult
    static func measureAsync<T>(
        _ name: StaticString,
        category: LogCategory,
        operation: () async throws -> T
    ) async rethrows -> T {
        let id = makeSignpostID(for: category)
        beginInterval(name, id: id, category: category)
        defer { endInterval(name, id: id, category: category) }
        return try await operation()
    }
}
