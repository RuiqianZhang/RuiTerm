import Foundation
import AppKit

@MainActor
class SFTPFileCoordinator: ObservableObject {
    static let shared = SFTPFileCoordinator()
    
    private let fileManager = FileManager.default
    private var watchers: [URL: DispatchSourceFileSystemObject] = [:]
    
    private init() {
        // Clean up old temporary files on startup
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("RuiTerm")
        try? fileManager.removeItem(at: tempDir)
    }
    
    func getLocalURL(hostID: UUID, remotePath: String) -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RuiTerm")
            .appendingPathComponent(hostID.uuidString)
            .appendingPathComponent(UUID().uuidString) // Unique folder per file
        
        try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let fileName = URL(fileURLWithPath: remotePath).lastPathComponent
        return tempDir.appendingPathComponent(fileName)
    }
    
    func watchFile(at localURL: URL, host: SSHHost, remotePath: String, password: String?) {
        guard watchers[localURL] == nil else { return }
        
        let fd = open(localURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .global(qos: .userInitiated)
        )
        
        source.setEventHandler { [weak self] in
            let events = source.data
            if events.contains(.write) {
                // File was written to! Time to upload.
                Task { @MainActor in
                    await self?.uploadFile(localURL: localURL, remotePath: remotePath, host: host, password: password)
                }
            }
            if events.contains(.delete) || events.contains(.rename) {
                // File deleted or moved, stop watching
                source.cancel()
                Task { @MainActor in
                    self?.watchers.removeValue(forKey: localURL)
                }
            }
        }
        
        source.setCancelHandler {
            close(fd)
        }
        
        watchers[localURL] = source
        source.resume()
    }
    
    private func uploadFile(localURL: URL, remotePath: String, host: SSHHost, password: String?) async {
        let taskID = SFTPTransferManager.shared.startTask(hostID: host.id, type: .upload, remotePath: remotePath, localURL: localURL)
        // Set a small fake progress so it shows as active immediately
        SFTPTransferManager.shared.updateProgress(id: taskID, progress: 0.1)
        
        // Use the existing runCopy logic from SFTPBrowserView to upload.
        // We will move runCopy to a shared location or call it via a new utility.
        let (status, error) = await runCopy(host: host, localURL: localURL, remotePath: remotePath, upload: true, password: password)
        
        if status == 0 {
            SFTPTransferManager.shared.updateProgress(id: taskID, progress: 1.0)
            SFTPTransferManager.shared.completeTask(id: taskID, success: true)
        } else {
            SFTPTransferManager.shared.completeTask(id: taskID, success: false, error: error)
        }
    }
    
    func downloadAndWatch(remotePath: String, localURL: URL, host: SSHHost, password: String?) async -> Bool {
        let (status, _) = await runCopy(host: host, localURL: localURL, remotePath: remotePath, upload: false, password: password)
        if status == 0 {
            // Once downloaded, start watching for modifications
            watchFile(at: localURL, host: host, remotePath: remotePath, password: password)
            return true
        }
        return false
    }
    
    // Extracted from SFTPBrowserView
    nonisolated private func runCopy(
        host: SSHHost,
        localURL: URL,
        remotePath: String,
        upload: Bool,
        password: String?
    ) async -> (status: Int32, output: String) {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
            var arguments = Self.scpArguments(for: host)
            let remote = "\(host.destination):\(remotePath)"
            arguments += upload ? [localURL.path, remote] : [remote, localURL.path]
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            if let password {
                AskPassProvider.configureEnvironment(&environment, password: password)
            }
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return (process.terminationStatus, String(decoding: data, as: UTF8.self))
            } catch {
                return (-1, error.localizedDescription)
            }
        }.value
    }
    
    nonisolated private static func scpArguments(for host: SSHHost) -> [String] {
        var arguments = [
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=/tmp/ruiterm-sftp-%C",
            "-o", "ControlPersist=3600",
            "-o", "ConnectTimeout=10",
            "-o", "NumberOfPasswordPrompts=1",
            "-P", String(host.port),
        ]
        if !host.identityFile.isEmpty {
            arguments += ["-i", NSString(string: host.identityFile).expandingTildeInPath]
        }
        if !host.proxyJump.isEmpty {
            arguments += ["-o", "ProxyJump=\(host.proxyJump)"]
        }
        return arguments
    }
}
