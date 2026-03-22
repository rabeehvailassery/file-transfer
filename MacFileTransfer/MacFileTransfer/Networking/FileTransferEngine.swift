import Foundation
import CryptoKit

protocol FileTransferEngineDelegate: AnyObject {
    func engine(_ engine: FileTransferEngine, didUpdateProgress progress: TransferProgress)
    func engine(_ engine: FileTransferEngine, didCompleteTransfer requestId: String, fileId: String, success: Bool)
    func engine(_ engine: FileTransferEngine, didReceiveChunkAck fileId: String, chunkNumber: Int)
    func engine(_ engine: FileTransferEngine, requiresSend message: Data, toDeviceId: UUID)
}

final class FileTransferEngine {

    static let chunkSize = 2 * 1024 * 1024   // 2 MB
    weak var delegate: FileTransferEngineDelegate?

    private var sendCheckpoints: [String: Int]  = [:]
    private var sendPaused:      [String: Bool] = [:]
    private var sendCancelled:   [String: Bool] = [:]
    private var receiveHandles:  [String: FileHandle] = [:]
    private var receivePaths:    [String: URL]  = [:]
    private var receiveDests:    [String: URL]  = [:]
    private var receiveProgress: [String: TransferProgress] = [:]
    private let queue = DispatchQueue(label: "com.filetransfer.engine", qos: .userInitiated)

    // MARK: - Send

    func sendFiles(files: [URL], requestId: String, toDeviceId: UUID) {
        queue.async {
            for url in files {
                guard !self.sendCancelled[requestId, default: false] else { break }
                self.sendFile(url: url, requestId: requestId, toDeviceId: toDeviceId)
            }
        }
    }

