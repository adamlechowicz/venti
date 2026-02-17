import Foundation
import os

@MainActor
enum ThresholdService {
    private static let logger = Logger.carbon
    private static var thresholds: [String: Int] = [:]

    static func load() {
        guard let url = Bundle.main.url(forResource: "Thresholds", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data) else {
            logger.error("Failed to load Thresholds.json")
            return
        }
        thresholds = dict
        logger.info("Loaded \(dict.count) carbon intensity thresholds")
    }

    /// Look up threshold for a region code. Strips hyphens to match key format.
    static func threshold(for region: String) -> Int {
        let key = region.replacingOccurrences(of: "-", with: "")
        if let value = thresholds[key] {
            return value
        }
        logger.debug("No threshold for region '\(region)', using default \(Constants.defaultThreshold)")
        return Constants.defaultThreshold
    }
}
