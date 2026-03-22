import Foundation
import Network

protocol DeviceDiscoveryDelegate: AnyObject {
    func discoveryService(_ service: DeviceDiscoveryService, didDiscover device: Device)
    func discoveryService(_ service: DeviceDiscoveryService, didLose device: Device)
}

final class DeviceDiscoveryService {

    static let udpPort: UInt16          = 5354
    static let tcpPort: UInt16          = 5355
    static let broadcastInterval: TimeInterval = 30
    static let deviceExpiry: TimeInterval      = 60
    static let appVersion               = "1.0"

    weak var delegate: DeviceDiscoveryDelegate?
    private(set) var discoveredDevices: [UUID: Device] = [:]

    private var udpListener:    NWListener?
    private var broadcastTimer: Timer?
    private var expiryTimer:    Timer?

    private let deviceId:   String
    private let deviceName: String
    private let queue = DispatchQueue(label: "com.filetransfer.discovery", qos: .utility)

    init() {
        deviceId   = Self.loadOrCreateDeviceId()
        deviceName = Host.current().localizedName ?? "Mac"
    }

    // MARK: - Start / Stop

    func start() { setupUDPListener(); startBroadcastTimer(); startExpiryTimer() }

    func stop() {
        udpListener?.cancel();   udpListener   = nil
        broadcastTimer?.invalidate(); broadcastTimer = nil
        expiryTimer?.invalidate();    expiryTimer    = nil
    }

    // MARK: - UDP Listener

    private func setupUDPListener() {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        guard let port     = NWEndpoint.Port(rawValue: Self.udpPort),
              let listener = try? NWListener(using: params, on: port) else { return }
        udpListener = listener
        listener.newConnectionHandler = { [weak self] conn in
            conn.start(queue: self?.queue ?? .global())
            conn.receiveMessage { data, _, _, _ in
                if let data, !data.isEmpty { self?.handleBroadcast(data: data, from: conn) }
            }
        }
        listener.start(queue: queue)
    }

    private func handleBroadcast(data: Data, from conn: NWConnection) {
        guard let msg  = try? JSONDecoder().decode(DeviceDiscoveryMessage.self, from: data),
              msg.messageType == MessageType.deviceDiscovery.rawValue,
              msg.deviceId != deviceId,
              let uuid = UUID(uuidString: msg.deviceId),
              let type = Device.DeviceType(rawValue: msg.deviceType) else { return }

        var ip = "Unknown"
        if case .hostPort(let h, _) = conn.endpoint { ip = "\(h)" }

        let device = Device(id: uuid, name: msg.deviceName, type: type,
                            ipAddress: ip, listeningPort: msg.listeningPort, lastSeen: Date())
        let isNew = discoveredDevices[uuid] == nil
        discoveredDevices[uuid] = device
        if isNew { DispatchQueue.main.async { self.delegate?.discoveryService(self, didDiscover: device) } }
    }

    // MARK: - Broadcast

    private func startBroadcastTimer() {
        broadcastMessage()
        broadcastTimer = Timer.scheduledTimer(withTimeInterval: Self.broadcastInterval,
                                              repeats: true) { [weak self] _ in self?.broadcastMessage() }
    }

    func broadcastMessage() {
        let msg = DeviceDiscoveryMessage(
            messageType: MessageType.deviceDiscovery.rawValue,
            deviceName: deviceName, deviceType: Device.DeviceType.mac.rawValue,
            listeningPort: Int(Self.tcpPort),
            timestamp: Date().timeIntervalSince1970,
            deviceId: deviceId
        )
        guard let data = try? JSONEncoder().encode(msg) else { return }
        let conn = NWConnection(host: "255.255.255.255",
                                port: NWEndpoint.Port(rawValue: Self.udpPort)!, using: .udp)
        conn.start(queue: queue)
        conn.send(content: data, completion: .contentProcessed { _ in conn.cancel() })
    }

    // MARK: - Expiry

    private func startExpiryTimer() {
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Date()
            let expired = self.discoveredDevices.filter { now.timeIntervalSince($0.value.lastSeen) > Self.deviceExpiry }
            for (id, dev) in expired {
                self.discoveredDevices.removeValue(forKey: id)
                DispatchQueue.main.async { self.delegate?.discoveryService(self, didLose: dev) }
            }
        }
    }

    // MARK: - Manual IP

    func addDeviceManually(ip: String, port: Int, name: String, type: Device.DeviceType = .android) {
        let device = Device(id: UUID(), name: name, type: type,
                            ipAddress: ip, listeningPort: port, lastSeen: Date())
        discoveredDevices[device.id] = device
        DispatchQueue.main.async { self.delegate?.discoveryService(self, didDiscover: device) }
    }

    // MARK: - Helpers

    static func loadOrCreateDeviceId() -> String {
        let key = "com.filetransfer.deviceId"
        if let v = UserDefaults.standard.string(forKey: key) { return v }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }
}
