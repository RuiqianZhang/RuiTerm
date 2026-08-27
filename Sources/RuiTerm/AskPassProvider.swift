import Foundation

/// Provides the SSH_ASKPASS helper script path.
/// The script is created on-demand in a temporary directory so it works
/// regardless of whether the app is run from Xcode Debug, SPM, or as a .app bundle.
enum AskPassProvider {
    
    /// Returns the path to a valid, executable askpass script.
    /// The script simply echoes the value of the `RUITERM_PASSWORD` environment variable.
    static var scriptPath: String {
        // 1. Try Bundle resources first (production .app bundle)
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("ruiterm-askpass.sh"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled.path
        }
        
        // 2. Create on-demand in a stable temp location
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RuiTerm")
        let scriptURL = tempDir.appendingPathComponent("ruiterm-askpass.sh")
        
        if FileManager.default.isExecutableFile(atPath: scriptURL.path) {
            return scriptURL.path
        }
        
        // Create the script
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let content = """
        #!/bin/sh
        printf '%s\\n' "$RUITERM_PASSWORD"
        """
        try? content.write(to: scriptURL, atomically: true, encoding: .utf8)
        
        // Make it executable (chmod +x)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )
        
        return scriptURL.path
    }
    
    /// Configure a Process's environment for password-based SSH authentication.
    static func configureEnvironment(_ environment: inout [String: String], password: String) {
        environment["SSH_ASKPASS"] = scriptPath
        environment["SSH_ASKPASS_REQUIRE"] = "force"
        environment["DISPLAY"] = "ruiterm"
        environment["RUITERM_PASSWORD"] = password
    }
}
