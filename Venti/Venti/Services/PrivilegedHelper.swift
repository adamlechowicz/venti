import Foundation
import os

enum PrivilegedHelper {
    private static let logger = Logger.setup

    enum PrivilegedError: LocalizedError {
        case userCanceled
        case executionFailed(String)

        var errorDescription: String? {
            switch self {
            case .userCanceled:
                return "Authentication canceled by user"
            case .executionFailed(let message):
                return "Privileged execution failed: \(message)"
            }
        }
    }

    /// Execute a command with admin privileges via NSAppleScript.
    /// Running in-process means macOS shows "Venti" with the app icon
    /// in the password dialog instead of "osascript" with a generic lock.
    /// - Parameters:
    ///   - command: The shell command to run as root
    ///   - prompt: Human-readable explanation shown in the password dialog
    static func execute(_ command: String, prompt: String = "Venti needs administrator privileges.") async throws -> String {
        let escapedCommand = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedPrompt = prompt.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let source = "do shell script \"\(escapedCommand)\" with administrator privileges with prompt \"\(escapedPrompt)\""

        logger.info("Executing privileged command via NSAppleScript")

        // NSAppleScript must run on the main thread
        return try await MainActor.run {
            var errorInfo: NSDictionary?
            let script = NSAppleScript(source: source)!
            let result = script.executeAndReturnError(&errorInfo)

            if let errorInfo {
                let errorMessage = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                if errorMessage.contains("User canceled") {
                    throw PrivilegedError.userCanceled
                }
                throw PrivilegedError.executionFailed(errorMessage)
            }

            return result.stringValue ?? ""
        }
    }
}
