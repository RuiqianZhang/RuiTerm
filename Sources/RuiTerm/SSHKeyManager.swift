import Foundation

enum SSHKeyManager {
    /// Ensures that an SSH key pair exists locally. If not, generates an ed25519 key.
    static func ensureLocalKeyExists() {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let sshDir = homeDir.appendingPathComponent(".ssh")
        
        // Create ~/.ssh if it doesn't exist
        if !fileManager.fileExists(atPath: sshDir.path) {
            try? fileManager.createDirectory(at: sshDir, withIntermediateDirectories: true, attributes: [
                .posixPermissions: NSNumber(value: 0o700)
            ])
        }
        
        let ed25519Key = sshDir.appendingPathComponent("id_ed25519.pub").path
        let rsaKey = sshDir.appendingPathComponent("id_rsa.pub").path
        
        if fileManager.fileExists(atPath: ed25519Key) || fileManager.fileExists(atPath: rsaKey) {
            // Key already exists
            return
        }
        
        // Generate a new ed25519 key
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = ["-t", "ed25519", "-f", sshDir.appendingPathComponent("id_ed25519").path, "-N", "", "-q"]
        try? process.run()
        process.waitUntilExit()
    }
    
    /// Installs the local public key to the remote host using ssh-copy-id.
    static func installKey(for host: SSHHost, password: String) async -> Bool {
        // If the user explicitly provided an identity file, they are managing keys manually.
        guard host.identityFile.isEmpty else { return false }
        
        // ssh-copy-id requires the askpass script to inject the password
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-copy-id")
            
            var arguments = [
                "-o", "ConnectTimeout=10",
                "-o", "NumberOfPasswordPrompts=1",
                "-o", "StrictHostKeyChecking=accept-new",
                "-p", String(host.port)
            ]
            
            if !host.proxyJump.isEmpty {
                arguments += ["-o", "ProxyJump=\(host.proxyJump)"]
            }
            
            arguments.append(host.destination)
            process.arguments = arguments
            
            var environment = ProcessInfo.processInfo.environment
            AskPassProvider.configureEnvironment(&environment, password: password)
            process.environment = environment
            
            // Suppress stdout/stderr to prevent logging garbage
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            process.terminationHandler = { p in
                continuation.resume(returning: p.terminationStatus == 0)
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}
