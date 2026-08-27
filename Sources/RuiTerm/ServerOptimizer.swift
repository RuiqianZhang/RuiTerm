import Foundation
import AppKit

@MainActor
class ServerOptimizer: ObservableObject {
    static let shared = ServerOptimizer()
    
    private init() {}
    
    func optimize(host: SSHHost, password: String?, completion: @escaping (Bool, String?) -> Void) {
        Task.detached(priority: .userInitiated) {
            let (success, err) = await self.runOptimization(host: host, password: password)
            await MainActor.run {
                completion(success, err)
            }
        }
    }
    
    private func runOptimization(host: SSHHost, password: String?) async -> (Bool, String?) {
        // 1. Ensure Local RSA Key
        let sshDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh")
        let privKey = sshDir.appendingPathComponent("id_rsa")
        let pubKey = sshDir.appendingPathComponent("id_rsa.pub")
        
        if !FileManager.default.fileExists(atPath: privKey.path) {
            let keygenProcess = Process()
            keygenProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
            keygenProcess.arguments = ["-t", "rsa", "-b", "4096", "-f", privKey.path, "-N", ""]
            do {
                try keygenProcess.run()
                keygenProcess.waitUntilExit()
                if keygenProcess.terminationStatus != 0 {
                    return (false, "Failed to generate local RSA key")
                }
            } catch {
                return (false, error.localizedDescription)
            }
        }
        
        guard let pubKeyContent = try? String(contentsOf: pubKey, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) else {
            return (false, "Could not read public key")
        }
        
        // 2. Prepare the optimization script to run on the remote server
        let script = """
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        echo "\(pubKeyContent)" >> ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
        
        # OSC 7 Injection
        BASH_MARKER="# RuiTerm OSC 7"
        if ! grep -q "$BASH_MARKER" ~/.bashrc 2>/dev/null; then
            echo "" >> ~/.bashrc
            echo "$BASH_MARKER" >> ~/.bashrc
            echo "if [ -n \\"\\$BASH_VERSION\\" ]; then PROMPT_COMMAND='printf \\"\\\\033]7;file://%s%s\\\\033\\\\\\\\\\" \\"\\$HOSTNAME\\" \\"\\$PWD\\"'; fi" >> ~/.bashrc
        fi
        
        ZSH_MARKER="# RuiTerm OSC 7"
        if ! grep -q "$ZSH_MARKER" ~/.zshrc 2>/dev/null; then
            echo "" >> ~/.zshrc
            echo "$ZSH_MARKER" >> ~/.zshrc
            echo "precmd() { printf \\"\\\\033]7;file://%s%s\\\\033\\\\\\\\\\" \\"\\$HOST\\" \\"\\$PWD\\" }" >> ~/.zshrc
        fi
        """
        
        // 3. Execute the script over SSH
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        var arguments = [
            "-o", "ConnectTimeout=10",
            "-o", "NumberOfPasswordPrompts=1",
            "-p", String(host.port),
        ]
        if !host.proxyJump.isEmpty {
            arguments += ["-o", "ProxyJump=\(host.proxyJump)"]
        }
        arguments += [host.destination, script]
        process.arguments = arguments
        
        var environment = ProcessInfo.processInfo.environment
        if let password {
            AskPassProvider.configureEnvironment(&environment, password: password)
        }
        process.environment = environment
        
        let pipe = Pipe()
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return (true, nil)
            } else {
                let errData = pipe.fileHandleForReading.readDataToEndOfFile()
                return (false, String(decoding: errData, as: UTF8.self))
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
