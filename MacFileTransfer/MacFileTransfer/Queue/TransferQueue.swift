import Foundation
import Combine

// MARK: - TransferItem

final class TransferItem: ObservableObject, Identifiable {
    let id           = UUID()
    let requestId:    String
    let sourceDevice: Device
    let files:        [FileMetadata]
    let createdAt     = Date()

    @Published var status:   TransferStatus
    @Published var progress: [String: TransferProgress] = [:]

    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }

    var overallPercentage: Double {
        guard !progress.isEmpty else { return 0 }
        return progress.values.reduce(0.0) { $0 + $1.percentage } / Double(progress.count)
    }

    var currentSpeedFormatted: String {
        let speed = progress.values.first(where: { $0.speedBytesPerSecond > 0 })?.speedBytesPerSecond ?? 0
        guard speed > 0 else { return "—" }
        return String(format: "%.1f MB/s", speed / 1_048_576)
    }

    var estimatedTimeRemainingFormatted: String {
        guard let eta = progress.values.compactMap({ $0.estimatedTimeRemaining }).min() else { return "—" }
        if eta < 60 { return "\(Int(eta))s" }
        return "\(Int(eta / 60))m \(Int(eta.truncatingRemainder(dividingBy: 60)))s"
    }

    init(requestId: String, sourceDevice: Device, files: [FileMetadata], status: TransferStatus = .pending) {
        self.requestId    = requestId
        self.sourceDevice = sourceDevice
        self.files        = files
        self.status       = status
    }
}

// MARK: - TransferQueue

final class TransferQueue: ObservableObject {
    @Published private(set) var items: [TransferItem] = []

    var pendingItems:   [TransferItem] { items.filter { $0.status == .pending } }
    var activeItems:    [TransferItem] { items.filter { $0.status == .active || $0.status == .paused } }
    var completedItems: [TransferItem] { items.filter { [.completed,.failed,.rejected,.cancelled].contains($0.status) } }

    func enqueue(_ item: TransferItem) {
        DispatchQueue.main.async { self.items.append(item) }
    }

    func updateStatus(_ status: TransferStatus, forRequestId id: String) {
        DispatchQueue.main.async { self.items.first { $0.requestId == id }?.status = status }
    }

    func updateProgress(_ progress: TransferProgress) {
        DispatchQueue.main.async {
            self.items.first { $0.requestId == progress.requestId }?.progress[progress.fileId] = progress
        }
    }

    func clearCompleted() {
        DispatchQueue.main.async {
            self.items.removeAll { [.completed,.failed,.rejected,.cancelled].contains($0.status) }
        }
    }
}
