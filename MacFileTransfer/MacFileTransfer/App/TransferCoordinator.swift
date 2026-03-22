import Foundation
import AppKit

final class TransferCoordinator {

    let discoveryService = DeviceDiscoveryService()
    let tcpManager       = TCPConnectionManager()
    let transferEngine   = FileTransferEngine()
    let queue            = TransferQueue()

    private let deviceId   = UserDefaults.standard.string(forKey: "com.filetransfer.deviceId") ?? UUID().uuidString
    private let deviceName = Host.current().localizedName ?? "Mac"
    private var pendingUrls: [String: ([URL], UUID)] = [:]

    init() {
        tcpManager.delegate       = self
        discoveryService.delegate = self
        transferEngine.delegate   = self
    }

    func start() { tcpManager.startListening(); discoveryService.start() }
    func stop()  { tcpManager.stopListening();  discoveryService.stop()  }

    func initiateTransfer(urls: [URL], toDevice: Device) {
        let fileMetas = urls.compactMap { url -> FileMetadata? in
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size  = attrs[.size] as? Int64 else { return nil }
            return FileMetadata(name: url.lastPathComponent, size: size, mimeType: mimeType(for: url))
        }
        let requestId    = UUID().uuidString
        let sourceDevice = Device(id: UUID(uuidString: deviceId) ?? UUID(), name: deviceName,
                                  type: .mac, ipAddress: "local",
                                  listeningPort: Int(DeviceDiscoveryService.tcpPort), lastSeen: Date())
        queue.enqueue(TransferItem(requestId: requestId, sourceDevice: sourceDevice, files: fileMetas))
        pendingUrls[requestId] = (urls, toDevice.id)

        tcpManager.connect(to: toDevice) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                let msg = MessageProtocol.makeTransferRequest(requestId: requestId, files: fileMetas,
                                                             deviceName: self.deviceName, deviceId: self.deviceId)
                self.tcpManager.send(msg, to: toDevice.id)
            case .failure(let e):
                print("[Coordinator] Connect failed: \(e)")
                self.queue.updateStatus(.failed, forRequestId: requestId)
                self.pendingUrls.removeValue(forKey: requestId)
            }
        }
    }
}

// MARK: - TCPConnectionDelegate

extension TransferCoordinator: TCPConnectionDelegate {
    func connectionManager(_ manager: TCPConnectionManager, didConnect device: Device) {
        NotificationCenter.default.post(name: .devicesDidChange, object: nil)
    }
    func connectionManager(_ manager: TCPConnectionManager, didDisconnect device: Device) {}

    func connectionManager(_ manager: TCPConnectionManager, didReceiveMessage message: Data, from device: Device) {
        switch MessageProtocol.decode(message) {
        case .transferResponse(let msg) where msg.approved:
            queue.updateStatus(.active, forRequestId: msg.requestId)
            if let (urls, _) = pendingUrls[msg.requestId] {
                transferEngine.sendFiles(files: urls, requestId: msg.requestId, toDeviceId: device.id)
                pendingUrls.removeValue(forKey: msg.requestId)
            }
        case .transferResponse(let msg):
            queue.updateStatus(.rejected, forRequestId: msg.requestId)
            pendingUrls.removeValue(forKey: msg.requestId)
        case .transferRequest(let msg):
            let src = Device(id: UUID(uuidString: msg.sourceDeviceId) ?? UUID(),
                             name: msg.sourceDevice, type: .android,
                             ipAddress: device.ipAddress, listeningPort: device.listeningPort, lastSeen: Date())
            let req = FileTransferRequest(id: UUID(), requestId: msg.requestId,
                                          sourceDevice: src, files: msg.files, status: .pending)
            queue.enqueue(TransferItem(requestId: msg.requestId, sourceDevice: src, files: msg.files))
            showApprovalPrompt(for: req, fromDeviceId: device.id)
        case .fileChunk(let msg):        transferEngine.handleIncomingChunk(msg, fromDeviceId: device.id)
        case .chunkAck(let msg):         transferEngine.handleChunkAck(msg)
        case .transferComplete(let msg): transferEngine.handleTransferComplete(msg)
        case .transferCancel(let msg):
            transferEngine.cancelSend(fileId: msg.fileId ?? msg.requestId)
            queue.updateStatus(.cancelled, forRequestId: msg.requestId)
        case .transferPause(let msg):
            transferEngine.pauseSend(fileId: msg.fileId ?? msg.requestId)
            queue.updateStatus(.paused, forRequestId: msg.requestId)
        case .transferResume(let msg):
            transferEngine.resumeSend(fileId: msg.fileId ?? msg.requestId)
            queue.updateStatus(.active, forRequestId: msg.requestId)
        default: break
        }
    }

    private func showApprovalPrompt(for request: FileTransferRequest, fromDeviceId: UUID) {
        DispatchQueue.main.async {
            guard let wc = NSApp.mainWindow?.windowController else { return }
            let vc = ApprovalPromptViewController()
            vc.request    = request
            vc.onDecision = { [weak self] approved in
                guard let self else { return }
                let dl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                let response = MessageProtocol.makeTransferResponse(
                    requestId: request.requestId, approved: approved,
                    downloadPath: approved ? dl?.path : nil
                )
                self.tcpManager.send(response, to: fromDeviceId)
                if approved {
                    for file in request.files {
                        self.transferEngine.prepareReceive(fileId: UUID().uuidString, fileName: file.name,
                                                           totalBytes: file.size, destinationFolder: dl!)
                    }
                    self.queue.updateStatus(.active, forRequestId: request.requestId)
                } else {
                    self.queue.updateStatus(.rejected, forRequestId: request.requestId)
                }
            }
            wc.contentViewController?.presentAsSheet(vc)
        }
    }
}

// MARK: - DeviceDiscoveryDelegate

extension TransferCoordinator: DeviceDiscoveryDelegate {
    func discoveryService(_ service: DeviceDiscoveryService, didDiscover device: Device) {
        NotificationCenter.default.post(name: .devicesDidChange, object: nil)
    }
    func discoveryService(_ service: DeviceDiscoveryService, didLose device: Device) {
        NotificationCenter.default.post(name: .devicesDidChange, object: nil)
    }
}

// MARK: - FileTransferEngineDelegate

extension TransferCoordinator: FileTransferEngineDelegate {
    func engine(_ e: FileTransferEngine, didUpdateProgress progress: TransferProgress) {
        queue.updateProgress(progress)
    }
    func engine(_ e: FileTransferEngine, didCompleteTransfer requestId: String, fileId: String, success: Bool) {
        queue.updateStatus(success ? .completed : .failed, forRequestId: requestId)
    }
    func engine(_ e: FileTransferEngine, didReceiveChunkAck fileId: String, chunkNumber: Int) {}
    func engine(_ e: FileTransferEngine, requiresSend message: Data, toDeviceId: UUID) {}
}

// MARK: - Helper

private func mimeType(for url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "jpg","jpeg": return "image/jpeg"
    case "png":  return "image/png"
    case "mp4":  return "video/mp4"
    case "mov":  return "video/quicktime"
    case "pdf":  return "application/pdf"
    case "zip":  return "application/zip"
    default:     return "application/octet-stream"
    }
}
