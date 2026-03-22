package com.filetransfer.network

import com.filetransfer.model.Device
import kotlinx.coroutines.*
import java.io.DataInputStream
import java.io.OutputStream
import java.net.ServerSocket
import java.net.Socket
import java.util.UUID

private const val TCP_PORT = 5355

interface TCPConnectionListener {
    fun onConnected(device: Device)
    fun onDisconnected(device: Device)
    fun onMessageReceived(data: String, from: Device)
}

class TCPConnectionManager(
    private val deviceId: String,
    private val deviceName: String
) {
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val connections = mutableMapOf<UUID, Pair<Socket, Device>>()
    private var serverSocket: ServerSocket? = null
    var listener: TCPConnectionListener? = null

    // MARK: - Listen

    fun startListening() {
        scope.launch {
            try {
                val ss = ServerSocket(TCP_PORT).also { serverSocket = it }
                while (true) {
                    val client = ss.accept()
                    launch { handleIncoming(client) }
                }
            } catch (_: Exception) {}
        }
    }

    fun stopListening() { serverSocket?.close(); serverSocket = null }

    // MARK: - Connect

    suspend fun connect(device: Device): Boolean = withContext(Dispatchers.IO) {
        try {
            val socket = Socket(device.ipAddress, device.listeningPort)
            connections[device.id] = socket to device
            sendHandshake(socket.getOutputStream())
            scope.launch { receiveLoop(socket, device) }
            true
        } catch (_: Exception) { false }
    }

    // MARK: - Send

    fun send(message: Any, toDeviceId: UUID) {
        val (socket, _) = connections[toDeviceId] ?: return
        scope.launch(Dispatchers.IO) {
            try {
                val framed = MessageProtocol.frame(MessageProtocol.toJson(message))
                socket.getOutputStream().write(framed)
                socket.getOutputStream().flush()
            } catch (_: Exception) {}
        }
    }

    fun sendRaw(data: ByteArray, toDeviceId: UUID) {
        val (socket, _) = connections[toDeviceId] ?: return
        scope.launch(Dispatchers.IO) {
            try { socket.getOutputStream().write(data); socket.getOutputStream().flush() }
            catch (_: Exception) {}
        }
    }

    fun disconnect(deviceId: UUID) {
        connections.remove(deviceId)?.first?.close()
    }

    // MARK: - Private

    private fun sendHandshake(out: OutputStream) {
        val hs = MessageProtocol.makeHandshake(deviceName, deviceId)
        val framed = MessageProtocol.frame(MessageProtocol.toJson(hs))
        out.write(framed); out.flush()
    }

    private suspend fun handleIncoming(socket: Socket) {
        try {
            receiveLoop(socket, null)
        } catch (_: Exception) { socket.close() }
    }

    private suspend fun receiveLoop(socket: Socket, knownDevice: Device?) {
        var device = knownDevice
        try {
            val stream = DataInputStream(socket.getInputStream())
            while (true) {
                // Read 4-byte big-endian length
                val len = stream.readInt()
                if (len <= 0 || len > 10 * 1024 * 1024) break
                val body = ByteArray(len)
                stream.readFully(body)
                val json = String(body, Charsets.UTF_8)

                if (device == null) {
                    // Expect handshake first
                    val msg = MessageProtocol.decode(json)
                    if (msg is IncomingMessage.Handshake) {
                        val hs = msg.msg
                        val uuid = UUID.fromString(hs.deviceId)
                        val type = Device.DeviceType.from(hs.deviceType)
                        device = Device(uuid, hs.deviceName, type, socket.inetAddress.hostAddress ?: "", TCP_PORT)
                        connections[uuid] = socket to device
                        withContext(Dispatchers.Main) { listener?.onConnected(device) }
                    }
                } else {
                    val d = device
                    withContext(Dispatchers.Main) { listener?.onMessageReceived(json, d) }
                }
            }
        } catch (_: Exception) {}
        device?.let {
            connections.remove(it.id)
            withContext(Dispatchers.Main) { listener?.onDisconnected(it) }
        }
        socket.close()
    }
}
