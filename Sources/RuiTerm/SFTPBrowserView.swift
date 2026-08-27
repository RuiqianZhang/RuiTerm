import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct BrowserEntry: Identifiable, Hashable {
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modificationDate: Date?

    var id: String { name }
}

private enum ClipboardOperation {
    case copy
    case cut
}

@MainActor
final class SFTPCommandCenter: NSObject, ObservableObject {
    static let shared = SFTPCommandCenter()

    @Published private var publishedKeyResponderState = false
    private var hasFocusedPanel = false
    private var focusedPanelID: UUID?
    private weak var focusedWindow: NSWindow?
    private var copyAction: (() -> Void)?
    private var cutAction: (() -> Void)?
    private var pasteAction: (() -> Void)?
    private var selectAllAction: (() -> Void)?

    var isKeyResponder: Bool {
        computeKeyResponder()
    }

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowKeyStateChanged(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowKeyStateChanged(_:)),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )
    }

    func focus(
        id: UUID,
        copy: @escaping () -> Void,
        cut: @escaping () -> Void,
        paste: @escaping () -> Void,
        selectAll: @escaping () -> Void
    ) {
        focusedPanelID = id
        copyAction = copy
        cutAction = cut
        pasteAction = paste
        selectAllAction = selectAll
        focusedWindow = NSApp.keyWindow
        hasFocusedPanel = true
        refreshKeyResponder()
    }

    func blur() {
        focusedPanelID = nil
        focusedWindow = nil
        copyAction = nil
        cutAction = nil
        pasteAction = nil
        selectAllAction = nil
        hasFocusedPanel = false
        publishedKeyResponderState = false
    }

    func blur(id: UUID) {
        guard focusedPanelID == id else { return }
        blur()
    }

    func performCopy() {
        guard isKeyResponder else { return }
        copyAction?()
    }

    func performCut() {
        guard isKeyResponder else { return }
        cutAction?()
    }

    func performPaste() {
        guard isKeyResponder else { return }
        pasteAction?()
    }

    func performSelectAll() {
        guard isKeyResponder else { return }
        selectAllAction?()
    }

    @objc private func windowKeyStateChanged(_ notification: Notification) {
        refreshKeyResponder()
    }

    private func refreshKeyResponder() {
        let newValue = computeKeyResponder()
        if publishedKeyResponderState != newValue {
            publishedKeyResponderState = newValue
        }
    }

    private func computeKeyResponder() -> Bool {
        hasFocusedPanel
            && focusedWindow?.isKeyWindow == true
            && NSApp.keyWindow === focusedWindow
    }
}

private enum FileLocation {
    case local(URL)
    case remote(String)
}

private struct ClipboardItem: Identifiable {
    let id = UUID()
    let location: FileLocation
    let operation: ClipboardOperation
    let name: String
    let isDirectory: Bool
}

private enum PasteConflictPolicy {
    case replace
    case keepBoth
}

private enum SFTPDragPayload {
    static let prefix = "ruiterm-sftp:"

    static func local(_ path: String) -> String {
        "\(prefix)local:\(path)"
    }

    static func remote(_ path: String) -> String {
        "\(prefix)remote:\(path)"
    }

    static func parse(_ value: String) -> FileLocation? {
        if value.hasPrefix("\(prefix)local:") {
            return .local(URL(fileURLWithPath: String(value.dropFirst("\(prefix)local:".count))))
        }
        if value.hasPrefix("\(prefix)remote:") {
            return .remote(String(value.dropFirst("\(prefix)remote:".count)))
        }
        return nil
    }
}

private struct PendingPasteRequest {
    let items: [ClipboardItem]
    let toLocal: Bool
    let conflictNames: [String]
}

