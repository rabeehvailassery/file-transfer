package com.filetransfer.model

import java.util.UUID

// MARK: - Device

data class Device(
    val id: UUID,
    val name: String,
    val type: DeviceType,
    val ipAddress: String,
    val listeningPort: Int,
    var lastSeen: Long = System.currentTimeMillis()
) {
    val isActive: Boolean get() = System.currentTimeMillis() - lastSeen < 60_000L

    enum class DeviceType(val raw: String) {
        MAC("Mac"), ANDROID("Android");
        companion object { fun from(s: String) = entries.firstOrNull { it.raw == s } ?: ANDROID }
    }
}

// MARK: - File Metadata

data class FileMetadata(
    val name: String,
    val size: Long,
    val mimeType: String
)

// MARK: - Transfer Status

enum class TransferStatus { PENDING, ACTIVE, PAUSED, COMPLETED, REJECTED, FAILED, CANCELLED }

// MARK: - Transfer Progress

data class TransferProgress(
    val requestId: String,
    val fileId: String,
    val fileName: String,
    val totalBytes: Long,
    var transferredBytes: Long = 0,
    var speedBytesPerSecond: Double = 0.0,
    val startedAt: Long = System.currentTimeMillis()
) {
    val percentage: Double get() = if (totalBytes > 0) transferredBytes.toDouble() / totalBytes * 100.0 else 0.0

    val estimatedSecondsRemaining: Double? get() {
        if (speedBytesPerSecond <= 0) return null
        return (totalBytes - transferredBytes).toDouble() / speedBytesPerSecond
    }

    val speedFormatted: String get() = "%.1f MB/s".format(speedBytesPerSecond / 1_048_576.0)
}

// MARK: - Incoming Transfer Request (for UI)

data class IncomingTransferRequest(
    val requestId: String,
    val senderDevice: Device,
    val files: List<FileMetadata>
) {
    val totalSize: Long get() = files.sumOf { it.size }
}
