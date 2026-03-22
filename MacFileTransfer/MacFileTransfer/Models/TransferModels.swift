import Foundation

// MARK: - Device

struct Device: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var type: DeviceType
    var ipAddress: String
    var listeningPort: Int
    var lastSeen: Date

    var isActive: Bool { Date().timeIntervalSince(lastSeen) < 60 }

    enum DeviceType: String, Codable, Sendable {
        case mac     = "Mac"
        case android = "Android"
    }
}

// MARK: - FileTransferRequest

struct FileTransferRequest: Identifiable {
    let id: UUID
    let requestId: String
    let sourceDevice: Device
    let files: [FileMetadata]
    var status: TransferStatus
    let createdAt: Date = Date()
    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
}

struct FileMetadata: Codable, Sendable {
    let name: String
    let size: Int64
    let mimeType: String
}

enum TransferStatus: String, Sendable {
    case pending, active, paused, completed, rejected, failed, cancelled
}

// MARK: - Protocol Messages

enum MessageType: String, Codable, Sendable {
    case deviceDiscovery  = "DEVICE_DISCOVERY"
    case transferRequest  = "TRANSFER_REQUEST"
    case transferResponse = "TRANSFER_RESPONSE"
    case fileChunk        = "FILE_CHUNK"
    case chunkAck         = "CHUNK_ACK"
    case transferComplete = "TRANSFER_COMPLETE"
    case transferCancel   = "TRANSFER_CANCEL"
    case transferPause    = "TRANSFER_PAUSE"
    case transferResume   = "TRANSFER_RESUME"
    case handshake        = "HANDSHAKE"
}

struct DeviceDiscoveryMessage: Codable, Sendable {
    let messageType: String
    let deviceName: String
    let deviceType: String
    let listeningPort: Int
    let timestamp: TimeInterval
    let deviceId: String
}

struct HandshakeMessage: Encodable, Sendable {
    let messageType: String
    let deviceName: String
    let deviceType: String
    let deviceId: String
    let version: String

    // Explicit nonisolated Decodable so it can be called from background NWConnection queues
    // without triggering Swift actor-isolation warnings.
    enum CodingKeys: String, CodingKey {
        case messageType, deviceName, deviceType, deviceId, version
    }
}

extension HandshakeMessage: Decodable {
    nonisolated init(from decoder: Decoder) throws {
        let c        = try decoder.container(keyedBy: CodingKeys.self)
        messageType  = try c.decode(String.self, forKey: .messageType)
        deviceName   = try c.decode(String.self, forKey: .deviceName)
        deviceType   = try c.decode(String.self, forKey: .deviceType)
        deviceId     = try c.decode(String.self, forKey: .deviceId)
        version      = try c.decode(String.self, forKey: .version)
    }
}

struct TransferRequestMessage: Codable, Sendable {
    let messageType: String
    let requestId: String
    let files: [FileMetadata]
    let totalSize: Int64
    let sourceDevice: String
    let sourceDeviceId: String
}

struct TransferResponseMessage: Codable, Sendable {
    let messageType: String
    let requestId: String
    let approved: Bool
    let downloadPath: String?
}

struct FileChunkMessage: Codable, Sendable {
    let messageType: String
    let fileId: String
    let requestId: String
    let chunkNumber: Int
    let totalChunks: Int
    let chunkSize: Int
    let data: String   // Base64-encoded
    let fileName: String
}

struct ChunkAckMessage: Codable, Sendable {
    let messageType: String
    let fileId: String
    let chunkNumber: Int
}

struct TransferCompleteMessage: Codable, Sendable {
    let messageType: String
    let fileId: String
    let requestId: String
    let checksum: String   // SHA-256
    let status: String
}

struct TransferControlMessage: Codable, Sendable {
    let messageType: String
    let requestId: String
    let fileId: String?
}

// MARK: - TransferProgress

struct TransferProgress: Sendable {
    let requestId: String
    let fileId: String
    let fileName: String
    let totalBytes: Int64
    var transferredBytes: Int64  = 0
    var speedBytesPerSecond: Double = 0
    var startedAt: Date          = Date()

    var percentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(transferredBytes) / Double(totalBytes) * 100
    }

    var estimatedTimeRemaining: TimeInterval? {
        guard speedBytesPerSecond > 0 else { return nil }
        return Double(totalBytes - transferredBytes) / speedBytesPerSecond
    }

    var speedFormatted: String {
        String(format: "%.1f MB/s", speedBytesPerSecond / 1_048_576)
    }
}