@MainActor
private final class RemoteDirectoryBrowser: ObservableObject {
    @Published private(set) var entries: [BrowserEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isTransferring = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var loadedPath: String?

    let session: SSHSession
    var host: SSHHost { session.host }

    /// Token for cancelling stale loads. Each load increments this.
    /// After every await point, the load checks whether its token is still current.
    private var loadToken: UInt64 = 0

    init(session: SSHSession) {
        self.session = session
    }

    @discardableResult
    func load(path: String, manualPassword: String? = nil) async -> Bool {
        guard !host.isLocal else {
            entries = []
            errorMessage = "SFTP is only available for SSH hosts."
            return false
        }

        // Bump token – this invalidates any in-flight load.
        loadToken &+= 1
        let token = loadToken

        isLoading = true
        errorMessage = nil

        let initialPassword: String?
        if let manualPassword, !manualPassword.isEmpty {
            initialPassword = manualPassword
            session.setCachedPassword(manualPassword)
        } else if let cachedPassword = session.cachedPassword {
            initialPassword = cachedPassword
        } else if host.savesPassword {
            initialPassword = session.getOrLoadPassword()
        } else {
            initialPassword = nil
        }

        var result = await Self.runListing(host: host, path: path, password: initialPassword)

        // If a newer load started while we awaited, abandon silently.
        if token != loadToken {
            // Don't touch isLoading/entries/error – the newer load owns them.
            return false
        }

        // 2. Retry with password if permission denied
        if initialPassword == nil,
           result.status != 0,
           (result.message.contains("Permission denied") || result.message.contains("password")) {
            let password: String?
            if let manualPassword, !manualPassword.isEmpty {
                password = manualPassword
                session.setCachedPassword(manualPassword)
            } else {
                password = session.getOrLoadPassword()
            }
            if password != nil {
                if token != loadToken {
                    return false
                }
                result = await Self.runListing(host: host, path: path, password: password)
                if token != loadToken {
                    return false
                }
            }
        }

        // Only the latest load updates state.
        isLoading = false
        if result.status == 0 {
            entries = Self.parse(result.data)
            loadedPath = path
            errorMessage = nil
            return true
        } else {
            entries = []
            loadedPath = nil
            errorMessage = result.message.trimmingCharacters(in: .whitespacesAndNewlines)
            NSLog("[SFTP] load FAIL: path=%@ msg=%@", path, errorMessage ?? "nil")
            return false
        }
    }

    func upload(localURL: URL, to remotePath: String, manualPassword: String? = nil, completion: @escaping () -> Void) {
        upload(
            localURL: localURL,
            toRemotePath: Self.appending(localURL.lastPathComponent, to: remotePath),
            manualPassword: manualPassword,
            completion: completion
        )
    }

    func upload(localURL: URL, toRemotePath: String, manualPassword: String? = nil, completion: @escaping () -> Void) {
        transfer(
            localURL: localURL,
            remotePath: toRemotePath,
            upload: true,
            manualPassword: manualPassword,
            completion: completion
        )
    }

    func download(entry: BrowserEntry, from remotePath: String, to localURL: URL, manualPassword: String? = nil, completion: @escaping () -> Void) {
        download(
            remotePath: Self.appending(entry.name, to: remotePath),
            toLocalURL: localURL.appending(path: entry.name),
            manualPassword: manualPassword,
            completion: completion
        )
    }

    func download(remotePath: String, toLocalURL: URL, manualPassword: String? = nil, completion: @escaping () -> Void) {
        transfer(
            localURL: toLocalURL,
            remotePath: remotePath,
            upload: false,
            manualPassword: manualPassword,
            completion: completion
        )
    }

    private func transfer(
        localURL: URL,
        remotePath: String,
        upload: Bool,
        manualPassword: String? = nil,
        completion: @escaping () -> Void
    ) {
        isTransferring = true
        errorMessage = nil
        let taskID = SFTPTransferManager.shared.startTask(
            hostID: host.id,
            type: upload ? .upload : .download,
            remotePath: remotePath,
            localURL: localURL
        )
        SFTPTransferManager.shared.updateProgress(id: taskID, progress: 0.01)
        Task {
            // 1. Optimistically try without password (ControlMaster active or RSA key active)
            var result = await Self.runCopy(
                host: host,
                localURL: localURL,
                remotePath: remotePath,
                upload: upload,
                password: nil,
                taskID: taskID
            )

            // 2. Retry with password if permission denied
            if result.status != 0 && (result.output.contains("Permission denied") || result.output.contains("password")) {
                let password: String?
                if let manualPassword, !manualPassword.isEmpty {
                    password = manualPassword
                    session.setCachedPassword(manualPassword)
                } else {
                    password = session.getOrLoadPassword()
                }
                if password != nil {
                    result = await Self.runCopy(
                        host: host,
                        localURL: localURL,
                        remotePath: remotePath,
                        upload: upload,
                        password: password,
                        taskID: taskID
                    )
                }
            }

            isTransferring = false
            if result.status == 0 {
                SFTPTransferManager.shared.updateProgress(id: taskID, progress: 1)
                SFTPTransferManager.shared.completeTask(id: taskID, success: true)
                completion()
            } else {
                errorMessage = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                SFTPTransferManager.shared.completeTask(id: taskID, success: false, error: errorMessage)
            }
        }
    }

    private static func runListing(
        host: SSHHost,
        path: String,
        password: String?
    ) async -> (status: Int32, data: Data, message: String) {
        await Task.detached(priority: .userInitiated) {
            let command = listingCommand(path: path)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = sshArguments(for: host) + [host.destination, command]
            var environment = ProcessInfo.processInfo.environment
            if let password {
                AskPassProvider.configureEnvironment(&environment, password: password)
            }
            process.environment = environment
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            do {
                try process.run()

                // Read stdout and stderr CONCURRENTLY to avoid pipe-buffer deadlock.
                let outReader = outPipe.fileHandleForReading
                let errReader = errPipe.fileHandleForReading
                async let outRead = outReader.readDataToEndOfFile()
                async let errRead = errReader.readDataToEndOfFile()

                // Timeout: kill the process if still running after 30s
                let timeoutTask = Task.detached {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    if process.isRunning {
                        NSLog("[SFTP] runListing TIMEOUT: killing process for path=%@", path)
                        process.terminate()
                    }
                }

                // Await both reads to complete before waiting for process exit.
                // (Reads finish when pipe closes, which happens when process exits.)
                let outBytes = await outRead
                let errBytes = await errRead
                process.waitUntilExit()
                timeoutTask.cancel()

                let errorOutput = String(decoding: errBytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

                if process.terminationStatus == 0 {
                    if outBytes.isEmpty && !errorOutput.isEmpty {
                        NSLog("[SFTP] runListing: empty stdout, stderr=%@", errorOutput)
                        return (1, Data(), errorOutput)
                    }
                    return (0, outBytes, "")
                } else {
                    let output = String(decoding: outBytes, as: UTF8.self)
                    let message = errorOutput.isEmpty ? output : errorOutput
                    NSLog("[SFTP] runListing FAIL: status=%d msg=%@", process.terminationStatus, String(message.prefix(300)))
                    return (process.terminationStatus, outBytes, message)
                }
            } catch {
                NSLog("[SFTP] runListing error: %@", error.localizedDescription)
                return (-1, Data(), error.localizedDescription)
            }
        }.value
    }

    func runCommand(command: String, manualPassword: String? = nil, completion: @escaping (Bool, String) -> Void) {
        isTransferring = true
        errorMessage = nil
        Task {
            // 1. Optimistically try without password (ControlMaster active or RSA key active)
            var result = await Self.executeCommand(host: host, command: command, password: nil)

            // 2. Retry with password if permission denied
            if result.status != 0 && (result.output.contains("Permission denied") || result.output.contains("password")) {
                let password: String?
                if let manualPassword, !manualPassword.isEmpty {
                    password = manualPassword
                    session.setCachedPassword(manualPassword)
                } else {
                    password = session.getOrLoadPassword()
                }
                if password != nil {
                    result = await Self.executeCommand(host: host, command: command, password: password)
                }
            }

            isTransferring = false
            if result.status == 0 {
                completion(true, result.output)
            } else {
                let err = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                errorMessage = err
                completion(false, err)
            }
        }
    }

    private static func executeCommand(host: SSHHost, command: String, password: String?) async -> (status: Int32, output: String) {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = sshArguments(for: host) + [host.destination, command]
            var environment = ProcessInfo.processInfo.environment
            if let password {
                AskPassProvider.configureEnvironment(&environment, password: password)
            }
            process.environment = environment
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            do {
                try process.run()
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let output = String(decoding: outData, as: UTF8.self)
                let errorOutput = String(decoding: errData, as: UTF8.self)

                if process.terminationStatus == 0 {
                    return (0, output)
                } else {
                    return (process.terminationStatus, errorOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? output : errorOutput)
                }
            } catch {
                return (-1, error.localizedDescription)
            }
        }.value
    }

    private static func runCopy(
        host: SSHHost,
        localURL: URL,
        remotePath: String,
        upload: Bool,
        password: String?,
        taskID: UUID?
    ) async -> (status: Int32, output: String) {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
            var arguments = scpArguments(for: host)
            let remote = "\(host.destination):\(remotePath)"
            arguments += upload ? [localURL.path, remote] : [remote, localURL.path]
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            if let password {
                AskPassProvider.configureEnvironment(&environment, password: password)
            }
            process.environment = environment
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            do {
                try process.run()
                let totalBytes = upload
                    ? localByteCount(at: localURL)
                    : remoteByteCount(host: host, path: remotePath, password: password)
                let monitor = Task.detached {
                    guard let taskID, totalBytes > 0 else { return }
                    while process.isRunning {
                        let copiedBytes = upload
                            ? remoteByteCount(host: host, path: remotePath, password: password)
                            : localByteCount(at: localURL)
                        if copiedBytes > 0 {
                            await SFTPTransferManager.shared.updateProgress(
                                id: taskID,
                                progress: min(0.99, Double(copiedBytes) / Double(totalBytes))
                            )
                        }
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }
                }
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                monitor.cancel()

                let output = String(decoding: outData, as: UTF8.self)
                let errorOutput = String(decoding: errData, as: UTF8.self)

                if process.terminationStatus == 0 {
                    return (0, output)
                } else {
                    return (process.terminationStatus, errorOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? output : errorOutput)
                }
            } catch {
                return (-1, error.localizedDescription)
            }
        }.value
    }

    nonisolated private static func localByteCount(at url: URL) -> Int64 {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            return (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        }
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: []) else {
            return 0
        }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            if let size = try? child.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    nonisolated private static func remoteByteCount(host: SSHHost, path: String, password: String?) -> Int64 {
        let command = """
        p=\(shellQuote(path)); if [ -d "$p" ]; then du -sk "$p" 2>/dev/null | awk '{print $1 * 1024}'; elif [ -e "$p" ]; then stat -c '%s' "$p" 2>/dev/null; else echo 0; fi
        """
        let result = runSynchronousCommand(host: host, command: command, password: password)
        return Int64(result.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    nonisolated private static func runSynchronousCommand(host: SSHHost, command: String, password: String?) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = sshArguments(for: host) + [host.destination, command]
        var environment = ProcessInfo.processInfo.environment
        if let password {
            AskPassProvider.configureEnvironment(&environment, password: password)
        }
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        } catch {
            return ""
        }
    }

