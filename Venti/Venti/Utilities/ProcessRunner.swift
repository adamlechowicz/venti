import Foundation
import os

/// Async wrapper around Process for running shell commands
enum ProcessRunner {
    private static let logger = Logger(subsystem: Constants.logSubsystem, category: "process")

    struct Result {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    /// Run a command and return its output
    static func run(_ command: String, arguments: [String] = [], sudo: Bool = false) async throws -> Result {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        var args: [String]
        if sudo {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            args = [command] + arguments
        } else {
            process.executableURL = URL(fileURLWithPath: command)
            args = arguments
        }
        process.arguments = args
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/bin:/usr/bin:/usr/local/bin:/usr/sbin:/opt/homebrew/bin"
        process.environment = env

        logger.debug("Running: \(sudo ? "sudo " : "")\(command) \(args.joined(separator: " "))")

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: Result(stdout: stdout, stderr: stderr, exitCode: proc.terminationStatus))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Run an SMC command with sudo
    static func runSMC(key: String, write value: String? = nil) async throws -> Result {
        var arguments = ["-k", key]
        if let value {
            arguments += ["-w", value]
        } else {
            arguments += ["-r"]
        }
        return try await run(Constants.smcBinaryPath, arguments: arguments, sudo: true)
    }
}
