import Foundation
import Combine

enum TransferType {
    case upload
    case download
}

enum TransferStatus {
    case pending
    case transferring(progress: Double)
    case success
    case failed(error: String)
}

struct TransferTask: Identifiable {
    let id = UUID()
    let hostID: UUID
    let type: TransferType
    let remotePath: String
    let localURL: URL
    var status: TransferStatus
    var startTime: Date
    var endTime: Date?
    
    var fileName: String {
        URL(fileURLWithPath: remotePath).lastPathComponent
    }

    var sourceDescription: String {
        switch type {
        case .upload:
            return localURL.path
        case .download:
            return remotePath
        }
    }

    var destinationDescription: String {
        switch type {
        case .upload:
            return remotePath
        case .download:
            return localURL.path
        }
    }
}

@MainActor
class SFTPTransferManager: ObservableObject {
    static let shared = SFTPTransferManager()
    
    @Published var tasks: [TransferTask] = []
    
    @Published var isPopoverPresented = false
    private enum PresentationMode {
        case automatic
        case manual
    }
    private var presentationMode: PresentationMode?
    private var autoDismissTask: Task<Void, Never>?

    private init() {}
    
    func startTask(hostID: UUID, type: TransferType, remotePath: String, localURL: URL) -> UUID {
        let task = TransferTask(
            hostID: hostID,
            type: type,
            remotePath: remotePath,
            localURL: localURL,
            status: .pending,
            startTime: Date()
        )
        tasks.insert(task, at: 0)
        presentForNewTransfer()
        return task.id
    }

    func togglePopoverByUser() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        if isPopoverPresented {
            isPopoverPresented = false
            presentationMode = nil
        } else {
            isPopoverPresented = true
            presentationMode = .manual
        }
    }

    func setPopoverPresented(_ presented: Bool) {
        isPopoverPresented = presented
        if !presented {
            autoDismissTask?.cancel()
            autoDismissTask = nil
            presentationMode = nil
        }
    }

    private func presentForNewTransfer() {
        // Do not auto-close a popover the user explicitly opened.
        if isPopoverPresented, presentationMode == .manual {
            return
        }

        isPopoverPresented = true
        presentationMode = .automatic
        autoDismissTask?.cancel()
        autoDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.isPopoverPresented = false
            self?.presentationMode = nil
            self?.autoDismissTask = nil
        }
    }
    
    func updateProgress(id: UUID, progress: Double) {
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            tasks[index].status = .transferring(progress: min(1, max(0, progress)))
        }
    }
    
    func completeTask(id: UUID, success: Bool, error: String? = nil) {
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            tasks[index].status = success ? .success : .failed(error: error ?? "Unknown Error")
            tasks[index].endTime = Date()
        }
    }
    
    var activeTasks: [TransferTask] {
        tasks.filter { task in
            if case .transferring = task.status { return true }
            if case .pending = task.status { return true }
            return false
        }
    }
    
    var globalProgress: Double {
        let active = activeTasks
        guard !active.isEmpty else { return 0 }
        let totalProgress = active.reduce(0.0) { sum, task in
            if case .transferring(let p) = task.status { return sum + p }
            return sum
        }
        return totalProgress / Double(active.count)
    }
}
