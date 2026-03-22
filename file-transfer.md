PRODUCT REQUIREMENTS DOCUMENT: LOCAL WIFI FILE TRANSFER SYSTEM
PROJECT OVERVIEW
A peer-to-peer file transfer application enabling seamless file sharing between a Mac and Samsung Android device over a local WiFi network. The system provides a secure, user-friendly interface with mutual approval workflows, queue management, and support for all file types including images, videos, and documents.
PROJECT SCOPE
This is a personal-use project designed specifically for transferring files between a MacBook running native Swift and a Samsung phone running Kotlin/Android. No cloud storage or external servers involved—purely local WiFi peer-to-peer communication.
CORE FUNCTIONAL REQUIREMENTS
Device Discovery and Connection
Both applications automatically discover each other on the same WiFi network using UDP broadcasting or mDNS. Devices display in a list with connection status. Manual IP address entry available as fallback. TCP socket connection established between devices.
File Transfer Capabilities
Support transfer of all file types: images, videos, documents, and generic files. Handle large file transfers up to several gigabytes. Implement chunked transfer protocol for stability and reliability. Display real-time progress tracking with percentage complete. Preserve file metadata where applicable.
Mutual Approval Workflow
When Device A initiates a transfer, Device B receives a notification/prompt. Device B can accept or reject before transmission begins. When Device B initiates, Device A receives the same approval prompt. Rejected transfers are logged and removed from queue. Approved transfers move to active queue.
Queue Management System
Display three queue types: pending requests (awaiting approval), active transfers (in progress), and completed transfers (with timestamps). Users can pause individual transfers, resume paused transfers, and cancel queued or in-progress transfers. Show estimated time remaining and transfer speed (MB/s) for each active transfer.
Mac User Interface (Swift/Native macOS)
Clean, modern macOS-native interface. Device list showing available Android devices with connection status. Main transfer window with drag-and-drop support for initiating sends. Queue panel showing pending approvals, active transfers, and completed history. Notifications for incoming transfer requests. Settings panel for network preferences. File browser for selecting multiple files. Transfer history with file viewing capability.
Android User Interface (Kotlin/Native)
Material Design 3 compliant interface. Device list showing available Mac devices with connection status. Notification system for incoming transfer requests with accept/reject buttons. Queue management screen showing all transfer statuses. File picker integration for selecting files to send. Transfer progress display with speed and time remaining. Completed transfer history.
NON-FUNCTIONAL REQUIREMENTS
Security
Optional password/PIN protection for pairing devices. All transfers encrypted over TCP (TLS/SSL optional for local network). No data sent to external servers. Mutual authentication handshake before file transfer.
Performance
Support file transfers up to several gigabytes. Optimize for local WiFi with no cloud overhead. Minimize battery drain on Android during transfers. Implement efficient chunking strategy (1-4MB chunks recommended).
Reliability
Resume capability for interrupted large transfers. Graceful error handling for network disconnections. Validation of file integrity post-transfer using checksums. Detailed error messages to guide users.
Compatibility
Mac: macOS 12.0 or later. Android: Android 10 or later. Both devices on same WiFi network (2.4GHz or 5GHz). No firewall blocking local network communication.
TECHNICAL ARCHITECTURE
Device Discovery Phase
UDP broadcast on port 5353 or use mDNS. Broadcast every 30 seconds. Include device name, type (Mac/Android), and listening TCP port. Device appears in list for 60 seconds without refresh.
Connection Handshake
TCP connection to target device. Exchange device metadata (name, UUID, supported features). Confirm mutual readiness to receive.
Transfer Request Phase
Initiating device sends transfer request with file metadata (name, size, type, count). Receiving device displays approval prompt. User accepts/rejects. Rejection cancels transfer. Acceptance signals proceed to file transfer.
File Transfer Phase
Send data in 2-4MB chunks with sequence numbers. Receiving device writes to temporary file. After each chunk: send acknowledgment. After all chunks: verify checksum. Move temp file to final location. Send completion confirmation.
Queue Status Updates
Continuous status updates between devices about queue state. Sync completed transfer history.
TECHNOLOGY STACK
Mac Application
Language: Swift. Framework: AppKit (native macOS). Networking: Foundation URLSession + raw TCP sockets. File I/O: FileManager. UI: NSViewController, NSTableView, NSDraggingDestination. Storage: UserDefaults for preferences, local file system.
Android Application
Language: Kotlin. Framework: Android Framework (native). Networking: java.net.Socket for TCP, DatagramSocket for UDP. Async: Coroutines. UI: Jetpack Compose or XML layouts. Storage: Android File System, MediaStore. Permissions: READ_EXTERNAL_STORAGE, WRITE_EXTERNAL_STORAGE, ACCESS_NETWORK_STATE.
NETWORK PROTOCOL
Messages use JSON format over TCP for control flow:
Device Discovery: messageType, deviceName, deviceType, listeningPort, timestamp
Transfer Request: messageType, requestId, files array (name, size, mimeType), totalSize, sourceDevice
Transfer Response: messageType, requestId, approved (boolean), downloadPath
File Chunk: messageType, fileId, chunkNumber, totalChunks, chunkSize, data (base64)
Transfer Complete: messageType, fileId, checksum (sha256), status
USER WORKFLOWS
Workflow 1: Mac User Sends Files to Android
User opens Mac app. Android device appears in list. User selects files via drag-and-drop or picker. Transfer request sent to Android. Android user sees notification. Android user taps accept. Files transfer with progress display on both devices. Transfer completes. Files appear in Android Downloads. Both devices log transfer.
Workflow 2: Android User Sends Files to Mac
User opens Android app. Mac device appears in list. User selects files from Android file picker. Transfer request sent to Mac. Mac user sees notification. Mac user clicks accept. Files transfer with progress display on both devices. Transfer completes. Files appear in Mac Downloads. Both devices log transfer.
Workflow 3: Pause and Resume Large Transfer
User initiates large video transfer. Progress bar shows percentage complete. User pauses transfer. Both devices show paused state. User resumes transfer later. Transfer resumes from checkpoint (not from beginning). Completes successfully.
OUT OF SCOPE
Cloud backup or sync. Web interface or browser-based access. Transfer scheduling or automation. File compression before transfer. Multi-device mesh networking (Mac-to-Android only). Group file sharing. File management/deletion on receiving device. Streaming or preview during transfer.
SUCCESS CRITERIA
Device discovery within 5 seconds of app launch. File transfer speed achieves 80%+ of WiFi bandwidth capacity. Large file transfers (1GB+) complete without interruption on stable WiFi. Users can pause and resume transfers without data loss. Mutual approval workflow prevents accidental transfers. Queue system clearly shows all pending, active, and completed transfers. Both apps maintain feature parity. Error messages guide user to resolution.
FUTURE ENHANCEMENTS
File compression option. Transfer scheduling. Automatic retry on connection loss. File preview before accepting. Favorites/frequent devices. Transfer history with thumbnails. Bandwidth limiting. Support for additional devices. Web UI for monitoring. Rich media notifications.
DEVELOPMENT PHASES
Phase 1: Core Infrastructure - Device discovery (UDP/mDNS), TCP socket connection, basic protocol
Phase 2: File Transfer Engine - Chunked transfer with checksums, progress tracking, error handling
Phase 3: UI and Queue Management - Mac native UI, Android native UI, approval workflow
Phase 4: Polish and Testing - Performance optimization, error scenarios, cross-device testing, UI refinement
ASSUMPTIONS AND DEPENDENCIES
Both devices on same WiFi network. WiFi allows local broadcast and TCP connections. Users have local file system write permissions. Target OS versions have required APIs. No firewall blocking local network communication between apps.
SUCCESS METRICS
100MB file transfer: under 30 seconds on 5GHz WiFi. 1GB file transfer: completes without interruption. Device discovery: appears in list within 5 seconds. Queue display: updates within 500ms of state change. Approval notification: appears within 2 seconds of request.