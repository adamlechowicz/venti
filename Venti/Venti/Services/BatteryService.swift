import Foundation
import os

enum BatteryService {
    private static let logger = Logger.battery

    struct Status: Sendable {
        let percentage: Int
        let timeRemaining: String
        let isCharging: Bool
    }

    /// Get battery status via pmset
    static func getStatus() async -> Status {
        do {
            let result = try await ProcessRunner.run("/usr/bin/pmset", arguments: ["-g", "batt"])
            return parseStatus(result.stdout)
        } catch {
            logger.error("Failed to get battery status: \(error.localizedDescription)")
            return Status(percentage: 0, timeRemaining: "unknown", isCharging: false)
        }
    }

    /// Get just the battery percentage
    static func getPercentage() async -> Int {
        let status = await getStatus()
        return status.percentage
    }

    private static func parseStatus(_ output: String) -> Status {
        let lines = output.components(separatedBy: "\n")

        // Second line contains battery info, e.g.:
        // " -InternalBattery-0 (id=...)	85%; charging; 1:23 remaining present: true"
        guard lines.count >= 2 else {
            return Status(percentage: 0, timeRemaining: "unknown", isCharging: false)
        }

        let batteryLine = lines[1]

        // Parse percentage
        var percentage = 0
        if let range = batteryLine.range(of: #"(\d+)%"#, options: .regularExpression) {
            let match = String(batteryLine[range]).replacingOccurrences(of: "%", with: "")
            percentage = Int(match) ?? 0
        }

        // Parse charging state
        let isCharging = batteryLine.contains("charging") && !batteryLine.contains("discharging")
            && !batteryLine.contains("not charging")

        // Parse time remaining
        var timeRemaining = "unknown"
        if let range = batteryLine.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) {
            timeRemaining = String(batteryLine[range])
        } else if batteryLine.contains("(no estimate)") {
            timeRemaining = "(no estimate)"
        }

        logger.debug("Battery: \(percentage)%, charging: \(isCharging), time: \(timeRemaining)")
        return Status(percentage: percentage, timeRemaining: timeRemaining, isCharging: isCharging)
    }
}
