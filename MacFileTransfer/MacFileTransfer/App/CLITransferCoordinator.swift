import Foundation

// MARK: - CLITransferCoordinator
// Bridges DeviceDiscoveryService, TCPConnectionManager, and FileTransferEngine
// to simple callback-based events consumed by CLIController.

final class CLITransferCoordinator {

    private let discoveryService = DeviceDiscoveryService()
    private let tcpManager       = TCPConnectionManager()
    private let transferEngine   = FileTransferEngine()
    private let queue            = TransferQueue()

    private let deviceId   = DeviceDiscoveryService.loadOrCreateDeviceId()
    private let deviceName = Host.current().localizedName ?? "Mac"

    private var onDiscover:    ((Device) -> Void)?
    private var onSendEvent:   ((SendEvent) -> Void)?
    private var onReceiveEvent: ((ReceiveEvent) -> Void)?
    private var saveDirectory: URL?

    init() {
        tcpManager.delegate       = self
        discoveryService.delegate = self
        transferEngine.delegate   = self
    }

    // MARK: - Discover

    func startDiscovery(onDevice: @escaping (Device) -> Void) {
        self.onDiscover = onDevice
        discoveryService.start()
        tcpManager.startListening()
    }

    // MARK: - Send

    func send(fileURL: URL, toIP: String, onEvent: @escaping (SendEvent) -> Void) {
        self.onSendEvent = onEvent
        tcpManager.startListening()

        guard let attrs   = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size     = attrs[.size] as? Int64 else {
            onEvent(.failed("Cannot read file attributes")); return
        }

        let meta = FileMetadata(name: fileURL.lastPathComponent, size: size, mimeType: "application/octet-stream")
        let requestId = UUID().uuidString
        let device = Device(id: UUID(), name: "Remote", type: .android,
                            ipAddress: toIP, listeningPort: Int(DeviceDiscoveryService.tcpPort),
                            lastSeen: Date())

        onEvent(.connecting)
        tcpManager.connect(to: device) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let e):
                onEvent(.failed(e.localizedDescription))
            case .success:
                let msg = MessageProtocol.makeTransferRequest(
                    requestId: requestId, files: [meta],
                    deviceName: self.deviceName, deviceId: self.deviceId
                )
                self.tcpManager.send(msg, to: device.id)
                self.pendingTransfers[requestId] = (urls: [fileURL], deviceId: device.id)
                onEvent(.waitingApproval)
            }
        }
    }

    // MARK: - Receive

    func startReceiving(saveDirectory: URL, onEvent: @escaping (ReceiveEvent) -> Void) {
        self.saveDirectory    = saveDirectory
        self.onReceiveEvent   = onEvent
        tcpManager.startListening()
        discoveryService.start()
    }

    // MARK: - State

    private var pendingTransfers: [String: (urls: [URL], deviceId: UUID)] = [:]
}

// MARK: - DeviceDiscoveryDelegate

extension CLITransferCoordinator: DeviceDiscoveryDelegate {
    func discoveryService(_ service: DeviceDiscoveryService, didDiscover device: Device) {
        onDiscover?(device)
    }
    func discoveryService(_ service: DeviceDiscoveryService, didLose device: Device) {}
}

// MARK: - TCPConnectionDelegate

extension CLITransferCoordinator: TCPConnectionDelegate {
    func connectionManager(_ manager: TCPConnectionManager, didConnect device: Device) {}
    func connectionManager(_ manager: TCPConnectionManager, didDisconnect device: Device) {}

    func connectionManager(_ manager: TCPConnectionManager, didReceiveMessage message: Data, from device: Device) {
        switch MessageProtocol.decode(message) {

        // ── Sender side ────────────────────────────────────────────────
        case .transferResponse(let msg) where msg.approved:
            guard let (urls, devId) = pendingTransfers[msg.requestId] else { return }
            pendingTransfers.removeValue(forKey: msg.requestId)
            transferEngine.sendFiles(files: urls, requestId: msg.requestId, toDeviceId: devId)

        case .transferResponse(let msg):
            pendingTransfers.removeValue(forKey: msg.requestId)
            onSendEvent?(.rejected)

        case .chunkAck(let msg):
            transferEngine.handleChunkAck(msg)

        // ── Receiver side ──────────────────────────────────────────────
        case .transferRequest(let msg):
            let totalMB = Double(msg.files.reduce(0) { $0 + $1.size }) / 1_048_576
            // Call directly on whichever queue arrived — NOT main thread.
            // CLIController dispatches readLine() to stdinQueue separately.
            onReceiveEvent?(.incomingRequest(sender: msg.sourceDevice,
                                             files: msg.files,
                                             totalMB: totalMB) { [weak self] accepted in
                guard let self else { return }
                let response = MessageProtocol.makeTransferResponse(
                    requestId: msg.requestId, approved: accepted,
                    downloadPath: accepted ? self.saveDirectory?.path : nil
                )
                self.tcpManager.send(response, to: device.id)
                if accepted, let dir = self.saveDirectory {
                    // Set the directory so FileTransferEngine auto-registers on first chunk
                    self.transferEngine.receiveDirectory = dir
                }
            })

        case .fileChunk(let msg):
            transferEngine.handleIncomingChunk(msg, fromDeviceId: device.id)

        case .transferComplete(let msg):
            transferEngine.handleTransferComplete(msg)

        default: break
        }
    }
}

// MARK: - FileTransferEngineDelegate

extension CLITransferCoordinator: FileTransferEngineDelegate {
    func engine(_ engine: FileTransferEngine, didUpdateProgress progress: TransferProgress) {
        let event = SendEvent.progress(pct: progress.percentage, speed: progress.speedFormatted)
        DispatchQueue.main.async {
            self.onSendEvent?(event)
            self.onReceiveEvent?(.progress(pct: progress.percentage, speed: progress.speedFormatted))
        }
    }

    func engine(_ engine: FileTransferEngine, didCompleteTransfer requestId: String, fileId: String, success: Bool) {
        if success {
            onSendEvent?(SendEvent.completed(fileName: requestId))
            onReceiveEvent?(ReceiveEvent.completed(fileName: fileId))
        } else {
            onSendEvent?(SendEvent.failed("Transfer failed — checksum mismatch"))
            onReceiveEvent?(ReceiveEvent.failed("Checksum mismatch"))
        }
    }

    func engine(_ engine: FileTransferEngine, didReceiveChunkAck fileId: String, chunkNumber: Int) {}

    func engine(_ engine: FileTransferEngine, requiresSend message: Data, toDeviceId: UUID) {
        tcpManager.sendRaw(message, to: toDeviceId)
    }
}


