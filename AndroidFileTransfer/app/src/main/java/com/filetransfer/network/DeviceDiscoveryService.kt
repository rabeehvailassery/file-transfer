package com.filetransfer.network

import android.content.Context
import android.net.wifi.WifiManager
import com.filetransfer.model.Device
import kotlinx.coroutines.*
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.UUID
import java.util.prefs.Preferences  // NOTE: use SharedPreferences below

private const val UDP_PORT        = 5354
private const val TCP_PORT        = 5355
private const val BROADCAST_INTERVAL_MS = 30_000L
private const val DEVICE_EXPIRY_MS      = 60_000L
private const val APP_VERSION     = "1.0"

interface DeviceDiscoveryListener {
    fun onDeviceDiscovered(device: Device)
    fun onDeviceLost(device: Device)
}

class DeviceDiscoveryService(private val context: Context) {

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val discoveredDevices = mutableMapOf<UUID, Device>()
    private var udpSocket: DatagramSocket? = null
    var listener: DeviceDiscoveryListener? = null

    val deviceId: String by lazy { loadOrCreateDeviceId() }
    val deviceName: String by lazy { android.os.Build.MODEL }

    fun start() {
        scope.launch { listenForBroadcasts() }
        scope.launch { broadcastLoop() }
        scope.launch { expiryLoop() }
    }

    fun stop() {
        scope.cancel()
        udpSocket?.close()
        udpSocket = null
    }

    /** Get snapshot of currently known devices */
    fun getDevices(): List<Device> = synchronized(discoveredDevices) {
        discoveredDevices.values.toList()
    }

    fun broadcastNow() { scope.launch { sendBroadcast() } }

    fun addManually(ip: String, port: Int = TCP_PORT, name: String = "Mac") {
        val dev = Device(UUID.randomUUID(), name, Device.DeviceType.MAC, ip, port)
        synchronized(discoveredDevices) { discoveredDevices[dev.id] = dev }
        listener?.onDeviceDiscovered(dev)
    }

    // MARK: - Private

    private suspend fun listenForBroadcasts() {
        try {
            val socket = DatagramSocket(UDP_PORT).also { udpSocket = it }
            socket.broadcast = true
            val buf = ByteArray(4096)
            while (true) {
                val pkt = DatagramPacket(buf, buf.size)
                socket.receive(pkt)
                val json = String(pkt.data, 0, pkt.length)
                val msg = try { MessageProtocol.decode(
                    // DeviceDiscoveryMessage comes over UDP without framing
                    json) } catch (_: Exception) { continue }
                if (msg is IncomingMessage.Unknown) {
                    // Try direct parse as DeviceDiscoveryMessage
                    handleDiscovery(json, pkt.address.hostAddress ?: continue)
                }
            }
        } catch (_: Exception) {}
    }

    private fun handleDiscovery(json: String, fromIp: String) {
        try {
            val msg = com.google.gson.Gson().fromJson(json, DeviceDiscoveryMessage::class.java)
            if (msg.messageType != MessageType.DEVICE_DISCOVERY) return
            if (msg.deviceId == deviceId) return   // our own broadcast
            val uuid = UUID.fromString(msg.deviceId)
            val type = Device.DeviceType.from(msg.deviceType)
            val device = Device(uuid, msg.deviceName, type, fromIp, msg.listeningPort)
            val isNew = synchronized(discoveredDevices) {
                val new = !discoveredDevices.containsKey(uuid)
                discoveredDevices[uuid] = device; new
            }
            if (isNew) listener?.onDeviceDiscovered(device)
        } catch (_: Exception) {}
    }

    private suspend fun broadcastLoop() {
        while (true) {
            sendBroadcast()
            delay(BROADCAST_INTERVAL_MS)
        }
    }

    private fun sendBroadcast() {
        try {
            val msg = DeviceDiscoveryMessage(
                deviceName   = deviceName,
                deviceType   = Device.DeviceType.ANDROID.raw,
                listeningPort = TCP_PORT,
                timestamp    = System.currentTimeMillis() / 1000.0,
                deviceId     = deviceId
            )
            val json  = MessageProtocol.toJson(msg).toByteArray()
            // Acquire multicast lock so broadcasts work on Android
            val wifiMgr = context.applicationContext
                .getSystemService(Context.WIFI_SERVICE) as WifiManager
            val lock = wifiMgr.createMulticastLock("filetransfer").also { it.acquire() }
            val socket = DatagramSocket()
            socket.broadcast = true
            socket.send(DatagramPacket(json, json.size,
                InetAddress.getByName("255.255.255.255"), UDP_PORT))
            socket.close()
            lock.release()
        } catch (_: Exception) {}
    }

    private suspend fun expiryLoop() {
        while (true) {
            delay(15_000L)
            val expired = synchronized(discoveredDevices) {
                val now = System.currentTimeMillis()
                discoveredDevices.entries
                    .filter { now - it.value.lastSeen > DEVICE_EXPIRY_MS }
                    .map { it.key to it.value }
                    .also { list -> list.forEach { discoveredDevices.remove(it.first) } }
            }
            expired.forEach { (_, dev) -> listener?.onDeviceLost(dev) }
        }
    }

    private fun loadOrCreateDeviceId(): String {
        val prefs = context.getSharedPreferences("filetransfer", Context.MODE_PRIVATE)
        return prefs.getString("deviceId", null) ?: UUID.randomUUID().toString().also {
            prefs.edit().putString("deviceId", it).apply()
        }
    }
}
