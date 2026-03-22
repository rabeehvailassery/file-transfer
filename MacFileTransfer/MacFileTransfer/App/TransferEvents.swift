import Foundation

// MARK: - CLI Transfer Events
// Shared between CLIController and CLITransferCoordinator

enum SendEvent {
    case connecting
    case waitingApproval
    case rejected
    case progress(pct: Double, speed: String)
    case completed(fileName: String)
    case failed(String)
}

enum ReceiveEvent {
    case incomingRequest(sender: String, files: [FileMetadata],
                         totalMB: Double, accept: (Bool) -> Void)
    case progress(pct: Double, speed: String)
    case completed(fileName: String)
    case failed(String)
    case idle
}
