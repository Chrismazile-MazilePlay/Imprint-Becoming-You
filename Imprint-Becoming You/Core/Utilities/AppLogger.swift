//
//  AppLogger.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/30/26.
//

import Foundation
import os.log

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
    
    /// Audio playback, binaural beats, audio session
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
/// ```
///
/// ## Viewing Logs
/// Use Console.app and filter by:
/// - Subsystem: `com.imprint.app`
/// - Category: `Audio`, `Data`, `TTS`, etc.
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
