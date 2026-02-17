import Foundation
import os

enum SetupService {
    private static let logger = Logger.setup

    /// Updated visudo config with Tahoe + legacy SMC keys
    static let visudoConfig = """
    # Visudo settings for the Venti utility installed from https://github.com/adamlechowicz/venti
    Cmnd_Alias      BATTERYOFF = /usr/local/bin/smc -k CH0B -w 02, /usr/local/bin/smc -k CH0C -w 02, /usr/local/bin/smc -k CH0B -r, /usr/local/bin/smc -k CH0C -r, /usr/local/bin/smc -k CHTE -w 01000000, /usr/local/bin/smc -k CHTE -r
    Cmnd_Alias      BATTERYON = /usr/local/bin/smc -k CH0B -w 00, /usr/local/bin/smc -k CH0C -w 00, /usr/local/bin/smc -k CHTE -w 00000000
    Cmnd_Alias      DISCHARGEOFF = /usr/local/bin/smc -k CH0I -w 00, /usr/local/bin/smc -k CH0I -r, /usr/local/bin/smc -k CHIE -w 00, /usr/local/bin/smc -k CHIE -r, /usr/local/bin/smc -k CH0J -w 00, /usr/local/bin/smc -k CH0J -r
    Cmnd_Alias      DISCHARGEON = /usr/local/bin/smc -k CH0I -w 01, /usr/local/bin/smc -k CHIE -w 08, /usr/local/bin/smc -k CH0J -w 01
    ALL ALL = NOPASSWD: BATTERYOFF
    ALL ALL = NOPASSWD: BATTERYON
    ALL ALL = NOPASSWD: DISCHARGEOFF
    ALL ALL = NOPASSWD: DISCHARGEON
    """

    // MARK: - Checks

    static func isSMCInstalled() -> Bool {
        FileManager.default.fileExists(atPath: Constants.smcBinaryPath)
    }

    static func isVisudoConfigured() async -> Bool {
        // Verify visudo has Tahoe keys by attempting a passwordless sudo read of CHTE.
        // If this succeeds (exit 0), the new visudo is in place. If sudo asks for a
        // password (exit 1), visudo is missing or only has legacy keys.
        do {
            let result = try await ProcessRunner.runSMC(key: "CHTE")
            return result.exitCode == 0
        } catch {
            return false
        }
    }

    // MARK: - Installation

    /// Install smc binary by running the setup script with admin privileges
    static func installSMC() async throws {
        logger.info("Installing smc binary...")
        let script = "curl -s \(Constants.setupScriptURL) | zsh -s -- $(whoami)"
        _ = try await PrivilegedHelper.execute(script, prompt: "Venti needs to install its battery management tool (smc).")
        logger.info("smc binary installation complete")
    }

    /// Write the visudo configuration with admin privileges
    static func configureVisudo() async throws {
        logger.info("Configuring visudo...")

        // Write config to temp file, validate, then install
        let tempPath = NSTemporaryDirectory() + "venti_visudo.tmp"
        try visudoConfig.write(toFile: tempPath, atomically: true, encoding: .utf8)

        let commands = [
            "visudo -c -f \(tempPath)",
            "cp \(tempPath) \(Constants.visudoPath)",
            "chmod 440 \(Constants.visudoPath)",
            "rm -f \(tempPath)"
        ].joined(separator: " && ")

        _ = try await PrivilegedHelper.execute(commands, prompt: "Venti needs to configure passwordless battery management permissions.")
        logger.info("visudo configuration complete")
    }

    /// Run full first-time setup
    static func runFullSetup() async throws {
        if !isSMCInstalled() {
            try await installSMC()
        }

        let visudoOK = await isVisudoConfigured()
        if !visudoOK {
            try await configureVisudo()
        }
    }
}