    nonisolated private static func sshArguments(for host: SSHHost) -> [String] {
        var arguments = [
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=/tmp/ruiterm-sftp-%C",
            "-o", "ControlPersist=3600",
            "-o", "ConnectTimeout=10",
            "-o", "NumberOfPasswordPrompts=1",
            "-p", String(host.port),
        ]
        if !host.identityFile.isEmpty {
            arguments += ["-i", NSString(string: host.identityFile).expandingTildeInPath]
        }
        if !host.proxyJump.isEmpty {
            arguments += ["-J", host.proxyJump]
        }
        return arguments
    }

    nonisolated private static func scpArguments(for host: SSHHost) -> [String] {
        var arguments = [
            "-r",
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

    nonisolated private static func listingCommand(path: String) -> String {
        let directory: String
        if path == "~" {
            directory = "\"$HOME\""
        } else if path.hasPrefix("~/") {
            directory = "\"$HOME\"/\(shellQuote(String(path.dropFirst(2))))"
        } else {
            directory = shellQuote(path)
        }

        // Include modification time as Unix epoch seconds. Prefer GNU find
        // because it avoids launching stat for every entry; retain GNU/BSD stat
        // fallbacks for hosts whose find does not support -printf.
        return "cd \(directory) >/dev/null 2>&1 || { echo 'No such file or directory' >&2; exit 1; }; if LC_ALL=C find . -maxdepth 0 -printf '' >/dev/null 2>&1; then LC_ALL=C find . -maxdepth 1 -mindepth 1 -printf '%y\\t%s\\t%T@\\t%p\\n'; elif stat -c '' . >/dev/null 2>&1; then LC_ALL=C find . -maxdepth 1 -mindepth 1 -exec stat -c '%F\t%s\t%Y\t%n' {} +; else LC_ALL=C find . -maxdepth 1 -mindepth 1 -exec stat -f '%HT\t%z\t%m\t%N' {} +; fi"
    }

    nonisolated fileprivate static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated private static func parse(_ output: Data) -> [BrowserEntry] {
        // Parse output from either find -printf or find -exec stat.
        // Each line: <fileType>\t<size>\t<modifiedEpoch>\t<./name>
        guard let text = String(data: output, encoding: .utf8) else {
            NSLog("[SFTP] parse: failed to decode output as UTF-8")
            return []
        }

        var entries: [BrowserEntry] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count >= 4 else {
                continue
            }
            let fileType = String(parts[0])
            let sizeStr = String(parts[1])
            let modifiedStr = String(parts[2])
            var name = String(parts[3])

            // Strip leading "./" prefix from find output
            if name.hasPrefix("./") { name = String(name.dropFirst(2)) }
            guard !name.isEmpty else { continue }

            let normalizedType = fileType.lowercased()
            let isDir = normalizedType == "d" || normalizedType.hasPrefix("directory")
            let sizeVal = Int64(sizeStr.trimmingCharacters(in: .whitespaces)) ?? 0
            let modificationDate = Double(modifiedStr.trimmingCharacters(in: .whitespaces))
                .map(Date.init(timeIntervalSince1970:))
            entries.append(
                BrowserEntry(
                    name: name,
                    isDirectory: isDir,
                    size: isDir ? 0 : sizeVal,
                    modificationDate: modificationDate
                )
            )
        }

        return entries.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    nonisolated private static func appending(_ component: String, to path: String) -> String {
        if path == "/" { return "/\(component)" }
        return "\(path)/\(component)"
    }
}

struct SFTPBrowserView: View {
    @ObservedObject var session: SSHSession
    let isVisible: Bool
    let onClose: () -> Void

    @StateObject private var remote: RemoteDirectoryBrowser
    @State private var localURL = FileManager.default.homeDirectoryForCurrentUser
    @State private var localEntries: [BrowserEntry] = []
    @State private var localErrorMessage: String?
    @State private var remotePath: String

    // 剪贴板
    @State private var clipboard: [ClipboardItem] = []
    @State private var pendingPaste: PendingPasteRequest?

    // 状态进度提示
    @State private var statusMessage: String?
    @State private var statusIsError: Bool = false

    // 重命名
    @State private var itemToRename: BrowserEntry?
    @State private var newName: String = ""
    @State private var isRenamingLocal: Bool = true

    // 权限与属主
    @State private var itemToChmod: BrowserEntry?
    @State private var newPermissions: String = ""
    @State private var itemToChown: BrowserEntry?
    @State private var newOwner: String = ""

    // 新建文件/文件夹
    @State private var isCreatingFolder: Bool = false
    @State private var isCreatingFile: Bool = false
    @State private var newFileName: String = ""
    @State private var isCreatingLocal: Bool = true

    // 详细信息
    @State private var itemToShowInfo: BrowserEntry?
    @State private var itemInfoText: String = ""

    // 选中状态
    @State private var localSelection: Set<String> = []
    @State private var remoteSelection: Set<String> = []
    @State private var localCommandID = UUID()
    @State private var remoteCommandID = UUID()

    // 导航任务取消
    @State private var navigationTask: Task<Void, Never>?
    @State private var localLoadToken: UInt64 = 0

    // 密码提示
    @State private var isPromptingPassword: Bool = false
    @State private var manualPassword: String = ""

    init(session: SSHSession, isVisible: Bool, onClose: @escaping () -> Void) {
        self.session = session
        self.isVisible = isVisible
        self.onClose = onClose
        _remote = StateObject(wrappedValue: RemoteDirectoryBrowser(session: session))
        _remotePath = State(initialValue: session.currentDirectory)
    }

    var body: some View {
        mainContent
            .onAppear {
                if isVisible {
                    loadLocal()
                    if remote.loadedPath != remotePath && !remote.isLoading {
                        loadRemote()
                    }
                }
            }
            .onChange(of: isVisible) { _, visible in
                if visible {
                    if localEntries.isEmpty { loadLocal() }
                    if remote.loadedPath != remotePath && !remote.isLoading { loadRemote() }
                } else {
                    SFTPCommandCenter.shared.blur()
                }
            }
            .onChange(of: session.currentDirectory) { _, newPath in
                let previousPath = remotePath
                guard newPath != previousPath else {
                    NSLog("[SFTP] onChange currentDirectory: same path, skipping")
                    return
                }
                NSLog("[SFTP] onChange currentDirectory: previous=%@ new=%@", previousPath, newPath)
                remotePath = newPath
                guard isVisible else { return }
                navigationTask?.cancel()
                navigationTask = Task {
                    let success = await remote.load(path: newPath, manualPassword: manualPassword)
                    if Task.isCancelled { return }
                    if !success, let msg = remote.errorMessage, msg.contains("No such file or directory") {
                        NSLog("[SFTP] onChange load failed, reverting to: %@", previousPath)
                        remotePath = previousPath
                    }
                }
            }
            .onChange(of: remote.errorMessage) { _, msg in
                if let msg, msg.contains("Permission denied") {
                    isPromptingPassword = true
                }
            }
            .onDisappear {
                SFTPCommandCenter.shared.blur()
            }
            .modifier(SFTPAlerts(
                isPromptingPassword: $isPromptingPassword,
                manualPassword: $manualPassword,
                itemToRename: $itemToRename,
                newName: $newName,
                isCreatingFolder: $isCreatingFolder,
                isCreatingFile: $isCreatingFile,
                newFileName: $newFileName,
                itemToChmod: $itemToChmod,
                newPermissions: $newPermissions,
                itemToChown: $itemToChown,
                newOwner: $newOwner,
                itemToShowInfo: $itemToShowInfo,
                itemInfoText: itemInfoText,
                session: session,
                loadRemote: loadRemote,
                performRename: performRename,
                performCreate: performCreate,
                performChmod: performChmod,
                performChown: performChown
            ))
            .confirmationDialog(
                pasteConflictTitle,
                isPresented: Binding(
                    get: { pendingPaste != nil },
                    set: { if !$0 { pendingPaste = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("替换") {
                    resolvePendingPaste(with: .replace)
                }
                Button("保留两者") {
                    resolvePendingPaste(with: .keepBoth)
                }
                Button("取消", role: .cancel) {
                    pendingPaste = nil
                }
            } message: {
                Text("选择如何处理现有项目。此选择将应用于本次粘贴的所有冲突。")
            }
            .overlay(alignment: .bottomTrailing) {
                if let msg = statusMessage {
                    Text(msg)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(statusIsError ? Color.red.opacity(0.8) : Color.black.opacity(0.7))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .padding(12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            HStack {
                Label("SFTP", systemImage: "externaldrive.connected.to.line.below")
                    .font(.subheadline.weight(.semibold))
                Text(session.host.destination)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if remote.isLoading || remote.isTransferring {
                    ProgressView().controlSize(.small)
                }
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.glass)
                .help(Text("关闭 SFTP"))
            }
            .padding(.horizontal, 12)
            .frame(height: 36)

            Divider()

            HSplitView {
                SFTPFilePanelView(
                    title: "Local",
                    path: Binding(
                        get: { localURL.path(percentEncoded: false) },
                        set: { navigateLocal(to: $0) }
                    ),
                    entries: localEntries,
                    selection: $localSelection,
                    error: localErrorMessage,
                    goUp: localGoUp,
                    refresh: { loadLocal() },
                    open: openLocal,
                    navigateTo: { path in
                        NSLog("[SFTP] local navigateTo: %@", path)
                        navigateLocal(to: path)
                    },
                    transferIcon: "arrow.right",
                    transferHelp: "Upload",
                    transfer: upload,
                    dragPayload: { entry in SFTPDragPayload.local(localURL.appending(path: entry.name).path) },
                    handleDrop: { providers in
                        handleDrop(providers, toLocal: true)
                    },
                    contextMenu: { entry in localContextMenu(for: entry) },
                    bgContextMenu: { localBgContextMenu() },
                    showStatus: { showStatus($0) },
                    activateCommands: activateLocalCommands,
                    deactivateCommands: { SFTPCommandCenter.shared.blur(id: localCommandID) }
                )
                SFTPFilePanelView(
                    title: "Remote",
                    path: $remotePath,
                    entries: remote.entries,
                    selection: $remoteSelection,
                    error: remote.errorMessage,
                    goUp: remoteGoUp,
                    refresh: loadRemote,
                    open: openRemote,
                    navigateTo: { path in
                        NSLog("[SFTP] remote navigateTo: %@", path)
                        remotePath = path
                        Task { _ = await remote.load(path: path, manualPassword: manualPassword.isEmpty ? nil : manualPassword) }
                    },
                    transferIcon: "arrow.left",
                    transferHelp: "Download",
                    transfer: download,
                    primaryActionIcon: "arrow.up.doc",
                    primaryActionHelp: "Upload Files",
                    primaryAction: chooseFilesToUpload,
                    dragPayload: { entry in SFTPDragPayload.remote(appending(entry.name, to: remotePath)) },
                    handleDrop: { providers in
                        handleDrop(providers, toLocal: false)
                    },
                    contextMenu: { entry in remoteContextMenu(for: entry) },
                    bgContextMenu: { remoteBgContextMenu() },
                    showStatus: { showStatus($0) },
                    activateCommands: activateRemoteCommands,
                    deactivateCommands: { SFTPCommandCenter.shared.blur(id: remoteCommandID) }
                )
            }
        }
    }

    @ViewBuilder
    private func localContextMenu(for entry: BrowserEntry) -> some View {
        Button("上传", systemImage: "arrow.up.doc") { upload(entry) }
        Divider()
        Button("查看信息", systemImage: "info.circle") { showInfo(for: entry, isLocal: true) }
        Divider()
        Button("复制", systemImage: "doc.on.doc") { copyContextSelection(entry: entry, isLocal: true) }
        Button("剪切", systemImage: "scissors") { cutContextSelection(entry: entry, isLocal: true) }
        Button("粘贴", systemImage: "doc.on.clipboard") { paste(toLocal: true) }
            .disabled(clipboard.isEmpty)
        Divider()
        Button("重命名", systemImage: "pencil") { beginRename(entry, isLocal: true) }
        Button("删除", systemImage: "trash", role: .destructive) { delete(entry, isLocal: true) }
    }

    @ViewBuilder
    private func localBgContextMenu() -> some View {
        Button("新建文件夹", systemImage: "folder.badge.plus") { beginCreate(isFolder: true, isLocal: true) }
        Button("新建文件", systemImage: "doc.badge.plus") { beginCreate(isFolder: false, isLocal: true) }
        Divider()
        Button("粘贴", systemImage: "doc.on.clipboard") { paste(toLocal: true) }
            .disabled(clipboard.isEmpty)
    }

    @ViewBuilder
    private func remoteContextMenu(for entry: BrowserEntry) -> some View {
        if !entry.isDirectory {
            Button("打开", systemImage: "doc.text") {
                openFileInBuiltInEditor(entry)
            }
            OpenWithMenu(entry: entry, host: session.host, remotePath: remotePath, password: manualPassword)
            Divider()
        }
        Button("下载", systemImage: "arrow.down.doc") { download(entry) }
        Button("下载到...", systemImage: "arrow.down.doc.fill") { downloadTo(entry) }
        Divider()
        Button("查看信息", systemImage: "info.circle") { showInfo(for: entry, isLocal: false) }
        Divider()
        Button("复制", systemImage: "doc.on.doc") { copyContextSelection(entry: entry, isLocal: false) }
        Button("剪切", systemImage: "scissors") { cutContextSelection(entry: entry, isLocal: false) }
        Button("粘贴", systemImage: "doc.on.clipboard") { paste(toLocal: false) }
            .disabled(clipboard.isEmpty)
        Divider()
        Button("重命名", systemImage: "pencil") { beginRename(entry, isLocal: false) }
        Button("修改权限...", systemImage: "lock.shield") { beginChmod(entry) }
        Button("修改所有者...", systemImage: "person.badge.shield") { beginChown(entry) }
        Divider()
        Button("删除", systemImage: "trash", role: .destructive) { delete(entry, isLocal: false) }
    }

    @ViewBuilder
    private func remoteBgContextMenu() -> some View {
        Button("新建文件夹", systemImage: "folder.badge.plus") { beginCreate(isFolder: true, isLocal: false) }
        Button("新建文件", systemImage: "doc.badge.plus") { beginCreate(isFolder: false, isLocal: false) }
        Divider()
        Button("粘贴", systemImage: "doc.on.clipboard") { paste(toLocal: false) }
            .disabled(clipboard.isEmpty)
    }

    // Maintain a reference to open editors to prevent them from being deallocated
    @State private var openEditors: [String: FileEditorWindowController] = [:]

    private func openFileInBuiltInEditor(_ entry: BrowserEntry) {
        let fullPath = remotePath + "/" + entry.name
        let localURL = SFTPFileCoordinator.shared.getLocalURL(hostID: session.host.id, remotePath: fullPath)

        Task {
            let taskID = SFTPTransferManager.shared.startTask(hostID: session.host.id, type: .download, remotePath: fullPath, localURL: localURL)
            SFTPTransferManager.shared.updateProgress(id: taskID, progress: 0.1)

            let success = await SFTPFileCoordinator.shared.downloadAndWatch(
                remotePath: fullPath,
                localURL: localURL,
                host: session.host,
                password: manualPassword
            )

            if success {
                SFTPTransferManager.shared.updateProgress(id: taskID, progress: 1.0)
                SFTPTransferManager.shared.completeTask(id: taskID, success: true)

                if let content = try? String(contentsOf: localURL, encoding: .utf8) {
                    let controller = FileEditorWindowController(
                        hostID: session.host.id,
                        remotePath: fullPath,
                        content: content
                    ) { newContent in
                        // Save handler
                        try? newContent.write(to: localURL, atomically: true, encoding: .utf8)
                        // SFTPFileCoordinator's file watcher will pick this up automatically!
                    }

                    openEditors[fullPath] = controller
                    controller.showWindow(nil)
                } else {
                    // Not a text file, open with default app instead
                    let config = NSWorkspace.OpenConfiguration()
                    NSWorkspace.shared.open([localURL], withApplicationAt: NSWorkspace.shared.urlForApplication(toOpen: localURL)!, configuration: config, completionHandler: nil)
                }
            } else {
                SFTPTransferManager.shared.completeTask(id: taskID, success: false, error: "Download failed")
            }
        }
    }

    private func loadLocal(at url: URL? = nil) {
        let path = normalizedLocalURL(url ?? localURL)
        localLoadToken &+= 1
        let token = localLoadToken
        localErrorMessage = nil
        NSLog("[SFTP] loadLocal start: path=%@", path.path)
        Task {
            let result: (entries: [BrowserEntry], error: String?) = {
                let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
                let fm = FileManager.default
                var urls: [URL] = []
                let didAccess = path.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        path.stopAccessingSecurityScopedResource()
                    }
                }
                do {
                    let values = try path.resourceValues(forKeys: [.isDirectoryKey])
                    guard values.isDirectory == true else {
                        return ([], "'\(path.path)' is not a folder.")
                    }
                    urls = try fm.contentsOfDirectory(
                        at: path,
                        includingPropertiesForKeys: Array(keys),
                        options: []
                    )
                } catch {
                    NSLog("[SFTP] loadLocal ERROR contentsOfDirectory: %@", error.localizedDescription)
                    return ([], error.localizedDescription)
                }
                NSLog("[SFTP] loadLocal: rawURLCount=%ld", urls.count)
                let result = urls.map { url in
                    let values = try? url.resourceValues(forKeys: keys)
                    let isDir = values?.isDirectory ?? false
                    let size = Int64(values?.fileSize ?? 0)
                    if values == nil {
                        NSLog("[SFTP] loadLocal entry FAILED resourceValues: name=%@", url.lastPathComponent)
                    }
                    return BrowserEntry(
                        name: url.lastPathComponent,
                        isDirectory: isDir,
                        size: size,
                        modificationDate: values?.contentModificationDate
                    )
                }
                .sorted {
                    if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return (result, nil)
            }()

            guard token == localLoadToken else {
                NSLog("[SFTP] loadLocal superseded: path=%@", path.path)
                return
            }
            self.localEntries = result.entries
            self.localErrorMessage = result.error
            NSLog("[SFTP] loadLocal done: entryCount=%ld error=%@", result.entries.count, result.error ?? "nil")
        }
    }

    private func openLocal(_ entry: BrowserEntry) {
        guard entry.isDirectory else { return }
        let newURL = normalizedLocalURL(localURL.appending(path: entry.name))
        NSLog("[SFTP] openLocal: %@ -> %@", entry.name, newURL.path)
        setLocalURL(newURL)
    }

    private func localGoUp() {
        let oldPath = localURL.path
        let parent = normalizedLocalURL(localURL.deletingLastPathComponent())
        NSLog("[SFTP] localGoUp: %@ -> %@", oldPath, parent.path)
        setLocalURL(parent)
    }

    private func navigateLocal(to path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let expanded = NSString(string: trimmed).expandingTildeInPath
        let url: URL
        if expanded.hasPrefix("/") {
            url = URL(fileURLWithPath: expanded)
        } else {
            url = localURL.appending(path: expanded)
        }
        setLocalURL(normalizedLocalURL(url))
    }

    private func setLocalURL(_ url: URL) {
        let normalized = normalizedLocalURL(url)
        localURL = normalized
        loadLocal(at: normalized)
    }

    private func normalizedLocalURL(_ url: URL) -> URL {
        url.standardizedFileURL
    }

    private func loadRemote() {
        guard !remote.isLoading else { return }
        Task { _ = await remote.load(path: remotePath, manualPassword: manualPassword.isEmpty ? nil : manualPassword) }
    }

    private func openRemote(_ entry: BrowserEntry) {
        guard entry.isDirectory else { return }
        let newPath = appending(entry.name, to: remotePath)
        NSLog("[SFTP] openRemote: %@ -> %@", entry.name, newPath)
        remotePath = newPath
        loadRemote()
    }

    private func remoteGoUp() {
        guard remotePath != "/" else { return }
        if remotePath == "~" {
            // From home, go up to parent of home (resolve to absolute path)
            remotePath = "/"
            loadRemote()
            return
        }
        if remotePath.hasPrefix("~/") {
            let parent = NSString(string: remotePath).deletingLastPathComponent
            remotePath = parent.isEmpty ? "~" : parent
        } else {
            remotePath = NSString(string: remotePath).deletingLastPathComponent
            if remotePath.isEmpty { remotePath = "/" }
        }
        loadRemote()
    }

    private func appending(_ component: String, to path: String) -> String {
        if path == "/" { return "/\(component)" }
        return "\(path)/\(component)"
    }

    private func upload(_ entry: BrowserEntry) {
        upload(localURL: localURL.appending(path: entry.name))
    }

    private func upload(localURL: URL) {
        remote.upload(localURL: localURL, to: remotePath, manualPassword: manualPassword.isEmpty ? nil : manualPassword) {
            loadRemote()
            showStatus("Uploaded '\(localURL.lastPathComponent)'")
        }
    }

    private func chooseFilesToUpload() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Upload"
        panel.message = NSLocalizedString("Choose files or folders to upload to the current remote directory.", comment: "SFTP upload picker")

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            upload(localURL: url)
        }
    }

    private func download(_ entry: BrowserEntry) {
        remote.download(entry: entry, from: remotePath, to: localURL, manualPassword: manualPassword.isEmpty ? nil : manualPassword) {
            loadLocal()
            showStatus("Downloaded '\(entry.name)'")
        }
    }

    private func handleDrop(_ providers: [NSItemProvider], toLocal: Bool) -> Bool {
        guard !providers.isEmpty else { return false }
        Task {
            var handled = false
            for provider in providers {
                if let location = await loadInternalDragLocation(from: provider) {
                    handled = true
                    await MainActor.run {
                        handleDroppedLocation(location, toLocal: toLocal)
                    }
                    continue
                }
                if let url = await loadFileURL(from: provider) {
                    handled = true
                    await MainActor.run {
                        handleDroppedLocation(.local(url), toLocal: toLocal)
                    }
                }
            }
            if !handled {
                await MainActor.run {
                    showStatus("Drop did not contain files", isError: true)
                }
            }
        }
        return true
    }

    private func handleDroppedLocation(_ location: FileLocation, toLocal: Bool) {
        switch (location, toLocal) {
        case (.local(let sourceURL), true):
            let destination = localURL.appending(path: sourceURL.lastPathComponent)
            guard sourceURL.standardizedFileURL != destination.standardizedFileURL else {
                showStatus("'\(sourceURL.lastPathComponent)' is already in this folder")
                return
            }
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destination)
                loadLocal()
                showStatus("Copied '\(sourceURL.lastPathComponent)'")
            } catch {
                showStatus(error.localizedDescription, isError: true)
            }
        case (.local(let sourceURL), false):
            remote.upload(localURL: sourceURL, to: remotePath, manualPassword: manualPassword.isEmpty ? nil : manualPassword) {
                loadRemote()
                showStatus("Uploaded '\(sourceURL.lastPathComponent)'")
            }
        case (.remote(let sourcePath), true):
            let destination = localURL.appending(path: URL(fileURLWithPath: sourcePath).lastPathComponent)
            remote.download(remotePath: sourcePath, toLocalURL: destination, manualPassword: manualPassword.isEmpty ? nil : manualPassword) {
                loadLocal()
                showStatus("Downloaded '\(destination.lastPathComponent)'")
            }
        case (.remote(let sourcePath), false):
            let name = URL(fileURLWithPath: sourcePath).lastPathComponent
            let destinationPath = appending(name, to: remotePath)
            guard sourcePath != destinationPath else {
                showStatus("'\(name)' is already in this folder")
                return
            }
            performAfterPreparingRemoteDestination(destinationPath, replacing: remote.entries.contains(where: { $0.name == name })) {
                remote.runCommand(
                    command: "cp -r \(RemoteDirectoryBrowser.shellQuote(sourcePath)) \(RemoteDirectoryBrowser.shellQuote(destinationPath))",
                    manualPassword: manualPassword.isEmpty ? nil : manualPassword
                ) { success, err in
                    if success {
                        loadRemote()
                        showStatus("Copied '\(name)'")
                    } else {
                        showStatus(err, isError: true)
                    }
                }
            }
        }
    }

    private func loadInternalDragLocation(from provider: NSItemProvider) async -> FileLocation? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.text.identifier)
                || provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) else {
            return nil
        }
        for identifier in [UTType.text.identifier, UTType.plainText.identifier] {
            guard provider.hasItemConformingToTypeIdentifier(identifier),
                  let value = await loadProviderItem(provider, identifier: identifier) else {
                continue
            }
            if let data = value as? Data,
               let text = String(data: data, encoding: .utf8),
               let location = SFTPDragPayload.parse(text) {
                return location
            }
            if let text = value as? String,
               let location = SFTPDragPayload.parse(text) {
                return location
            }
            if let text = value as? NSString,
               let location = SFTPDragPayload.parse(text as String) {
                return location
            }
        }
        return nil
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
              let item = await loadProviderItem(provider, identifier: UTType.fileURL.identifier) else {
            return nil
        }
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data,
           let text = String(data: data, encoding: .utf8) {
            return URL(string: text)
        }
        if let text = item as? String {
            return URL(string: text)
        }
        return nil
    }

    private func loadProviderItem(_ provider: NSItemProvider, identifier: String) async -> Any? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }

    private func showStatus(_ msg: String, isError: Bool = false) {
        withAnimation {
            statusMessage = msg
            statusIsError = isError
        }
        if !isError {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation {
                    if statusMessage == msg { statusMessage = nil }
                }
            }
        }
    }

    private func activateLocalCommands() {
        TerminalCommandCenter.shared.blur()
        SFTPCommandCenter.shared.focus(
            id: localCommandID,
            copy: { copySelection(isLocal: true) },
            cut: { cutSelection(isLocal: true) },
            paste: { paste(toLocal: true) },
            selectAll: { localSelection = Set(localEntries.map(\.name)) }
        )
    }

    private func activateRemoteCommands() {
        TerminalCommandCenter.shared.blur()
        SFTPCommandCenter.shared.focus(
            id: remoteCommandID,
            copy: { copySelection(isLocal: false) },
            cut: { cutSelection(isLocal: false) },
            paste: { pasteFilesFromPasteboardOrSFTPClipboard() },
            selectAll: { remoteSelection = Set(remote.entries.map(\.name)) }
        )
    }

    /// Finder's copy command places file URLs on the general pasteboard. Prefer
    /// those URLs when the remote panel receives Command-V, then retain the
    /// existing in-app clipboard as a fallback for remote/local file operations.
    private func pasteFilesFromPasteboardOrSFTPClipboard() {
        let urls = pastedFileURLs()
        guard !urls.isEmpty else {
            paste(toLocal: false)
            return
        }
        for url in urls {
            handleDroppedLocation(.local(url), toLocal: false)
        }
    }

    private func pastedFileURLs() -> [URL] {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            return urls
        }
        if let paths = pasteboard.propertyList(forType: .fileURL) as? [String] {
            return paths.compactMap { value in
                if let url = URL(string: value), url.isFileURL {
                    return url
                }
                return URL(fileURLWithPath: value)
            }
        }
        if let value = pasteboard.string(forType: .fileURL),
           let url = URL(string: value),
           url.isFileURL {
            return [url]
        }
        return []
    }

    private func selectedEntries(isLocal: Bool) -> [BrowserEntry] {
        let selection = isLocal ? localSelection : remoteSelection
        let entries = isLocal ? localEntries : remote.entries
        return entries.filter { selection.contains($0.name) }
    }

    private func contextEntries(entry: BrowserEntry, isLocal: Bool) -> [BrowserEntry] {
        let selection = isLocal ? localSelection : remoteSelection
        if selection.contains(entry.name) {
            let selected = selectedEntries(isLocal: isLocal)
            if !selected.isEmpty { return selected }
        }
        return [entry]
    }

    private func copyContextSelection(entry: BrowserEntry, isLocal: Bool) {
        setClipboard(entries: contextEntries(entry: entry, isLocal: isLocal), isLocal: isLocal, operation: .copy)
    }

    private func cutContextSelection(entry: BrowserEntry, isLocal: Bool) {
        setClipboard(entries: contextEntries(entry: entry, isLocal: isLocal), isLocal: isLocal, operation: .cut)
    }

    private func copySelection(isLocal: Bool) {
        setClipboard(entries: selectedEntries(isLocal: isLocal), isLocal: isLocal, operation: .copy)
    }

    private func cutSelection(isLocal: Bool) {
        setClipboard(entries: selectedEntries(isLocal: isLocal), isLocal: isLocal, operation: .cut)
    }

    private func setClipboard(entries: [BrowserEntry], isLocal: Bool, operation: ClipboardOperation) {
        guard !entries.isEmpty else {
            showStatus("No files selected", isError: true)
            return
        }
        clipboard = entries.map { entry in
            ClipboardItem(
                location: isLocal
                    ? .local(localURL.appending(path: entry.name))
                    : .remote(appending(entry.name, to: remotePath)),
                operation: operation,
                name: entry.name,
                isDirectory: entry.isDirectory
            )
        }
        let verb = operation == .copy ? "Copied" : "Cut"
        showStatus(entries.count == 1 ? "\(verb) '\(entries[0].name)'" : "\(verb) \(entries.count) items")
    }

    private func paste(toLocal: Bool) {
        guard !clipboard.isEmpty else {
            showStatus("SFTP clipboard is empty", isError: true)
            return
        }
        let items = clipboard
        let existingNames = Set((toLocal ? localEntries : remote.entries).map(\.name))
        let conflicts = items.map(\.name).filter(existingNames.contains)
        if !conflicts.isEmpty {
            pendingPaste = PendingPasteRequest(items: items, toLocal: toLocal, conflictNames: conflicts)
            return
        }
        executePaste(items: items, toLocal: toLocal, policy: .replace)
    }

    private var pasteConflictTitle: String {
        guard let pendingPaste else { return "Items Already Exist" }
        if pendingPaste.conflictNames.count == 1, let name = pendingPaste.conflictNames.first {
            return "'\(name)' Already Exists"
        }
        return "\(pendingPaste.conflictNames.count) Items Already Exist"
    }

    private func resolvePendingPaste(with policy: PasteConflictPolicy) {
        guard let request = pendingPaste else { return }
        pendingPaste = nil
        executePaste(items: request.items, toLocal: request.toLocal, policy: policy)
    }

    private func executePaste(items: [ClipboardItem], toLocal: Bool, policy: PasteConflictPolicy) {
        showStatus(items.count == 1 ? "Pasting '\(items[0].name)'..." : "Pasting \(items.count) items...")
        var reservedNames = Set((toLocal ? localEntries : remote.entries).map(\.name))
        for item in items {
            let destinationName: String
            if policy == .keepBoth, reservedNames.contains(item.name) {
                destinationName = uniquePasteName(for: item.name, reservedNames: reservedNames)
            } else {
                destinationName = item.name
            }
            let replacing = policy == .replace && reservedNames.contains(destinationName)
            reservedNames.insert(destinationName)
            paste(item, toLocal: toLocal, destinationName: destinationName, replacing: replacing)
        }
    }

    private func paste(_ item: ClipboardItem, toLocal: Bool, destinationName: String, replacing: Bool) {
        let destName = destinationName
        if toLocal {
            let destURL = localURL.appending(path: destName)
            switch item.location {
            case .local(let srcURL):
                if srcURL.standardizedFileURL == destURL.standardizedFileURL {
                    if item.operation == .cut { removeCutItemFromClipboard(item) }
                    showStatus("'\(destName)' is already in this folder")
                    return
                }
                do {
                    if replacing, FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    if item.operation == .cut {
                        try FileManager.default.moveItem(at: srcURL, to: destURL)
                        removeCutItemFromClipboard(item)
                    } else {
                        try FileManager.default.copyItem(at: srcURL, to: destURL)
                    }
                    loadLocal()
                    showStatus("Pasted '\(destName)'")
                } catch {
                    showStatus(error.localizedDescription, isError: true)
                }
            case .remote(let srcPath):
                do {
                    if replacing, FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                } catch {
                    showStatus(error.localizedDescription, isError: true)
                    return
                }
                remote.download(remotePath: srcPath, toLocalURL: destURL, manualPassword: manualPassword.isEmpty ? nil : manualPassword) {
                    if item.operation == .cut {
                        remote.runCommand(command: "rm -rf \(RemoteDirectoryBrowser.shellQuote(srcPath))", manualPassword: manualPassword.isEmpty ? nil : manualPassword) { success, error in
                            if success {
                                loadRemote()
                                removeCutItemFromClipboard(item)
                            } else {
                                showStatus(error, isError: true)
                            }
                        }
                    }
                    loadLocal()
                    showStatus("Pasted '\(destName)' from remote")
                }
            }
        } else {
            let destPath = appending(destName, to: remotePath)
            switch item.location {
            case .local(let srcURL):
                performAfterPreparingRemoteDestination(destPath, replacing: replacing) {
                    remote.upload(localURL: srcURL, toRemotePath: destPath, manualPassword: manualPassword.isEmpty ? nil : manualPassword) {
                        if item.operation == .cut {
                            try? FileManager.default.removeItem(at: srcURL)
                            loadLocal()
                            removeCutItemFromClipboard(item)
                        }
                        loadRemote()
                        showStatus("Pasted '\(destName)' to remote")
                    }
                }
            case .remote(let srcPath):
                if srcPath == destPath {
                    if item.operation == .cut {
                        removeCutItemFromClipboard(item)
                    }
                    showStatus("'\(destName)' is already in this folder")
                    return
                }
                performAfterPreparingRemoteDestination(destPath, replacing: replacing) {
                    let cmd = item.operation == .cut ? "mv" : "cp -r"
                    remote.runCommand(command: "\(cmd) \(RemoteDirectoryBrowser.shellQuote(srcPath)) \(RemoteDirectoryBrowser.shellQuote(destPath))", manualPassword: manualPassword.isEmpty ? nil : manualPassword) { success, err in
                        if success {
                            if item.operation == .cut { removeCutItemFromClipboard(item) }
                            loadRemote()
                            showStatus("Pasted '\(destName)'")
                        } else {
                            showStatus(err, isError: true)
                        }
                    }
                }
            }
        }
    }

    private func performAfterPreparingRemoteDestination(
        _ destinationPath: String,
        replacing: Bool,
        operation: @escaping () -> Void
    ) {
        guard replacing else {
            operation()
            return
        }
        remote.runCommand(
            command: "rm -rf \(RemoteDirectoryBrowser.shellQuote(destinationPath))",
            manualPassword: manualPassword.isEmpty ? nil : manualPassword
        ) { success, error in
            if success {
                operation()
            } else {
                showStatus(error, isError: true)
            }
        }
    }

    private func uniquePasteName(for name: String, reservedNames: Set<String>) -> String {
        let nsName = name as NSString
        let ext = nsName.pathExtension
        let base = ext.isEmpty ? name : nsName.deletingPathExtension
        var candidate = ext.isEmpty ? "\(base) copy" : "\(base) copy.\(ext)"
        var suffix = 2
        while reservedNames.contains(candidate) {
            candidate = ext.isEmpty ? "\(base) copy \(suffix)" : "\(base) copy \(suffix).\(ext)"
            suffix += 1
        }
        return candidate
    }

    private func removeCutItemFromClipboard(_ item: ClipboardItem) {
        clipboard.removeAll { $0.id == item.id }
    }

    private func delete(_ entry: BrowserEntry, isLocal: Bool) {
        if isLocal {
            do {
                try FileManager.default.removeItem(at: localURL.appending(path: entry.name))
                loadLocal()
                showStatus("Deleted '\(entry.name)'")
            } catch {
                showStatus(error.localizedDescription, isError: true)
            }
        } else {
            let path = appending(entry.name, to: remotePath)
            remote.runCommand(command: "rm -rf \(RemoteDirectoryBrowser.shellQuote(path))", manualPassword: manualPassword.isEmpty ? nil : manualPassword) { success, err in
                if success {
                    loadRemote()
                    showStatus("Deleted '\(entry.name)'")
                } else {
                    showStatus(err, isError: true)
                }
            }
        }
    }

    private func beginRename(_ entry: BrowserEntry, isLocal: Bool) {
        itemToRename = entry
        newName = entry.name
        isRenamingLocal = isLocal
    }

    private func performRename(_ entry: BrowserEntry) {
        let newNameTrimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newNameTrimmed.isEmpty, newNameTrimmed != entry.name else { return }

        if isRenamingLocal {
            do {
                let src = localURL.appending(path: entry.name)
                let dst = localURL.appending(path: newNameTrimmed)
                try FileManager.default.moveItem(at: src, to: dst)
                loadLocal()
                showStatus("Renamed to '\(newNameTrimmed)'")
            } catch {
                showStatus(error.localizedDescription, isError: true)
            }
        } else {
            let src = appending(entry.name, to: remotePath)
            let dst = appending(newNameTrimmed, to: remotePath)
            remote.runCommand(command: "mv \(RemoteDirectoryBrowser.shellQuote(src)) \(RemoteDirectoryBrowser.shellQuote(dst))", manualPassword: manualPassword.isEmpty ? nil : manualPassword) { success, err in
                if success {
                    loadRemote()
                    showStatus("Renamed to '\(newNameTrimmed)'")
                } else {
                    showStatus(err, isError: true)
                }
            }
        }
    }

    private func beginCreate(isFolder: Bool, isLocal: Bool) {
        if isFolder {
            isCreatingFolder = true
        } else {
            isCreatingFile = true
        }
        isCreatingLocal = isLocal
        newFileName = ""
    }

    private func performCreate() {
        let name = newFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let isFolder = isCreatingFolder

        if isCreatingLocal {
            let url = localURL.appending(path: name)
            do {
                if isFolder {
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                } else {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                loadLocal()
                showStatus("Created '\(name)'")
            } catch {
                showStatus(error.localizedDescription, isError: true)
            }
        } else {
            let path = appending(name, to: remotePath)
            let cmd = isFolder ? "mkdir -p \(RemoteDirectoryBrowser.shellQuote(path))" : "touch \(RemoteDirectoryBrowser.shellQuote(path))"
            remote.runCommand(command: cmd, manualPassword: manualPassword.isEmpty ? nil : manualPassword) { success, err in
                if success {
                    loadRemote()
                    showStatus("Created '\(name)'")
                } else {
                    showStatus(err, isError: true)
                }
            }
        }
    }

    private func beginChmod(_ entry: BrowserEntry) {
        itemToChmod = entry
        newPermissions = "755"
    }

    private func performChmod(_ entry: BrowserEntry) {
        let path = appending(entry.name, to: remotePath)
        remote.runCommand(command: "chmod \(newPermissions) \(RemoteDirectoryBrowser.shellQuote(path))", manualPassword: manualPassword.isEmpty ? nil : manualPassword) { success, err in
            if success {
                loadRemote()
                showStatus("Permissions updated")
            } else {
                showStatus(err, isError: true)
            }
        }
    }

    private func beginChown(_ entry: BrowserEntry) {
        itemToChown = entry
        newOwner = "root:root"
    }

    private func performChown(_ entry: BrowserEntry) {
        let path = appending(entry.name, to: remotePath)
        remote.runCommand(command: "chown \(newOwner) \(RemoteDirectoryBrowser.shellQuote(path))", manualPassword: manualPassword.isEmpty ? nil : manualPassword) { success, err in
            if success {
                loadRemote()
                showStatus("Owner updated")
            } else {
                showStatus(err, isError: true)
            }
        }
    }

    private func showInfo(for entry: BrowserEntry, isLocal: Bool) {
        if isLocal {
            let url = localURL.appending(path: entry.name)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                let size = attrs[.size] as? Int64 ?? 0
                let perms = String(format: "%o", attrs[.posixPermissions] as? Int ?? 0)
                let owner = attrs[.ownerAccountName] as? String ?? ""
                itemInfoText = "名称: \(entry.name)\n大小: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))\n权限: \(perms)\n所有者: \(owner)"
                itemToShowInfo = entry
            }
        } else {
            let path = appending(entry.name, to: remotePath)
            remote.runCommand(command: "ls -ld \(RemoteDirectoryBrowser.shellQuote(path))", manualPassword: manualPassword.isEmpty ? nil : manualPassword) { success, out in
                if success {
                    itemInfoText = out
                    itemToShowInfo = entry
                } else {
                    showStatus(out, isError: true)
                }
            }
        }
    }

    private func downloadTo(_ entry: BrowserEntry) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "下载到此处"
        if panel.runModal() == .OK, let url = panel.url {
            remote.download(entry: entry, from: remotePath, to: url, manualPassword: manualPassword.isEmpty ? nil : manualPassword) {
                showStatus("Downloaded '\(entry.name)' to \(url.lastPathComponent)")
            }
        }
    }
}

