import Foundation

final class MessageProtocol {

    enum IncomingMessage {
        case handshake(HandshakeMessage)
        case transferRequest(TransferRequestMessage)
        case transferResponse(TransferResponseMessage)
        case fileChunk(FileChunkMessage)
        case chunkAck(ChunkAckMessage)
        case transferComplete(TransferCompleteMessage)
        case transferCancel(TransferControlMessage)
        case transferPause(TransferControlMessage)
        case transferResume(TransferControlMessage)
        case unknown
    }

    static func decode(_ data: Data) -> IncomingMessage {
        guard let w = try? JSONDecoder().decode(TypeWrapper.self, from: data) else { return .unknown }
        switch MessageType(rawValue: w.messageType) {
        case .handshake:
            if let m = try? JSONDecoder().decode(HandshakeMessage.self,        from: data) { return .handshake(m) }
        case .transferRequest:
            if let m = try? JSONDecoder().decode(TransferRequestMessage.self,  from: data) { return .transferRequest(m) }
        case .transferResponse:
            if let m = try? JSONDecoder().decode(TransferResponseMessage.self, from: data) { return .transferResponse(m) }
        case .fileChunk:
            if let m = try? JSONDecoder().decode(FileChunkMessage.self,        from: data) { return .fileChunk(m) }
        case .chunkAck:
            if let m = try? JSONDecoder().decode(ChunkAckMessage.self,         from: data) { return .chunkAck(m) }
        case .transferComplete:
            if let m = try? JSONDecoder().decode(TransferCompleteMessage.self, from: data) { return .transferComplete(m) }
        case .transferCancel, .transferPause, .transferResume:
            if let m = try? JSONDecoder().decode(TransferControlMessage.self, from: data) {
                switch MessageType(rawValue: w.messageType) {
                case .transferCancel: return .transferCancel(m)
                case .transferPause:  return .transferPause(m)
                default:              return .transferResume(m)
                }
            }
        default: break
        }
        return .unknown
    }

    // MARK: - Builders

    static func makeTransferRequest(requestId: String, files: [FileMetadata],
                                    deviceName: String, deviceId: String) -> TransferRequestMessage {
        TransferRequestMessage(messageType: MessageType.transferRequest.rawValue, requestId: requestId,
                               files: files, totalSize: files.reduce(0) { $0 + $1.size },
                               sourceDevice: deviceName, sourceDeviceId: deviceId)
    }

    static func makeTransferResponse(requestId: String, approved: Bool,
                                     downloadPath: String? = nil) -> TransferResponseMessage {
        TransferResponseMessage(messageType: MessageType.transferResponse.rawValue,
                                requestId: requestId, approved: approved, downloadPath: downloadPath)
    }

    static func makeFileChunk(fileId: String, requestId: String, chunkNumber: Int,
                               totalChunks: Int, data: Data, fileName: String) -> FileChunkMessage {
        FileChunkMessage(messageType: MessageType.fileChunk.rawValue, fileId: fileId,
                         requestId: requestId, chunkNumber: chunkNumber, totalChunks: totalChunks,
                         chunkSize: data.count, data: data.base64EncodedString(), fileName: fileName)
    }

    static func makeChunkAck(fileId: String, chunkNumber: Int) -> ChunkAckMessage {
        ChunkAckMessage(messageType: MessageType.chunkAck.rawValue,
                        fileId: fileId, chunkNumber: chunkNumber)
    }

    static func makeTransferComplete(fileId: String, requestId: String,
                                     checksum: String, success: Bool) -> TransferCompleteMessage {
        TransferCompleteMessage(messageType: MessageType.transferComplete.rawValue, fileId: fileId,
                                requestId: requestId, checksum: checksum,
                                status: success ? "success" : "failed")
    }
}

private struct TypeWrapper: Codable { let messageType: String }
