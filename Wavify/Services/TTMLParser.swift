//
//  TTMLParser.swift
//  Wavify
//
//  Parses TTML (Timed Text Markup Language) XML from BetterLyrics/Paxsenix
//  into SyncedLyricLine arrays with word-level SyncedWord timing.
//

import Foundation

final class TTMLParser: NSObject, XMLParserDelegate {

    private var lines: [SyncedLyricLine] = []
    private var currentWords: [SyncedWord] = []
    private var currentPBegin: Double?
    private var currentPEnd: Double?
    private var currentSpanBegin: Double?
    private var currentSpanEnd: Double?
    private var currentText = ""
    private var bareLineText = ""
    private var insideP = false
    private var insideSpan = false
    private var hadSpans = false
    private var parseError: Error?

    // Global lyric offset from <audio lyricOffset="..."> in TTML head
    private var lyricOffset: Double = 0

    // Credit lines to filter out
    private static let creditPatterns: [String] = [
        "synced by", "lyrics by", "music by", "arranged by",
        "written by", "composed by", "produced by"
    ]

    // MARK: - Public

    func parse(_ ttmlString: String) -> [SyncedLyricLine]? {
        guard let data = ttmlString.data(using: .utf8) else { return nil }

        // Reset state
        lines = []
        currentWords = []
        currentPBegin = nil
        currentPEnd = nil
        currentSpanBegin = nil
        currentSpanEnd = nil
        currentText = ""
        bareLineText = ""
        insideP = false
        insideSpan = false
        hadSpans = false
        parseError = nil
        lyricOffset = 0

        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldResolveExternalEntities = false
        parser.parse()

        guard parseError == nil, !lines.isEmpty else { return nil }

        // Filter credit lines
        let filtered = lines.filter { line in
            let lower = line.text.lowercased()
            return !Self.creditPatterns.contains { lower.contains($0) }
        }

        return filtered.sorted { $0.time < $1.time }
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch elementName {
        case "audio":
            // Extract global lyric offset from <audio lyricOffset="...">
            if let offsetStr = attributes["lyricOffset"],
               let offset = Double(offsetStr) {
                lyricOffset = offset
            }

        case "p":
            insideP = true
            hadSpans = false
            currentWords = []
            bareLineText = ""
            currentPBegin = parseTimeAttribute(attributes["begin"])
            currentPEnd = parseTimeAttribute(attributes["end"])

        case "span" where insideP:
            insideSpan = true
            hadSpans = true
            currentText = ""
            currentSpanBegin = parseTimeAttribute(attributes["begin"])
            currentSpanEnd = parseTimeAttribute(attributes["end"])

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideSpan {
            currentText += string
        } else if insideP {
            bareLineText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "span" where insideSpan:
            var text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            // Strip timing/onset markers from Apple Music TTML
            text = text.replacingOccurrences(of: "<>", with: "")
            text = text.replacingOccurrences(of: "</>", with: "")
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty, let begin = currentSpanBegin, let end = currentSpanEnd {
                currentWords.append(SyncedWord(
                    startTime: begin + lyricOffset,
                    endTime: end + lyricOffset,
                    text: text
                ))
            }
            insideSpan = false
            currentText = ""
            currentSpanBegin = nil
            currentSpanEnd = nil

        case "p" where insideP:
            guard let begin = currentPBegin else {
                insideP = false
                return
            }

            let adjustedBegin = begin + lyricOffset
            let adjustedEnd = currentPEnd.map { $0 + lyricOffset }

            if hadSpans && !currentWords.isEmpty {
                var lineText = currentWords.map(\.text).joined(separator: " ")
                lineText = Self.cleanLineText(lineText)
                // If the first word was a section annotation, remove it from words too
                if let first = currentWords.first {
                    let cleanedFirst = Self.cleanLineText(first.text)
                    if cleanedFirst != first.text {
                        if cleanedFirst.isEmpty {
                            currentWords.removeFirst()
                        } else {
                            currentWords[0] = SyncedWord(
                                startTime: first.startTime,
                                endTime: first.endTime,
                                text: cleanedFirst
                            )
                        }
                        lineText = currentWords.map(\.text).joined(separator: " ")
                    }
                }
                if !lineText.isEmpty && !currentWords.isEmpty {
                    lines.append(SyncedLyricLine(
                        time: adjustedBegin,
                        text: lineText,
                        endTime: adjustedEnd,
                        words: currentWords
                    ))
                }
            } else {
                var text = bareLineText.trimmingCharacters(in: .whitespacesAndNewlines)
                text = Self.cleanLineText(text)
                if !text.isEmpty {
                    lines.append(SyncedLyricLine(
                        time: adjustedBegin,
                        text: text,
                        endTime: adjustedEnd
                    ))
                }
            }

            insideP = false
            currentWords = []
            currentPBegin = nil
            currentPEnd = nil
            bareLineText = ""

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }

    // MARK: - Text Cleaning

    /// Strip section annotations (v1:, c:, b:, etc.) and timing markers from line text
    private static func cleanLineText(_ text: String) -> String {
        var cleaned = text

        // Strip verse/chorus/bridge annotations
        cleaned = cleaned.replacingOccurrences(
            of: #"^(?:v\d*|c\d*|b\d*|p\d*|i\d*|o\d*|outro|intro|verse|chorus|bridge|hook|pre-chorus|post-chorus):\s*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // Strip timing/onset markers
        cleaned = cleaned.replacingOccurrences(of: "<>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "</>", with: "")

        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Time Parsing

    /// Parses TTML time attributes. Supports:
    /// - Plain seconds: "18.893"
    /// - Milliseconds suffix: "18893ms"
    /// - Minute suffix: "1.5m"
    /// - Hour suffix: "0.5h"
    /// - Second suffix: "18.893s"
    /// - MM:SS.fff: "1:23.456"
    /// - HH:MM:SS.fff: "0:01:23.456"
    private func parseTimeAttribute(_ value: String?) -> Double? {
        guard var value, !value.isEmpty else { return nil }

        value = value.trimmingCharacters(in: .whitespaces)

        // Check for unit suffixes first
        if value.hasSuffix("ms") {
            let numStr = String(value.dropLast(2))
            return Double(numStr).map { $0 / 1000.0 }
        }
        if value.hasSuffix("h") {
            let numStr = String(value.dropLast(1))
            return Double(numStr).map { $0 * 3600.0 }
        }
        if value.hasSuffix("m") {
            let numStr = String(value.dropLast(1))
            return Double(numStr).map { $0 * 60.0 }
        }
        if value.hasSuffix("s") {
            let numStr = String(value.dropLast(1))
            return Double(numStr)
        }

        // Try plain seconds (most common in BetterLyrics)
        if !value.contains(":") {
            return Double(value)
        }

        // Try MM:SS.fff or HH:MM:SS.fff
        let parts = value.split(separator: ":")
        switch parts.count {
        case 2:
            guard let minutes = Double(parts[0]),
                  let seconds = Double(parts[1]) else { return nil }
            return minutes * 60 + seconds
        case 3:
            guard let hours = Double(parts[0]),
                  let minutes = Double(parts[1]),
                  let seconds = Double(parts[2]) else { return nil }
            return hours * 3600 + minutes * 60 + seconds
        default:
            return nil
        }
    }
}
