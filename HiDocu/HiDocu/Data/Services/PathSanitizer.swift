//
//  PathSanitizer.swift
//  HiDocu
//
//  Utilities for sanitizing file/folder names and resolving naming conflicts.
//

import Foundation

/// Utilities for creating safe file system paths and resolving naming conflicts.
enum PathSanitizer {

    // MARK: - Constants

    /// Maximum filename length in bytes for APFS/HFS+
    private static let maxFilenameBytes = 255

    /// Default name when sanitization results in empty string
    private static let defaultName = "Untitled"

    // MARK: - Sanitization

    /// Sanitizes a string for use as a file or directory name.
    ///
    /// - Parameter name: The original name to sanitize
    /// - Returns: A safe filename that adheres to macOS file system constraints
    ///
    /// Transformations applied:
    /// - Replaces path traversal components (`..`) with `_`
    /// - Replaces `/`, `:`, null bytes, and ASCII control characters with `-`
    /// - Trims leading/trailing whitespace and dots
    /// - Collapses consecutive spaces into single space
    /// - Truncates to 255 UTF-8 bytes without breaking characters
    /// - Returns "Untitled" if result is empty
    static func sanitize(_ name: String) -> String {
        var result = name

        // Replace path traversal
        result = result.replacingOccurrences(of: "..", with: "_")

        // Replace forbidden characters
        result = result.map { char -> Character in
            let scalar = char.unicodeScalars.first!
            let value = scalar.value

            // Replace / : \0 and control characters (0x00-0x1F)
            if char == "/" || char == ":" || value == 0 || (value >= 0x00 && value <= 0x1F) {
                return "-"
            }
            return char
        }.map(String.init).joined()

        // Collapse multiple consecutive spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        // Trim whitespace and dots
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "."))

        // Truncate to 255 UTF-8 bytes without breaking characters
        result = truncateToByteLimit(result, maxBytes: maxFilenameBytes)

        // Return default if empty
        return result.isEmpty ? defaultName : result
    }

    // MARK: - Conflict Resolution

    /// Resolves naming conflicts by appending numeric suffixes.
    ///
    /// - Parameters:
    ///   - baseName: The base filename without extension
    ///   - suffix: The file extension or suffix (e.g., ".document", ".md")
    ///   - existsCheck: Closure that returns true if a given path exists
    /// - Returns: A unique filename with suffix applied, potentially with numeric suffix
    ///
    /// Example:
    /// ```swift
    /// let unique = PathSanitizer.resolveConflict(
    ///     baseName: "Meeting",
    ///     suffix: ".document",
    ///     existsCheck: { FileManager.default.fileExists(atPath: $0) }
    /// )
    /// // Returns "Meeting.document" or "Meeting 2.document" or "Meeting 3.document" etc.
    /// ```
    static func resolveConflict(
        baseName: String,
        suffix: String,
        existsCheck: (String) -> Bool
    ) -> String {
        let candidate = baseName + suffix

        if !existsCheck(candidate) {
            return candidate
        }

        var counter = 2
        while true {
            let candidate = "\(baseName) \(counter)\(suffix)"
            if !existsCheck(candidate) {
                return candidate
            }
            counter += 1
        }
    }

    // MARK: - Private Helpers

    /// Truncates a string to a maximum number of UTF-8 bytes without breaking characters.
    ///
    /// - Parameters:
    ///   - string: The string to truncate
    ///   - maxBytes: Maximum number of UTF-8 bytes
    /// - Returns: Truncated string that fits within byte limit
    private static func truncateToByteLimit(_ string: String, maxBytes: Int) -> String {
        guard string.utf8.count > maxBytes else {
            return string
        }

        var result = string
        while result.utf8.count > maxBytes {
            result = String(result.dropLast())
        }
        return result
    }
}