private struct SFTPAlerts: ViewModifier {
    @Binding var isPromptingPassword: Bool
    @Binding var manualPassword: String
    @Binding var itemToRename: BrowserEntry?
    @Binding var newName: String
    @Binding var isCreatingFolder: Bool
    @Binding var isCreatingFile: Bool
    @Binding var newFileName: String
    @Binding var itemToChmod: BrowserEntry?
    @Binding var newPermissions: String
    @Binding var itemToChown: BrowserEntry?
    @Binding var newOwner: String
    @Binding var itemToShowInfo: BrowserEntry?
    let itemInfoText: String
    let session: SSHSession
    let loadRemote: () -> Void
    let performRename: (BrowserEntry) -> Void
    let performCreate: () -> Void
    let performChmod: (BrowserEntry) -> Void
    let performChown: (BrowserEntry) -> Void

    func body(content: Content) -> some View {
        content
            .alert("需要认证", isPresented: $isPromptingPassword) {
                SecureField("密码", text: $manualPassword)
                Button("取消", role: .cancel) { }
                Button("连接") { loadRemote() }
            } message: {
                Text("请输入 \(session.host.destination) 的 SSH 密码。")
            }
            .alert("重命名", isPresented: Binding(get: { itemToRename != nil }, set: { if !$0 { itemToRename = nil } })) {
                TextField("新名称", text: $newName)
                Button("取消", role: .cancel) { }
                Button("重命名") {
                    if let item = itemToRename { performRename(item) }
                }
            }
            .alert(isCreatingFolder ? "新建文件夹" : "新建文件", isPresented: Binding(get: { isCreatingFolder || isCreatingFile }, set: { if !$0 { isCreatingFolder = false; isCreatingFile = false } })) {
                TextField("名称", text: $newFileName)
                Button("取消", role: .cancel) { }
                Button("创建") { performCreate() }
            }
            .alert("修改权限", isPresented: Binding(get: { itemToChmod != nil }, set: { if !$0 { itemToChmod = nil } })) {
                TextField("模式 (例如 755)", text: $newPermissions)
                Button("取消", role: .cancel) { }
                Button("应用") {
                    if let item = itemToChmod { performChmod(item) }
                }
            }
            .alert("修改所有者", isPresented: Binding(get: { itemToChown != nil }, set: { if !$0 { itemToChown = nil } })) {
                TextField("所有者:组", text: $newOwner)
                Button("取消", role: .cancel) { }
                Button("应用") {
                    if let item = itemToChown { performChown(item) }
                }
            }
            .alert("项目信息", isPresented: Binding(get: { itemToShowInfo != nil }, set: { if !$0 { itemToShowInfo = nil } })) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(itemInfoText)
            }
    }
}
