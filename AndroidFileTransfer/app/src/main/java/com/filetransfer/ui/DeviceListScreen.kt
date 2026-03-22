package com.filetransfer.ui

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.filetransfer.TransferViewModel
import com.filetransfer.UiState
import com.filetransfer.model.Device

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DeviceListScreen(vm: TransferViewModel, state: UiState) {
    var selectedDevice by remember { mutableStateOf<Device?>(null) }
    var manualIp by remember { mutableStateOf("") }
    var showIpDialog by remember { mutableStateOf(false) }
    var pendingUris by remember { mutableStateOf<List<Uri>>(emptyList()) }

    val filePicker = rememberLauncherForActivityResult(
        ActivityResultContracts.GetMultipleContents()
    ) { uris ->
        if (uris.isNotEmpty()) {
            selectedDevice?.let { vm.sendFiles(uris, it) }
        }
    }

    // Incoming transfer approval dialog
    state.pendingRequest?.let { req ->
        AlertDialog(
            onDismissRequest = { vm.respondToIncoming(req.requestId, false) },
            title = { Text("Incoming Transfer") },
            text = {
                Column {
                    Text("From: ${req.senderDevice.name}", fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(4.dp))
                    req.files.forEach { Text("• ${it.name}  (${it.size / 1024} KB)") }
                    Spacer(Modifier.height(4.dp))
                    Text("Total: ${"%.1f".format(req.totalSize / 1_048_576.0)} MB")
                }
            },
            confirmButton = {
                TextButton(onClick = { vm.respondToIncoming(req.requestId, true) }) {
                    Text("Accept", color = MaterialTheme.colorScheme.primary)
                }
            },
            dismissButton = {
                TextButton(onClick = { vm.respondToIncoming(req.requestId, false) }) {
                    Text("Reject", color = MaterialTheme.colorScheme.error)
                }
            }
        )
    }

    // Manual IP dialog
    if (showIpDialog) {
        AlertDialog(
            onDismissRequest = { showIpDialog = false },
            title = { Text("Add Device by IP") },
            text = {
                OutlinedTextField(
                    value = manualIp,
                    onValueChange = { manualIp = it },
                    label = { Text("IP Address (e.g. 192.168.1.10)") },
                    singleLine = true
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    if (manualIp.isNotBlank()) {
                        // handled in main via ViewModel
                    }
                    showIpDialog = false
                }) { Text("Add") }
            },
            dismissButton = { TextButton(onClick = { showIpDialog = false }) { Text("Cancel") } }
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("File Transfer") },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer
                ),
                actions = {
                    TextButton(onClick = { vm.refresh() }) { Text("Refresh") }
                    TextButton(onClick = { showIpDialog = true }) { Text("Add IP") }
                }
            )
        }
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            if (state.devices.isEmpty()) {
                Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        CircularProgressIndicator()
                        Spacer(Modifier.height(16.dp))
                        Text("Scanning for devices…", color = Color.Gray)
                    }
                }
            } else {
                Text("Tap a device to send files",
                    style = MaterialTheme.typography.labelMedium,
                    modifier = Modifier.padding(16.dp, 12.dp))
                LazyColumn(Modifier.weight(1f)) {
                    items(state.devices) { device ->
                        DeviceRow(device = device, selected = device == selectedDevice) {
                            selectedDevice = device
                            filePicker.launch("*/*")
                        }
                        HorizontalDivider()
                    }
                }
            }

            // Transfer list
            if (state.transfers.isNotEmpty()) {
                Text("Transfers", style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.padding(16.dp, 8.dp))
                LazyColumn(Modifier.heightIn(max = 240.dp)) {
                    items(state.transfers) { item ->
                        TransferRow(item)
                        HorizontalDivider()
                    }
                }
            }

            if (state.statusMessage.isNotBlank()) {
                Text(state.statusMessage,
                    modifier = Modifier.padding(16.dp),
                    color = MaterialTheme.colorScheme.primary)
            }
        }
    }
}

@Composable
private fun DeviceRow(device: Device, selected: Boolean, onClick: () -> Unit) {
    val bg = if (selected) MaterialTheme.colorScheme.primaryContainer else Color.Transparent
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Surface(shape = MaterialTheme.shapes.small,
            color = if (device.isActive) MaterialTheme.colorScheme.primary
                    else MaterialTheme.colorScheme.outline,
            modifier = Modifier.size(12.dp)) {}
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(device.name, fontWeight = FontWeight.SemiBold)
            Text("${device.type.raw}  •  ${device.ipAddress}",
                style = MaterialTheme.typography.bodySmall, color = Color.Gray)
        }
        Text(if (device.isActive) "Online" else "Offline",
            style = MaterialTheme.typography.labelSmall,
            color = if (device.isActive) MaterialTheme.colorScheme.primary else Color.Gray)
    }
}

@Composable
private fun TransferRow(item: com.filetransfer.TransferItem) {
    val dir = if (item.direction == com.filetransfer.TransferItem.Direction.SENDING) "↑" else "↓"
    Column(Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) {
        Row(Modifier.fillMaxWidth()) {
            Text("$dir ${item.fileName}", Modifier.weight(1f), fontWeight = FontWeight.Medium)
            Text(item.status.name, style = MaterialTheme.typography.labelSmall)
        }
        item.progress?.let { p ->
            Spacer(Modifier.height(4.dp))
            LinearProgressIndicator(
                progress = { (p.percentage / 100.0).toFloat().coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth()
            )
            Text("%.1f%%  ${p.speedFormatted}".format(p.percentage),
                style = MaterialTheme.typography.labelSmall, color = Color.Gray)
        }
    }
}