    private func sendFile(url: URL, requestId: String, toDeviceId: UUID) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return }
        let fileId      = UUID().uuidString
        let fileName    = url.lastPathComponent
        let totalChunks = Int(ceil(Double(data.count) / Double(Self.chunkSize)))
        let startChunk  = sendCheckpoints[fileId, default: 0]
        sendPaused[fileId] = false; sendCancelled[fileId] = false

        var progress = TransferProgress(requestId: requestId, fileId: fileId, fileName: fileName,
                                        totalBytes: Int64(data.count),
                                        transferredBytes: Int64(startChunk * Self.chunkSize))
        var lastUpdate = Date(); var bytesSince: Int64 = 0

        for chunkNum in startChunk..<totalChunks {
            while sendPaused[fileId, default: false] { Thread.sleep(forTimeInterval: 0.2) }
            guard !sendCancelled[fileId, default: false] else { return }

            let start = chunkNum * Self.chunkSize
            let end   = min(start + Self.chunkSize, data.count)
            let chunk = Data(data[start..<end])

            let msg = MessageProtocol.makeFileChunk(fileId: fileId, requestId: requestId,
                                                    chunkNumber: chunkNum, totalChunks: totalChunks,
                                                    data: chunk, fileName: fileName)
            guard let encoded = try? JSONEncoder().encode(msg) else { continue }
            var len = UInt32(encoded.count).bigEndian
            var pkt = Data(bytes: &len, count: 4); pkt.append(encoded)
            delegate?.engine(self, requiresSend: pkt, toDeviceId: toDeviceId)

            waitForAck(fileId: fileId, expectedChunk: chunkNum)

            bytesSince += Int64(chunk.count); progress.transferredBytes += Int64(chunk.count)
            let elapsed = Date().timeIntervalSince(lastUpdate)
            if elapsed >= 0.5 {
                progress.speedBytesPerSecond = Double(bytesSince) / elapsed
                bytesSince = 0; lastUpdate = Date()
            }
            DispatchQueue.main.async { self.delegate?.engine(self, didUpdateProgress: progress) }
        }

        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let complete = MessageProtocol.makeTransferComplete(fileId: fileId, requestId: requestId,
                                                            checksum: checksum, success: true)
        if let encoded = try? JSONEncoder().encode(complete) {
            var len = UInt32(encoded.count).bigEndian
            var pkt = Data(bytes: &len, count: 4); pkt.append(encoded)
            delegate?.engine(self, requiresSend: pkt, toDeviceId: toDeviceId)
        }
        sendCheckpoints.removeValue(forKey: fileId)
    }

    private func waitForAck(fileId: String, expectedChunk: Int) {
        let timeout = Date().addingTimeInterval(10)
        while sendCheckpoints[fileId, default: -1] < expectedChunk {
            if Date() > timeout || sendCancelled[fileId, default: false] { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    func handleChunkAck(_ msg: ChunkAckMessage) {
        sendCheckpoints[msg.fileId] = msg.chunkNumber
        delegate?.engine(self, didReceiveChunkAck: msg.fileId, chunkNumber: msg.chunkNumber)
    }

    func pauseSend(fileId: String)  { sendPaused[fileId]    = true  }
    func resumeSend(fileId: String) { sendPaused[fileId]    = false }
    func cancelSend(fileId: String) { sendCancelled[fileId] = true; sendPaused[fileId] = false }

    // MARK: - Receive

    func prepareReceive(fileId: String, fileName: String, totalBytes: Int64, destinationFolder: URL) {
        let tmpURL  = destinationFolder.appendingPathComponent(".\(fileId).tmp")
        let dstURL  = destinationFolder.appendingPathComponent(fileName)
        FileManager.default.createFile(atPath: tmpURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: tmpURL) else { return }
        receiveHandles[fileId]  = handle
        receivePaths[fileId]    = tmpURL
        receiveDests[fileId]    = dstURL
        receiveProgress[fileId] = TransferProgress(requestId: "", fileId: fileId,
                                                    fileName: fileName, totalBytes: totalBytes)
    }

    func handleIncomingChunk(_ msg: FileChunkMessage, fromDeviceId: UUID) {
        guard let chunkData = Data(base64Encoded: msg.data),
              let handle    = receiveHandles[msg.fileId] else { return }
        handle.seekToEndOfFile(); handle.write(chunkData)

        if var p = receiveProgress[msg.fileId] {
            p.transferredBytes += Int64(chunkData.count)
            let elapsed = Date().timeIntervalSince(p.startedAt)
            p.speedBytesPerSecond = elapsed > 0 ? Double(p.transferredBytes) / elapsed : 0
            receiveProgress[msg.fileId] = p
            DispatchQueue.main.async { self.delegate?.engine(self, didUpdateProgress: p) }
        }

        let ack = MessageProtocol.makeChunkAck(fileId: msg.fileId, chunkNumber: msg.chunkNumber)
        if let encoded = try? JSONEncoder().encode(ack) {
            var len = UInt32(encoded.count).bigEndian
            var pkt = Data(bytes: &len, count: 4); pkt.append(encoded)
            delegate?.engine(self, requiresSend: pkt, toDeviceId: fromDeviceId)
        }
    }

    func handleTransferComplete(_ msg: TransferCompleteMessage) {
        guard let handle = receiveHandles[msg.fileId],
              let tmpURL = receivePaths[msg.fileId],
              let dstURL = receiveDests[msg.fileId] else { return }
        handle.closeFile()

        guard let data = try? Data(contentsOf: tmpURL) else {
            finalize(fileId: msg.fileId, success: false, requestId: msg.requestId); return
        }
        let computed = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if computed == msg.checksum { try? FileManager.default.moveItem(at: tmpURL, to: dstURL) }
        else                        { try? FileManager.default.removeItem(at: tmpURL) }
        finalize(fileId: msg.fileId, success: computed == msg.checksum, requestId: msg.requestId)
    }

    private func finalize(fileId: String, success: Bool, requestId: String) {
        receiveHandles.removeValue(forKey: fileId); receivePaths.removeValue(forKey: fileId)
        receiveDests.removeValue(forKey: fileId);   receiveProgress.removeValue(forKey: fileId)
        DispatchQueue.main.async {
            self.delegate?.engine(self, didCompleteTransfer: requestId, fileId: fileId, success: success)
        }
    }
}
