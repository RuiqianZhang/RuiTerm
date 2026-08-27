import Darwin
import Foundation

private final class TerminalReadAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var deliveryScheduled = false
    private var readsPaused = false

    func append(_ data: Data, pauseThreshold: Int) -> (shouldDeliver: Bool, shouldPauseReads: Bool) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        let shouldPauseReads: Bool
        if buffer.count >= pauseThreshold && !readsPaused {
            readsPaused = true
            shouldPauseReads = true
        } else {
            shouldPauseReads = false
        }
        guard !deliveryScheduled else { return (false, shouldPauseReads) }
        deliveryScheduled = true
        return (true, shouldPauseReads)
    }

    func take() -> Data {
        lock.lock()
        defer { lock.unlock() }
        let data = buffer
        buffer = Data()
        deliveryScheduled = false
        return data
    }

    func pauseReadsIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !readsPaused else { return false }
        readsPaused = true
        return true
    }

    func resumeReadsIfPossible(pendingByteCount: Int, resumeThreshold: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard readsPaused, buffer.count + pendingByteCount <= resumeThreshold else { return false }
        readsPaused = false
        return true
    }

    func resumeReadsForCancellation() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard readsPaused else { return false }
        readsPaused = false
        return true
    }
}

@MainActor
final class SSHSession: ObservableObject {
    @Published private(set) var output = ""
    @Published private(set) var outputVersion = 0
    @Published private(set) var isConnected = false
    @Published private(set) var isConnecting = false
    @Published private(set) var isAuthenticated = false
    @Published private(set) var exitStatus: Int32?
    @Published private(set) var errorMessage: String?
    @Published private(set) var currentDirectory = "~"
    @Published private(set) var isPasswordPrompt = false
    private var typedCommand = ""

    let host: SSHHost

    private var childPID: pid_t = 0
    private var masterFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var readAccumulator: TerminalReadAccumulator?
    private var waitSource: DispatchSourceProcess?
    private var pendingUTF8 = Data()
    private var recentText = ""
    private var sentSavedPassword = false
    private var savedPassword: String?
    private var terminalSize = (columns: UInt16(100), rows: UInt16(30))
    private var connectTask: Task<Void, Never>?
    private var authenticationProbeTask: Task<Void, Never>?
    private var pendingCommand = ""
    private var terminalHandlerID: UUID?
    private var rawDataHandler: ((Data) -> Void)?
    private var terminalClearHandler: (() -> Void)?
    private var rawReplayBuffer = Data()
    private let rawReplayLimit = 64 * 1024
    private let rawReplayTrimSlack = 32 * 1024
    private let terminalControlPath = "/tmp/ruiterm-terminal-\(UUID().uuidString)"
    private var pendingRawData = Data()
    private var pendingFlushTask: Task<Void, Never>?
    private let terminalNormalFlushInterval: UInt64 = 33_340_000
    private let activeTerminalBurstFlushInterval: UInt64 = 50_000_000
    private let backgroundTerminalBurstFlushInterval: UInt64 = 750_000_000
    private let terminalBurstByteThreshold = 32 * 1024
    private let activeTerminalBurstFlushByteBudget = 24 * 1024
    private let backgroundTerminalBurstFlushByteBudget = 2 * 1024
    private let activeBackpressurePauseThreshold = 160 * 1024
    private let activeBackpressureResumeThreshold = 48 * 1024
    private let backgroundBackpressurePauseThreshold = 24 * 1024
    private let backgroundBackpressureResumeThreshold = 4 * 1024
    private var highThroughputModeUntil: TimeInterval = 0
    private var terminalOutputIsInteractive = true
    private var terminalOutputQuietUntil: TimeInterval = 0
    private var terminalOutputQuietTask: Task<Void, Never>?
    private var lastOutputPublishTime: TimeInterval = 0
    private let outputPublishInterval: TimeInterval = 0.25
    private var hasAttemptedConnection = false

    // Darwin's FIONREAD macro is not imported into Swift because it expands
    // through _IOR(). This is _IOR('f', 127, int) on macOS.
    nonisolated private static let ioctlFIONREAD = UInt(0x4004667f)
    nonisolated private static let readAccumulatorPauseThreshold = 256 * 1024

