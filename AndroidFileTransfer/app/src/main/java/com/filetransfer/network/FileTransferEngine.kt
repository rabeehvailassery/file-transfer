package com.filetransfer.network

import android.util.Base64
import com.filetransfer.model.TransferProgress
import kotlinx.coroutines.*
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.UUID

private const val CHUNK_SIZE = 2 * 1024 * 1024   // 2 MB — must match Mac

interface FileTransferEngineListener {
    fun onProgress(progress: TransferProgress)
    fun onComplete(requestId: String, fileId: String, success: Boolean)
    fun onRequiresSend(data: ByteArray, toDeviceId: UUID)
}

class FileTransferEngine {

    var listener: FileTransferEngineListener? = null
    var receiveDirectory: File? = null

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val sendCheckpoints = mutableMapOf<String, Int>()
    private val sendPaused      = mutableMapOf<String, Boolean>()
    private val sendCancelled   = mutableMapOf<String, Boolean>()
    private val receiveStreams   = mutableMapOf<String, FileOutputStream>()
    private val receivePaths    = mutableMapOf<String, File>()
    private val receiveDests    = mutableMapOf<String, File>()
    private val receiveProgress = mutableMapOf<String, TransferProgress>()

    // MARK: - Send

    fun sendFiles(files: List<File>, requestId: String, toDeviceId: UUID) {
        scope.launch {
            for (file in files) {
                if (sendCancelled[requestId] == true) break
                sendFile(file, requestId, toDeviceId)
            }
        }
    }

    private suspend fun sendFile(file: File, requestId: String, toDeviceId: UUID) {
        val data        = file.readBytes()
        val fileId      = UUID.randomUUID().toString()
        val fileName    = file.name
        val totalChunks = Math.ceil(data.size.toDouble() / CHUNK_SIZE).toInt().coerceAtLeast(1)
        sendPaused[fileId] = false; sendCancelled[fileId] = false

        var progress = TransferProgress(requestId, fileId, fileName, data.size.toLong())
        var lastUpdate = System.currentTimeMillis(); var bytesSince = 0L

        for (chunkNum in 0 until totalChunks) {
            while (sendPaused[fileId] == true) delay(200)
            if (sendCancelled[fileId] == true) return

            val start = chunkNum * CHUNK_SIZE
            val end   = minOf(start + CHUNK_SIZE, data.size)
            val chunk = data.copyOfRange(start, end)
            val encoded = Base64.encodeToString(chunk, Base64.NO_WRAP)

            val msg = MessageProtocol.makeFileChunk(fileId, requestId, chunkNum,
                totalChunks, encoded, fileName, chunk.size)
            val framed = MessageProtocol.frame(MessageProtocol.toJson(msg))
            listener?.onRequiresSend(framed, toDeviceId)

            // Wait for ACK (simple polling with 10s timeout)
            val timeout = System.currentTimeMillis() + 10_000
            while ((sendCheckpoints[fileId] ?: -1) < chunkNum) {
                if (System.currentTimeMillis() > timeout || sendCancelled[fileId] == true) break
                delay(10)
            }

            bytesSince += chunk.size
            progress = progress.copy(transferredBytes = progress.transferredBytes + chunk.size)
            val elapsed = (System.currentTimeMillis() - lastUpdate) / 1000.0
            if (elapsed >= 0.5) {
                progress = progress.copy(speedBytesPerSecond = bytesSince / elapsed)
                bytesSince = 0; lastUpdate = System.currentTimeMillis()
            }
            withContext(Dispatchers.Main) { listener?.onProgress(progress) }
        }

        // Send completion with SHA-256
        val checksum = sha256hex(data)
        val complete = MessageProtocol.makeTransferComplete(fileId, requestId, checksum, true)
        listener?.onRequiresSend(MessageProtocol.frame(MessageProtocol.toJson(complete)), toDeviceId)
        sendCheckpoints.remove(fileId)
    }

    fun handleChunkAck(msg: ChunkAckMessage) { sendCheckpoints[msg.fileId] = msg.chunkNumber }
    fun pauseSend(fileId: String)  { sendPaused[fileId]    = true  }
    fun resumeSend(fileId: String) { sendPaused[fileId]    = false }
    fun cancelSend(fileId: String) { sendCancelled[fileId] = true; sendPaused[fileId] = false }

    // MARK: - Receive

    fun handleIncomingChunk(msg: FileChunkMessage, fromDeviceId: UUID) {
        // Auto-register on first chunk (mirrors Mac behaviour)
        if (!receiveStreams.containsKey(msg.fileId)) {
            val dir = receiveDirectory ?: return
            val tmp  = File(dir, ".${msg.fileId}.tmp")
            val dest = File(dir, msg.fileName)
            receiveStreams[msg.fileId]   = FileOutputStream(tmp)
            receivePaths[msg.fileId]     = tmp
            receiveDests[msg.fileId]     = dest
            val totalBytes = msg.totalChunks.toLong() * msg.chunkSize
            receiveProgress[msg.fileId]  = TransferProgress("", msg.fileId, msg.fileName, totalBytes)
        }

        val chunk = Base64.decode(msg.data, Base64.NO_WRAP)
        receiveStreams[msg.fileId]?.write(chunk)

        receiveProgress[msg.fileId]?.let { p ->
            val updated = p.copy(transferredBytes = p.transferredBytes + chunk.size,
                speedBytesPerSecond = if ((System.currentTimeMillis() - p.startedAt) > 0)
                    p.transferredBytes.toDouble() / ((System.currentTimeMillis() - p.startedAt) / 1000.0) else 0.0)
            receiveProgress[msg.fileId] = updated
            scope.launch(Dispatchers.Main) { listener?.onProgress(updated) }
        }

        // Send ACK
        val ack = MessageProtocol.makeChunkAck(msg.fileId, msg.chunkNumber)
        listener?.onRequiresSend(MessageProtocol.frame(MessageProtocol.toJson(ack)), fromDeviceId)
    }

    fun handleTransferComplete(msg: TransferCompleteMessage) {
        val stream = receiveStreams[msg.fileId] ?: return
        val tmpFile = receivePaths[msg.fileId]  ?: return
        val dstFile = receiveDests[msg.fileId]  ?: return
        stream.close()

        val data = tmpFile.readBytes()
        val computed = sha256hex(data)
        val success = computed == msg.checksum
        if (success) tmpFile.renameTo(dstFile) else tmpFile.delete()

        receiveStreams.remove(msg.fileId); receivePaths.remove(msg.fileId)
        receiveDests.remove(msg.fileId);  receiveProgress.remove(msg.fileId)
        scope.launch(Dispatchers.Main) { listener?.onComplete(msg.requestId, msg.fileId, success) }
    }

    // MARK: - Helpers

    private fun sha256hex(data: ByteArray): String {
        val md = MessageDigest.getInstance("SHA-256")
        return md.digest(data).joinToString("") { "%02x".format(it) }
    }
}
