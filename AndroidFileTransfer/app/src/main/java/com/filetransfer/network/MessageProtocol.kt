package com.filetransfer.network

import com.filetransfer.model.FileMetadata
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.JsonParser

// ── Message type constants (must match Mac) ─────────────────────────────────
object MessageType {
    const val DEVICE_DISCOVERY  = "DEVICE_DISCOVERY"
    const val TRANSFER_REQUEST  = "TRANSFER_REQUEST"
    const val TRANSFER_RESPONSE = "TRANSFER_RESPONSE"
    const val FILE_CHUNK        = "FILE_CHUNK"
    const val CHUNK_ACK         = "CHUNK_ACK"
    const val TRANSFER_COMPLETE = "TRANSFER_COMPLETE"
    const val TRANSFER_CANCEL   = "TRANSFER_CANCEL"
    const val TRANSFER_PAUSE    = "TRANSFER_PAUSE"
    const val TRANSFER_RESUME   = "TRANSFER_RESUME"
    const val HANDSHAKE         = "HANDSHAKE"
}

// ── JSON message data classes ────────────────────────────────────────────────

data class DeviceDiscoveryMessage(
    val messageType: String = MessageType.DEVICE_DISCOVERY,
    val deviceName: String,
    val deviceType: String,
    val listeningPort: Int,
    val timestamp: Double,
    val deviceId: String
)

data class HandshakeMessage(
    val messageType: String = MessageType.HANDSHAKE,
    val deviceName: String,
    val deviceType: String,
    val deviceId: String,
    val version: String = "1.0"
)

data class TransferRequestMessage(
    val messageType: String = MessageType.TRANSFER_REQUEST,
    val requestId: String,
    val files: List<FileMetadata>,
    val totalSize: Long,
    val sourceDevice: String,
    val sourceDeviceId: String
)

data class TransferResponseMessage(
    val messageType: String = MessageType.TRANSFER_RESPONSE,
    val requestId: String,
    val approved: Boolean,
    val downloadPath: String? = null
)

data class FileChunkMessage(
    val messageType: String = MessageType.FILE_CHUNK,
    val fileId: String,
    val requestId: String,
    val chunkNumber: Int,
    val totalChunks: Int,
    val chunkSize: Int,
    val data: String,       // Base64
    val fileName: String
)

data class ChunkAckMessage(
    val messageType: String = MessageType.CHUNK_ACK,
    val fileId: String,
    val chunkNumber: Int
)

data class TransferCompleteMessage(
    val messageType: String = MessageType.TRANSFER_COMPLETE,
    val fileId: String,
    val requestId: String,
    val checksum: String,   // SHA-256 hex
    val status: String
)

data class TransferControlMessage(
    val messageType: String,
    val requestId: String,
    val fileId: String? = null
)

// ── Decode ───────────────────────────────────────────────────────────────────

sealed class IncomingMessage {
    data class Handshake(val msg: HandshakeMessage) : IncomingMessage()
    data class TransferRequest(val msg: TransferRequestMessage) : IncomingMessage()
    data class TransferResponse(val msg: TransferResponseMessage) : IncomingMessage()
    data class FileChunk(val msg: FileChunkMessage) : IncomingMessage()
    data class ChunkAck(val msg: ChunkAckMessage) : IncomingMessage()
    data class TransferComplete(val msg: TransferCompleteMessage) : IncomingMessage()
    data class TransferControl(val type: String, val msg: TransferControlMessage) : IncomingMessage()
    object Unknown : IncomingMessage()
}

object MessageProtocol {
    private val gson = Gson()

    fun decode(json: String): IncomingMessage {
        return try {
            val obj: JsonObject = JsonParser.parseString(json).asJsonObject
            when (val type = obj.get("messageType")?.asString) {
                MessageType.HANDSHAKE         -> IncomingMessage.Handshake(gson.fromJson(json, HandshakeMessage::class.java))
                MessageType.TRANSFER_REQUEST  -> IncomingMessage.TransferRequest(gson.fromJson(json, TransferRequestMessage::class.java))
                MessageType.TRANSFER_RESPONSE -> IncomingMessage.TransferResponse(gson.fromJson(json, TransferResponseMessage::class.java))
                MessageType.FILE_CHUNK        -> IncomingMessage.FileChunk(gson.fromJson(json, FileChunkMessage::class.java))
                MessageType.CHUNK_ACK         -> IncomingMessage.ChunkAck(gson.fromJson(json, ChunkAckMessage::class.java))
                MessageType.TRANSFER_COMPLETE -> IncomingMessage.TransferComplete(gson.fromJson(json, TransferCompleteMessage::class.java))
                MessageType.TRANSFER_CANCEL,
                MessageType.TRANSFER_PAUSE,
                MessageType.TRANSFER_RESUME   -> IncomingMessage.TransferControl(type ?: "", gson.fromJson(json, TransferControlMessage::class.java))
                else -> IncomingMessage.Unknown
            }
        } catch (e: Exception) { IncomingMessage.Unknown }
    }

    fun toJson(any: Any): String = gson.toJson(any)

    // ── Builders ────────────────────────────────────────────────────────────

    fun makeHandshake(deviceName: String, deviceId: String) =
        HandshakeMessage(deviceName = deviceName, deviceType = "Android", deviceId = deviceId)

    fun makeTransferRequest(requestId: String, files: List<FileMetadata>, deviceName: String, deviceId: String) =
        TransferRequestMessage(requestId = requestId, files = files,
            totalSize = files.sumOf { it.size }, sourceDevice = deviceName, sourceDeviceId = deviceId)

    fun makeTransferResponse(requestId: String, approved: Boolean, downloadPath: String? = null) =
        TransferResponseMessage(requestId = requestId, approved = approved, downloadPath = downloadPath)

    fun makeFileChunk(fileId: String, requestId: String, chunkNumber: Int,
                      totalChunks: Int, data: String, fileName: String, chunkSize: Int) =
        FileChunkMessage(fileId = fileId, requestId = requestId, chunkNumber = chunkNumber,
            totalChunks = totalChunks, chunkSize = chunkSize, data = data, fileName = fileName)

    fun makeChunkAck(fileId: String, chunkNumber: Int) =
        ChunkAckMessage(fileId = fileId, chunkNumber = chunkNumber)

    fun makeTransferComplete(fileId: String, requestId: String, checksum: String, success: Boolean) =
        TransferCompleteMessage(fileId = fileId, requestId = requestId,
            checksum = checksum, status = if (success) "success" else "failed")

    /** Frame: 4-byte big-endian length + UTF-8 JSON body */
    fun frame(json: String): ByteArray {
        val body = json.toByteArray(Charsets.UTF_8)
        val len = body.size
        return byteArrayOf(
            (len shr 24).toByte(), (len shr 16).toByte(), (len shr 8).toByte(), len.toByte()
        ) + body
    }
}
