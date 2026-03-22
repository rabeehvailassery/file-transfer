import Foundation
import Network

protocol TCPConnectionDelegate: AnyObject {
    func connectionManager(_ manager: TCPConnectionManager, didConnect device: Device)
    func connectionManager(_ manager: TCPConnectionManager, didDisconnect device: Device)
    func connectionManager(_ manager: TCPConnectionManager, didReceiveMessage message: Data, from device: Device)
}

final class TCPConnectionManager {

    weak var delegate: TCPConnectionDelegate?

    private var listener: NWListener?
    private var activeConnections: [UUID: (connection: NWConnection, device: Device)] = [:]
    private let queue = DispatchQueue(label: "com.filetransfer.tcp", qos: .userInitiated)
    private let deviceId:   String
    private let deviceName: String
    private let port:       NWEndpoint.Port

    init(port: UInt16 = DeviceDiscoveryService.tcpPort) {
        deviceId   = UserDefaults.standard.string(forKey: "com.filetransfer.deviceId") ?? UUID().uuidString
        deviceName = Host.current().localizedName ?? "Mac"
        self.port  = NWEndpoint.Port(rawValue: port)!
    }

    // MARK: - Listen

    func startListening() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: params, on: port) else { return }
        self.listener = listener
        listener.newConnectionHandler  = { [weak self] conn in self?.handleIncoming(conn) }
        listener.stateUpdateHandler    = { state in
            if case .ready = state { print("[TCP] Listening on \(DeviceDiscoveryService.tcpPort)") }
        }
        listener.start(queue: queue)
    }

    func stopListening() { listener?.cancel(); listener = nil }

    // MARK: - Connect

    func connect(to device: Device, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let p = NWEndpoint.Port(rawValue: UInt16(device.listeningPort)) else {
            completion(.failure(TransferError.invalidPort)); return
        }
        let conn = NWConnection(host: .init(device.ipAddress), port: p, using: .tcp)
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.activeConnections[device.id] = (conn, device)
                self.performHandshake(on: conn)
                self.startReceiving(from: conn, device: device)
                completion(.success(()))
            case .failed(let e): completion(.failure(e))
            case .cancelled:
                self.activeConnections.removeValue(forKey: device.id)
                DispatchQueue.main.async { self.delegate?.connectionManager(self, didDisconnect: device) }
            default: break
            }
        }
        conn.start(queue: queue)
    }

    // MARK: - Send

    func send<T: Encodable>(_ message: T, to id: UUID) {
        guard let (conn, _) = activeConnections[id],
              let data = try? JSONEncoder().encode(message) else { return }
        var len = UInt32(data.count).bigEndian
        var pkt = Data(bytes: &len, count: 4); pkt.append(data)
        conn.send(content: pkt, completion: .contentProcessed { _ in })
    }

    /// Send pre-framed bytes directly (used by FileTransferEngine for chunks/acks).
    func sendRaw(_ data: Data, to id: UUID) {
        guard let (conn, _) = activeConnections[id] else { return }
        conn.send(content: data, completion: .contentProcessed { _ in })
    }

    // MARK: - Private

    private func performHandshake(on conn: NWConnection) {
        let hs = HandshakeMessage(messageType: MessageType.handshake.rawValue,
                                  deviceName: deviceName, deviceType: Device.DeviceType.mac.rawValue,
                                  deviceId: deviceId, version: DeviceDiscoveryService.appVersion)
        guard let data = try? JSONEncoder().encode(hs) else { return }
        var len = UInt32(data.count).bigEndian
        var pkt = Data(bytes: &len, count: 4); pkt.append(data)
        conn.send(content: pkt, completion: .contentProcessed { _ in })
    }

    private func handleIncoming(_ conn: NWConnection) {
        conn.stateUpdateHandler = { [weak self] state in
            if case .ready = state { self?.startReceiving(from: conn, device: nil) }
        }
        conn.start(queue: queue)
    }

    private func startReceiving(from conn: NWConnection, device: Device?) {
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self, let data, data.count == 4, error == nil else { return }
            let length = Int(UInt32(bigEndian: data.withUnsafeBytes { $0.load(as: UInt32.self) }))
            conn.receive(minimumIncompleteLength: length, maximumLength: length) { body, _, _, err in
                guard let body, err == nil else { return }
                var resolved = device
                if resolved == nil,
                   let hs   = TCPConnectionManager.decodeHandshake(from: body),
                   let uuid = UUID(uuidString: hs.deviceId),
                   let type = Device.DeviceType(rawValue: hs.deviceType) {
                    var ip = "Unknown"
                    if case .hostPort(let h, _) = conn.endpoint { ip = "\(h)" }
                    let dev = Device(id: uuid, name: hs.deviceName, type: type,
                                     ipAddress: ip, listeningPort: Int(DeviceDiscoveryService.tcpPort), lastSeen: Date())
                    resolved = dev
                    self.activeConnections[uuid] = (conn, dev)
                    DispatchQueue.main.async { self.delegate?.connectionManager(self, didConnect: dev) }
                } else if let dev = resolved {
                    DispatchQueue.main.async { self.delegate?.connectionManager(self, didReceiveMessage: body, from: dev) }
                }
                self.startReceiving(from: conn, device: resolved)
            }
        }
    }

    /// Nonisolated helper so the decode call is safe on any background queue (Swift 6 concurrency).
    private nonisolated static func decodeHandshake(from data: Data) -> HandshakeMessage? {
        guard let hs = try? JSONDecoder().decode(HandshakeMessage.self, from: data),
              hs.messageType == MessageType.handshake.rawValue else { return nil }
        return hs
    }
}

// MARK: - Errors

enum TransferError: LocalizedError {
    case noConnection, invalidPort, checksumMismatch, transferRejected, chunkDecodingFailure
    case fileWriteFailure(String)
    var errorDescription: String? {
        switch self {
        case .noConnection:          return "No active connection to device."
        case .invalidPort:           return "Invalid TCP port."
        case .checksumMismatch:      return "Integrity check failed — file may be corrupted."
        case .transferRejected:      return "Transfer rejected by receiving device."
        case .chunkDecodingFailure:  return "Failed to decode a file chunk."
        case .fileWriteFailure(let p): return "Failed to write file at \(p)"
        }
    }
}