    init(host: SSHHost) {
        self.host = host
    }

    var auxiliaryControlPath: String {
        terminalControlPath
    }

    /// Safely gets the saved password, prompting for Touch ID / Biometrics on first Keychain access if enabled.
    func getOrLoadPassword() -> String? {
        if let savedPassword {
            return savedPassword
        }
        if host.savesPassword {
            let pwd = KeychainStore.password(for: host.id)
            savedPassword = pwd
            return pwd
        }
        return nil
    }

    /// Caches the manually supplied password in-memory.
    func setCachedPassword(_ pwd: String) {
        savedPassword = pwd
    }

    var cachedPassword: String? {
        savedPassword
    }

    @discardableResult
    func attachTerminal(
        rawData: @escaping (Data) -> Void,
        clear: @escaping () -> Void,
        replay: Bool = true
    ) -> UUID {
        let id = UUID()
        terminalHandlerID = id
        rawDataHandler = rawData
        terminalClearHandler = clear
        if replay, !rawReplayBuffer.isEmpty {
            rawData(rawReplayBuffer)
        }
        return id
    }

    func detachTerminal(id: UUID?) {
        guard terminalHandlerID == id else { return }
        terminalHandlerID = nil
        rawDataHandler = nil
        terminalClearHandler = nil
    }
    
    func setCurrentDirectory(_ directory: String?) {
        guard let directory = directory, !directory.isEmpty else { return }
        if directory.hasPrefix("file://") {
            if let url = URL(string: directory) {
                currentDirectory = url.path
                NSLog("[SFTP] setCurrentDirectory (file://): %@", url.path)
            }
        } else {
            currentDirectory = directory
            NSLog("[SFTP] setCurrentDirectory: %@", directory)
        }
    }

    func connect(columns requestedColumns: UInt16? = nil, rows requestedRows: UInt16? = nil) {
        guard childPID == 0, connectTask == nil, !hasAttemptedConnection else {
            NSLog("[SSH] connect() skipped: childPID=%d, connectTask=%@, hasAttempted=%@",
                  childPID, connectTask != nil ? "active" : "nil", String(hasAttemptedConnection))
            return
        }
        startConnectTask(columns: requestedColumns, rows: requestedRows)
    }

    func reconnect(columns requestedColumns: UInt16? = nil, rows requestedRows: UInt16? = nil) {
        guard childPID == 0, connectTask == nil else { return }
        hasAttemptedConnection = false
        startConnectTask(columns: requestedColumns, rows: requestedRows)
    }

    private func startConnectTask(columns requestedColumns: UInt16?, rows requestedRows: UInt16?) {
        hasAttemptedConnection = true
        if let requestedColumns { terminalSize.columns = requestedColumns }
        if let requestedRows { terminalSize.rows = requestedRows }
        isConnecting = true
        isAuthenticated = false
        errorMessage = nil
        NSLog("[SSH] startConnectTask: host=%@, savesPassword=%@, isLocal=%@",
              host.destination, String(host.savesPassword), String(host.isLocal))
        connectTask = Task { [weak self] in
            guard let self else { return }
            if host.savesPassword {
                let hostID = host.id
                savedPassword = await Task.detached(priority: .userInitiated) {
                    KeychainStore.password(for: hostID)
                }.value
                NSLog("[SSH] Password loaded: %@", savedPassword != nil ? "yes" : "no")
            }
            guard !Task.isCancelled else {
                isConnecting = false
                connectTask = nil
                return
            }
            if host.savesPassword, savedPassword == nil {
                isConnecting = false
                errorMessage = "Unable to unlock the saved password. Re-save it in the host settings."
                appendMessage(errorMessage!)
                connectTask = nil
                return
            }
            startConnection()
            connectTask = nil
        }
    }

