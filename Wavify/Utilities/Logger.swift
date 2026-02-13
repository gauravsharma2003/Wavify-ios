//
//  Logger.swift
//  Wavify
//
//  Structured logging utility for consistent error handling and debugging
//

import Foundation
import os.log

// MARK: - Log Categories

enum LogCategory: String {
    case playback = "Playback"
    case network = "Network"
    case data = "Data"
    case ui = "UI"
    case lyrics = "Lyrics"
    case charts = "Charts"
    case cache = "Cache"
    case sharePlay = "SharePlay"

    var osLogCategory: String {
        switch self {
        case .playback: return "Playback"
        case .network: return "Network"
        case .data: return "Data"
        case .ui: return "UI"
        case .lyrics: return "Lyrics"
        case .charts: return "Charts"
        case .cache: return "Cache"
        case .sharePlay: return "SharePlay"
        }
    }
}

// MARK: - Log Levels

enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    
    var emoji: String {
        switch self {
        case .debug: return "Debug:"
        case .info: return "Info:"
        case .warning: return "Warn:"
        case .error: return "Error:"
        }
    }
    
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }
    
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Logger

struct Logger {
    /// Minimum log level to output (configurable for debug vs release)
    #if DEBUG
    static var minimumLevel: LogLevel = .debug
    #else
    static var minimumLevel: LogLevel = .warning
    #endif
    
    /// Whether to use Apple's unified logging (os_log) in addition to print
    static var useUnifiedLogging = true
    
    // MARK: - Primary Logging Methods
    
    /// Log a message with category and level
    static func log(
        _ message: String,
        category: LogCategory,
        level: LogLevel = .info,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard level >= minimumLevel else { return }
        
        let filename = (file as NSString).lastPathComponent
        let formattedMessage = "\(level.emoji) \(category.rawValue): \(message)"
        
        #if DEBUG
        let debugInfo = "[\(filename):\(line) \(function)]"
        print("\(formattedMessage) \(debugInfo)")
        #else
        print(formattedMessage)
        #endif
        
        if useUnifiedLogging {
            let osLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "Wavify", category: category.osLogCategory)
            os_log("%{public}@", log: osLog, type: level.osLogType, message)
        }
    }
    
    /// Log an error with optional Error object
    static func error(
        _ message: String,
        category: LogCategory,
        error: Error? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        var fullMessage = message
        if let error = error {
            fullMessage += " | Error: \(error.localizedDescription)"
        }
        
        log(fullMessage, category: category, level: .error, file: file, function: function, line: line)
    }
    
    /// Log a warning
    static func warning(
        _ message: String,
        category: LogCategory,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, category: category, level: .warning, file: file, function: function, line: line)
    }
    
    /// Log debug information (only in DEBUG builds)
    static func debug(
        _ message: String,
        category: LogCategory,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, category: category, level: .debug, file: file, function: function, line: line)
    }
    
    // MARK: - Convenience Methods
    
    /// Log a network error with retry suggestion
    static func networkError(
        _ message: String,
        error: Error? = nil,
        endpoint: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        var fullMessage = message
        if let endpoint = endpoint {
            fullMessage += " [Endpoint: \(endpoint)]"
        }
        self.error(fullMessage, category: .network, error: error, file: file, function: function, line: line)
    }
    
    /// Log a data/persistence error
    static func dataError(
        _ message: String,
        error: Error? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        self.error(message, category: .data, error: error, file: file, function: function, line: line)
    }
    
    /// Log a playback error
    static func playbackError(
        _ message: String,
        error: Error? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        self.error(message, category: .playback, error: error, file: file, function: function, line: line)
    }
}
