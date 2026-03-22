package com.filetransfer

import android.app.Application
import android.content.Context
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.filetransfer.model.*
import com.filetransfer.network.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

data class UiState(
    val devices: List<Device> = emptyList(),
    val transfers: List<TransferItem> = emptyList(),
    val pendingRequest: IncomingTransferRequest? = null,
    val statusMessage: String = ""
)

data class TransferItem(
    val requestId: String,
    val fileName: String,
    val direction: Direction,
    var status: TransferStatus = TransferStatus.PENDING,
    var progress: TransferProgress? = null
) { enum class Direction { SENDING, RECEIVING } }

class TransferViewModel(app: Application) : AndroidViewModel(app) {

    private val ctx = app.applicationContext
    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state

    private val discoveryService = DeviceDiscoveryService(ctx)
    private val tcpManager: TCPConnectionManager
    private val engine = FileTransferEngine()

    private val pendingTransfers = mutableMapOf<String, Pair<List<File>, UUID>>()
    private var pendingRespondFn: ((Boolean) -> Unit)? = null

    init {
        tcpManager = TCPConnectionManager(discoveryService.deviceId, discoveryService.deviceName)

        discoveryService.listener = object : DeviceDiscoveryListener {
            override fun onDeviceDiscovered(device: Device) { updateDevices() }
            override fun onDeviceLost(device: Device) { updateDevices() }
        }

        tcpManager.listener = object : TCPConnectionListener {
            override fun onConnected(device: Device) { updateDevices() }
            override fun onDisconnected(device: Device) { updateDevices() }
            override fun onMessageReceived(data: String, from: Device) { handleMessage(data, from) }
        }

        engine.listener = object : FileTransferEngineListener {
            override fun onProgress(progress: TransferProgress) {
                _state.value = _state.value.copy(transfers = _state.value.transfers.map {
                    if (it.requestId == progress.requestId) it.copy(progress = progress) else it
                })
            }
            override fun onComplete(requestId: String, fileId: String, success: Boolean) {
                _state.value = _state.value.copy(
                    transfers = _state.value.transfers.map {
                        if (it.requestId == requestId)
                            it.copy(status = if (success) TransferStatus.COMPLETED else TransferStatus.FAILED)
                        else it
                    },
                    statusMessage = if (success) "Transfer complete ✅" else "Transfer failed ❌"
                )
            }
            override fun onRequiresSend(data: ByteArray, toDeviceId: UUID) {
                tcpManager.sendRaw(data, toDeviceId)
            }
        }

        engine.receiveDirectory = ctx.getExternalFilesDir(android.os.Environment.DIRECTORY_DOWNLOADS)

        tcpManager.startListening()
        discoveryService.start()
    }

    // MARK: - Public API

    fun sendFiles(uris: List<Uri>, toDevice: Device) {
        viewModelScope.launch {
            val files = uris.mapNotNull { uriToFile(it) }
            val requestId = UUID.randomUUID().toString()
            val metas = files.map { FileMetadata(it.name, it.length(), "application/octet-stream") }

            val item = TransferItem(requestId, files.firstOrNull()?.name ?: "unknown",
                TransferItem.Direction.SENDING)
            addTransfer(item)

            val connected = tcpManager.connect(toDevice)
            if (!connected) { updateTransferStatus(requestId, TransferStatus.FAILED); return@launch }

            val req = MessageProtocol.makeTransferRequest(requestId, metas,
                discoveryService.deviceName, discoveryService.deviceId)
            tcpManager.send(req, toDevice.id)
            pendingTransfers[requestId] = files to toDevice.id
            updateTransferStatus(requestId, TransferStatus.PENDING)
        }
    }

    fun respondToIncoming(requestId: String, approved: Boolean) {
        pendingRespondFn?.invoke(approved)
        pendingRespondFn = null
        _state.value = _state.value.copy(pendingRequest = null)
    }

    fun refresh() { discoveryService.broadcastNow() }

    // MARK: - Private

    private fun handleMessage(json: String, from: Device) {
        when (val msg = MessageProtocol.decode(json)) {
            is IncomingMessage.TransferResponse -> {
                val (files, devId) = pendingTransfers[msg.msg.requestId] ?: return
                pendingTransfers.remove(msg.msg.requestId)
                if (msg.msg.approved) {
                    updateTransferStatus(msg.msg.requestId, TransferStatus.ACTIVE)
                    engine.sendFiles(files, msg.msg.requestId, devId)
                } else {
                    updateTransferStatus(msg.msg.requestId, TransferStatus.REJECTED)
                }
            }
            is IncomingMessage.TransferRequest -> {
                val req = IncomingTransferRequest(
                    msg.msg.requestId,
                    Device(UUID.fromString(msg.msg.sourceDeviceId), msg.msg.sourceDevice,
                        Device.DeviceType.MAC, from.ipAddress, from.listeningPort),
                    msg.msg.files
                )
                val item = TransferItem(msg.msg.requestId, msg.msg.files.firstOrNull()?.name ?: "unknown",
                    TransferItem.Direction.RECEIVING)
                addTransfer(item)

                pendingRespondFn = { approved ->
                    val response = MessageProtocol.makeTransferResponse(msg.msg.requestId, approved)
                    tcpManager.send(response, from.id)
                    if (approved) {
                        engine.receiveDirectory =
                            ctx.getExternalFilesDir(android.os.Environment.DIRECTORY_DOWNLOADS)
                        updateTransferStatus(msg.msg.requestId, TransferStatus.ACTIVE)
                    } else {
                        updateTransferStatus(msg.msg.requestId, TransferStatus.REJECTED)
                    }
                }
                _state.value = _state.value.copy(pendingRequest = req)
            }
            is IncomingMessage.FileChunk       -> engine.handleIncomingChunk(msg.msg, from.id)
            is IncomingMessage.ChunkAck        -> engine.handleChunkAck(msg.msg)
            is IncomingMessage.TransferComplete -> engine.handleTransferComplete(msg.msg)
            else -> {}
        }
    }

    private fun updateDevices() {
        _state.value = _state.value.copy(devices = discoveryService.getDevices())
    }

    private fun addTransfer(item: TransferItem) {
        _state.value = _state.value.copy(transfers = _state.value.transfers + item)
    }

    private fun updateTransferStatus(requestId: String, status: TransferStatus) {
        _state.value = _state.value.copy(transfers = _state.value.transfers.map {
            if (it.requestId == requestId) it.copy(status = status) else it
        })
    }

    private fun uriToFile(uri: Uri): File? {
        return try {
            val ins = ctx.contentResolver.openInputStream(uri) ?: return null
            val name = uri.lastPathSegment?.substringAfterLast("/") ?: "file"
            val tmp = File(ctx.cacheDir, name)
            FileOutputStream(tmp).use { out -> ins.copyTo(out) }
            tmp
        } catch (_: Exception) { null }
    }

    override fun onCleared() {
        super.onCleared()
        discoveryService.stop()
        tcpManager.stopListening()
    }
}