    private func startConnection() {
        guard childPID == 0 else { return }

        let executable = host.isLocal ? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh" : "/usr/bin/ssh"
        let arguments = host.isLocal ? [executable, "-l"] : [executable] + sshArguments(for: host)
        NSLog("[SSH] Connecting to %@ with args: %@", host.destination, arguments.joined(separator: " "))
        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "RuiTerm"
        environment["TERM_PROGRAM_VERSION"] = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "dev"
        if !host.isLocal, let savedPassword {
            AskPassProvider.configureEnvironment(&environment, password: savedPassword)
        }
        var envp: [UnsafeMutablePointer<CChar>?] = environment.map {
            strdup("\($0.key)=\($0.value)")
        } + [nil]

        var descriptor: Int32 = -1
        var windowSize = winsize(
            ws_row: terminalSize.rows,
            ws_col: terminalSize.columns,
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        let pid = forkpty(&descriptor, nil, nil, &windowSize)

        if pid == 0 {
            execve(executable, &argv, &envp)
            _exit(127)
        }

        for pointer in argv {
            if let pointer { Darwin.free(pointer) }
        }
        for pointer in envp {
            if let pointer { Darwin.free(pointer) }
        }

        guard pid > 0 else {
            let error = String(cString: strerror(errno))
            NSLog("[SSH] forkpty failed: %@", error)
            errorMessage = "Unable to create terminal session: \(error)"
            output += "\(errorMessage!)\n"
            rawDataHandler?(Data("\(errorMessage!)\n".utf8))
            isConnecting = false
            return
        }

        NSLog("[SSH] Process started (pid=%d, fd=%d)", pid, descriptor)
        childPID = pid
        masterFD = descriptor
        isConnected = true
        isConnecting = false
        exitStatus = nil
        sentSavedPassword = false
        startReading()
        startWaiting()
        if host.isLocal {
            isAuthenticated = true
        } else {
            beginAuthenticationProbe()
        }
    }

    func send(_ data: Data) {
        guard masterFD >= 0 else { return }
        if data.contains(13) || data.contains(10) {
            DispatchQueue.main.async { self.isPasswordPrompt = false }
        }
        
        if let str = String(data: data, encoding: .utf8) {
            for char in str {
                if char == "\r" || char == "\n" {
                    let trimmed = typedCommand.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("cd ") {
                        let path = String(trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces))
                        if !path.isEmpty && !path.contains(";") && !path.contains("&") && !path.contains("|") {
                            var newDir = self.currentDirectory
                            if path.hasPrefix("/") {
                                newDir = path
                            } else if path == "~" {
                                newDir = "~"
                            } else {
                                newDir = (self.currentDirectory as NSString).appendingPathComponent(path)
                            }
                            
                            let isAbsolute = newDir.hasPrefix("/")
                            var parts = [String]()
                            for comp in newDir.split(separator: "/") {
                                if comp == "." || comp.isEmpty { continue }
                                if comp == ".." {
                                    if !parts.isEmpty && parts.last != "~" && parts.last != ".." {
                                        parts.removeLast()
                                    } else {
                                        parts.append("..")
                                    }
                                } else {
                                    parts.append(String(comp))
                                }
                            }
                            let normalized = (isAbsolute ? "/" : "") + parts.joined(separator: "/")
                            let finalPath = normalized.isEmpty ? (isAbsolute ? "/" : "~") : normalized
                            NSLog("[SFTP] cd parsed: raw=%@ -> newDir=%@ -> normalized=%@ -> finalPath=%@", path, newDir, normalized, finalPath)
                            DispatchQueue.main.async { self.setCurrentDirectory(finalPath) }
                        }
                    }
                    typedCommand = ""
                } else if char == "\u{7F}" || char == "\u{08}" {
                    if !typedCommand.isEmpty { typedCommand.removeLast() }
                } else if char == "\u{15}" || char == "\u{03}" {
                    typedCommand = ""
                } else if let ascii = char.asciiValue, ascii >= 32 && ascii < 127 {
                    typedCommand.append(char)
                }
            }
        }
        
        data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(masterFD, baseAddress.advanced(by: offset), buffer.count - offset)
                guard written > 0 else { break }
                offset += written
            }
        }
    }

    func resize(columns: UInt16, rows: UInt16) {
        guard terminalSize.columns != columns || terminalSize.rows != rows else { return }
        terminalSize = (columns, rows)
        guard masterFD >= 0 else { return }
        var size = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, TIOCSWINSZ, &size)
    }

    func setTerminalOutputInteractive(_ isInteractive: Bool) {
        if isInteractive {
            terminalOutputQuietUntil = 0
            terminalOutputQuietTask?.cancel()
            terminalOutputQuietTask = nil
        }
        guard terminalOutputIsInteractive != isInteractive else {
            resumeReadingIfBackpressureAllows()
            if isInteractive, !pendingRawData.isEmpty {
                pendingFlushTask?.cancel()
                pendingFlushTask = nil
                schedulePendingFlush()
            }
            return
        }
        terminalOutputIsInteractive = isInteractive
        if pendingFlushTask != nil {
            pendingFlushTask?.cancel()
            pendingFlushTask = nil
            schedulePendingFlush()
        }
        pauseReadingIfBackpressureRequires()
        resumeReadingIfBackpressureAllows()
    }

    func deferTerminalOutputForUserInteraction(seconds: TimeInterval = 6.0) {
        guard seconds > 0 else { return }
        let deadline = Date().timeIntervalSinceReferenceDate + seconds
        terminalOutputQuietUntil = max(terminalOutputQuietUntil, deadline)
        pendingFlushTask?.cancel()
        pendingFlushTask = nil
        pauseReadingIfBackpressureRequires()
        scheduleQuietResumeTask(deadline: terminalOutputQuietUntil)
    }

    func disconnect() {
        connectTask?.cancel()
        connectTask = nil
        authenticationProbeTask?.cancel()
        authenticationProbeTask = nil
        pendingFlushTask?.cancel()
        pendingFlushTask = nil
        terminalOutputQuietTask?.cancel()
        terminalOutputQuietTask = nil
        pendingRawData = Data()
        pendingUTF8 = Data()
        rawReplayBuffer = Data()
        recentText = ""
        typedCommand = ""
        rawDataHandler = nil
        terminalClearHandler = nil
        terminalHandlerID = nil
        isConnecting = false
        isAuthenticated = false
        if childPID > 0 {
            kill(childPID, SIGHUP)
        }
    }

    func clear() {
        pendingFlushTask?.cancel()
        pendingFlushTask = nil
        pendingRawData = Data()
        pendingUTF8 = Data()
        rawReplayBuffer = Data()
        recentText = ""
        output = ""
        outputVersion += 1
        terminalClearHandler?()
        resumeReadingIfBackpressureAllows()
    }

    private func startReading() {
        let descriptor = masterFD
        let accumulator = TerminalReadAccumulator()
        readAccumulator = accumulator
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .global(qos: .userInitiated))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 65_536)

            while true {
                var available: Int32 = 0
                let ioctlResult = ioctl(descriptor, Self.ioctlFIONREAD, &available)
                let targetCount = ioctlResult == 0 && available > 0
                    ? min(Int(available), buffer.count)
                    : (data.isEmpty ? buffer.count : 0)
                guard targetCount > 0 else { break }

                let count = Darwin.read(descriptor, &buffer, targetCount)
                if count > 0 {
                    data.append(buffer, count: count)
                    if ioctlResult != 0 { break }
                } else {
                    break
                }
            }

            guard !data.isEmpty else { return }
            let result = accumulator.append(data, pauseThreshold: Self.readAccumulatorPauseThreshold)
            if result.shouldPauseReads {
                source.suspend()
            }
            if result.shouldDeliver {
                Task { @MainActor [weak self, accumulator] in
                    self?.drainReadAccumulator(accumulator)
                }
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        readSource = source
        source.resume()
    }

    private func drainReadAccumulator(_ accumulator: TerminalReadAccumulator) {
        let data = accumulator.take()
        guard !data.isEmpty else { return }
        append(data)
    }

    private func startWaiting() {
        let source = DispatchSource.makeProcessSource(identifier: childPID, eventMask: .exit, queue: .global())
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var status: Int32 = 0
            waitpid(self.childPID, &status, 0)
            Task { @MainActor in self.finish(status: status) }
        }
        waitSource = source
        source.resume()
    }

    private func append(_ data: Data) {
        pendingRawData.append(data)
        pauseReadingIfBackpressureRequires()
        schedulePendingFlush()
    }

    private func schedulePendingFlush() {
        guard pendingFlushTask == nil else { return }
        let now = Date().timeIntervalSinceReferenceDate
        if terminalOutputQuietUntil > now {
            let delay = UInt64((terminalOutputQuietUntil - now) * 1_000_000_000)
            pendingFlushTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                self?.flushPendingData()
            }
            return
        }
        let isHighThroughput = now < highThroughputModeUntil
            || pendingRawData.count >= terminalBurstByteThreshold
        let interval = isHighThroughput ? currentBurstFlushInterval : terminalNormalFlushInterval
        pendingFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: interval)
            self?.flushPendingData()
        }
    }

    private func flushPendingData() {
        pendingFlushTask?.cancel()
        pendingFlushTask = nil
        guard !pendingRawData.isEmpty else { return }

        let data: Data
        let byteBudget = currentBurstFlushByteBudget
        if pendingRawData.count > byteBudget {
            data = pendingRawData.prefix(byteBudget)
            pendingRawData.removeFirst(byteBudget)
        } else {
            data = pendingRawData
            pendingRawData = Data()
        }
        processTerminalData(data)
        resumeReadingIfBackpressureAllows()

        if !pendingRawData.isEmpty {
            schedulePendingFlush()
        }
    }

    private func pauseReadingIfBackpressureRequires() {
        guard pendingRawData.count >= currentBackpressurePauseThreshold,
              let readSource,
              readAccumulator?.pauseReadsIfNeeded() == true else {
            return
        }
        readSource.suspend()
    }

    private func resumeReadingIfBackpressureAllows() {
        guard let readSource,
              readAccumulator?.resumeReadsIfPossible(
                pendingByteCount: pendingRawData.count,
                resumeThreshold: currentBackpressureResumeThreshold
              ) == true else {
            return
        }
        readSource.resume()
    }

    private func scheduleQuietResumeTask(deadline: TimeInterval) {
        terminalOutputQuietTask?.cancel()
        let delay = max(0, deadline - Date().timeIntervalSinceReferenceDate)
        terminalOutputQuietTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self?.resumeDeferredTerminalOutput(deadline: deadline)
        }
    }

    private func resumeDeferredTerminalOutput(deadline: TimeInterval) {
        guard terminalOutputQuietUntil <= deadline else { return }
        terminalOutputQuietUntil = 0
        terminalOutputQuietTask = nil
        resumeReadingIfBackpressureAllows()
        if !pendingRawData.isEmpty {
            schedulePendingFlush()
        }
    }

    private var currentBurstFlushInterval: UInt64 {
        terminalOutputIsInteractive ? activeTerminalBurstFlushInterval : backgroundTerminalBurstFlushInterval
    }

    private var currentBurstFlushByteBudget: Int {
        terminalOutputIsInteractive ? activeTerminalBurstFlushByteBudget : backgroundTerminalBurstFlushByteBudget
    }

    private var currentBackpressurePauseThreshold: Int {
        terminalOutputIsInteractive ? activeBackpressurePauseThreshold : backgroundBackpressurePauseThreshold
    }

    private var currentBackpressureResumeThreshold: Int {
        terminalOutputIsInteractive ? activeBackpressureResumeThreshold : backgroundBackpressureResumeThreshold
    }

    private func cancelReadSource() {
        guard let source = readSource else {
            readAccumulator = nil
            return
        }
        if readAccumulator?.resumeReadsForCancellation() == true {
            source.resume()
        }
        source.cancel()
        readSource = nil
        readAccumulator = nil
    }

    private func processTerminalData(_ data: Data) {
        if data.count >= terminalBurstByteThreshold {
            highThroughputModeUntil = Date().timeIntervalSinceReferenceDate + 1.0
        }
        rawReplayBuffer.append(data)
        if rawReplayBuffer.count > rawReplayLimit + rawReplayTrimSlack {
            rawReplayBuffer = Data(rawReplayBuffer.suffix(rawReplayLimit))
        }
        rawDataHandler?(data)
        guard !isAuthenticated else {
            pendingUTF8.removeAll(keepingCapacity: false)
            recentText = ""
            return
        }
        pendingUTF8.append(data)
        guard let text = String(data: pendingUTF8, encoding: .utf8) else {
            if pendingUTF8.count > 64_000 {
                pendingUTF8.removeAll()
            }
            return
        }
        pendingUTF8.removeAll(keepingCapacity: false)

        if !isAuthenticated {
            recentText.append(text)
            if recentText.count > 8000 {
                recentText.removeFirst(recentText.count - 4000)
            }
            publishRecentOutputIfNeeded()

            if looksLikeAuthenticationFailure(recentText) {
                savedPassword = nil
                errorMessage = "Authentication failed. Check or re-save the password in the host settings."
            }

            if looksLikePasswordPrompt(recentText) {
                isPasswordPrompt = true
                if !sentSavedPassword {
                    // Fetch the password on-demand (prompts Touch ID if accessible control is set) only when requested
                    if let password = getOrLoadPassword() {
                        sentSavedPassword = true
                        send(Data("\(password)\r".utf8))
                    }
                }
            }
        }
    }

    private func looksLikePasswordPrompt(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("password:")
            && !looksLikeAuthenticationFailure(text)
            && (
                lowercased.contains(host.hostname.lowercased())
                    || lowercased.contains(host.destination.lowercased())
            )
    }

    private func looksLikeAuthenticationFailure(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("permission denied (")
            || lowercased.contains("permission denied, please try again")
    }

    private func appendMessage(_ message: String) {
        let line = "\(message)\n"
        recentText = String((recentText + line).suffix(4000))
        publishRecentOutput(force: true)
        let data = Data(line.utf8)
        rawReplayBuffer.append(data)
        rawDataHandler?(data)
    }

    private func stripANSI(_ text: String) -> String {
        let pattern = "\u{001B}\\[[0-9;]*[a-zA-Z]|\u{001B}\\][^\u{0007}\u{001B}]*(?:\u{0007}|\u{001B}\\\\)"
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    private func finish(status: Int32) {
        flushPendingData()
        publishRecentOutput(force: true)
        pendingFlushTask?.cancel()
        pendingFlushTask = nil
        cancelReadSource()
        waitSource?.cancel()
        waitSource = nil
        childPID = 0
        masterFD = -1
        isConnected = false
        isConnecting = false
        isAuthenticated = false
        authenticationProbeTask?.cancel()
        authenticationProbeTask = nil
        exitStatus = status
    }

    private func publishRecentOutputIfNeeded() {
        let now = Date().timeIntervalSinceReferenceDate
        guard output.isEmpty || now - lastOutputPublishTime >= outputPublishInterval else { return }
        publishRecentOutput(now: now)
    }

    private func publishRecentOutput(force: Bool = false, now: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        guard force || output.isEmpty || now - lastOutputPublishTime >= outputPublishInterval else { return }
        let preview = String(stripANSI(recentText).suffix(1000))
        if preview != output {
            output = preview
            outputVersion += 1
        }
        lastOutputPublishTime = now
    }

    private func beginAuthenticationProbe() {
        authenticationProbeTask?.cancel()
        let host = host
        let terminalControlPath = terminalControlPath
        authenticationProbeTask = Task { [weak self] in
            for _ in 0..<75 {
                guard !Task.isCancelled else { return }
                let authenticated = await Task.detached(priority: .utility) {
                    Self.hasActiveControlMaster(for: host, controlPath: terminalControlPath)
                }.value
                guard !Task.isCancelled else { return }
                if authenticated {
                    self?.isAuthenticated = true
                    self?.authenticationProbeTask = nil
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
            self?.authenticationProbeTask = nil
        }
    }

    nonisolated private static func hasActiveControlMaster(for host: SSHHost, controlPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        var arguments = [
            "-S", controlPath,
            "-O", "check",
            "-p", String(host.port)
        ]
        if !host.identityFile.isEmpty {
            arguments += ["-i", NSString(string: host.identityFile).expandingTildeInPath]
        }
        if !host.proxyJump.isEmpty {
            arguments += ["-J", host.proxyJump]
        }
        arguments.append(host.destination)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func sshArguments(for host: SSHHost) -> [String] {
        var arguments = [
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ControlMaster=yes",
            "-o", "ControlPath=\(terminalControlPath)",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "ConnectTimeout=10",
            "-o", "NumberOfPasswordPrompts=1",
            "-p", String(host.port)
        ]
        if !host.identityFile.isEmpty {
            arguments += ["-i", NSString(string: host.identityFile).expandingTildeInPath]
        }
        if !host.proxyJump.isEmpty {
            arguments += ["-J", host.proxyJump]
        }
        arguments.append(host.destination)
        return arguments
    }
}
