import Foundation
import os

enum SMCService {
    private static let logger = Logger.smc

    // MARK: - Capability Detection

    /// Detect which SMC keys are supported on this hardware
    static func detectCapabilities() async -> SMCCapabilities {
        async let chte = isKeySupported("CHTE")
        async let ch0b = isKeySupported("CH0B")
        async let chie = isKeySupported("CHIE")
        async let ch0j = isKeySupported("CH0J")
        async let ch0i = isKeySupported("CH0I")

        let caps = await SMCCapabilities(
            useTahoeCharging: chte,
            useLegacyCharging: ch0b,
            useCHIE: chie,
            useCH0J: ch0j,
            useCH0I: ch0i
        )

        logger.info("SMC capabilities: Tahoe charging=\(caps.useTahoeCharging), Legacy charging=\(caps.useLegacyCharging), CHIE=\(caps.useCHIE), CH0J=\(caps.useCH0J), CH0I=\(caps.useCH0I)")
        return caps
    }

    private static func isKeySupported(_ key: String) async -> Bool {
        do {
            let result = try await ProcessRunner.runSMC(key: key)
            let output = result.stdout + result.stderr
            if result.exitCode != 0 {
                // sudo password prompt or other failure — key not available (may need visudo update)
                logger.debug("Key \(key) not available (exit \(result.exitCode))")
                return false
            }
            let supported = !output.lowercased().contains("no data")
            logger.info("Key \(key): supported=\(supported), output='\(result.stdout)'")
            return supported
        } catch {
            logger.debug("Key \(key) check failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Charging Control

    static func enableCharging(capabilities: SMCCapabilities) async {
        logger.info("Enabling battery charging")
        do {
            if capabilities.useTahoeCharging {
                _ = try await ProcessRunner.runSMC(key: "CHTE", write: "00000000")
            } else if capabilities.useLegacyCharging {
                _ = try await ProcessRunner.runSMC(key: "CH0B", write: "00")
                _ = try await ProcessRunner.runSMC(key: "CH0C", write: "00")
            }
            await disableDischarging(capabilities: capabilities)
        } catch {
            logger.error("Failed to enable charging: \(error.localizedDescription)")
        }
    }

    static func disableCharging(capabilities: SMCCapabilities) async {
        logger.info("Disabling battery charging")
        do {
            if capabilities.useTahoeCharging {
                _ = try await ProcessRunner.runSMC(key: "CHTE", write: "01000000")
            } else if capabilities.useLegacyCharging {
                _ = try await ProcessRunner.runSMC(key: "CH0B", write: "02")
                _ = try await ProcessRunner.runSMC(key: "CH0C", write: "02")
            }
        } catch {
            logger.error("Failed to disable charging: \(error.localizedDescription)")
        }
    }

    // MARK: - Discharging Control

    static func enableDischarging(capabilities: SMCCapabilities) async {
        logger.info("Enabling battery discharging")
        do {
            if capabilities.useCHIE {
                _ = try await ProcessRunner.runSMC(key: "CHIE", write: "08")
            } else if capabilities.useCH0J {
                _ = try await ProcessRunner.runSMC(key: "CH0J", write: "01")
            } else if capabilities.useCH0I {
                _ = try await ProcessRunner.runSMC(key: "CH0I", write: "01")
            }
        } catch {
            logger.error("Failed to enable discharging: \(error.localizedDescription)")
        }
    }

    static func disableDischarging(capabilities: SMCCapabilities) async {
        logger.info("Disabling battery discharging")
        do {
            if capabilities.useCHIE {
                _ = try await ProcessRunner.runSMC(key: "CHIE", write: "00")
            } else if capabilities.useCH0J {
                _ = try await ProcessRunner.runSMC(key: "CH0J", write: "00")
            } else if capabilities.useCH0I {
                _ = try await ProcessRunner.runSMC(key: "CH0I", write: "00")
            }
        } catch {
            logger.error("Failed to disable discharging: \(error.localizedDescription)")
        }
    }

    // MARK: - Status

    static func isChargingEnabled(capabilities: SMCCapabilities) async -> Bool {
        do {
            if capabilities.useTahoeCharging {
                let result = try await ProcessRunner.runSMC(key: "CHTE")
                // CHTE returns "00000000" when charging enabled, "01000000" when disabled
                return result.stdout.contains("00000000") || (!result.stdout.contains("01000000") && result.stdout.contains("00"))
            } else if capabilities.useLegacyCharging {
                let result = try await ProcessRunner.runSMC(key: "CH0B")
                // Parse hex value from output: "  CH0B  [ui8 ]  (bytes 00)"
                let output = result.stdout
                return output.contains("bytes 00") || output.hasSuffix("00)")
            }
        } catch {
            logger.error("Failed to read charging status: \(error.localizedDescription)")
        }
        return true // assume charging enabled if we can't read
    }
}
