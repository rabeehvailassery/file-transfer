// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "file-transfer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "file-transfer",
            path: "MacFileTransfer",
            sources: [
                "App/main.swift",
                "App/CLIController.swift",
                "App/CLITransferCoordinator.swift",
                "App/TransferEvents.swift",
                "Models/TransferModels.swift",
                "Networking/DeviceDiscoveryService.swift",
                "Networking/TCPConnectionManager.swift",
                "Networking/MessageProtocol.swift",
                "Networking/FileTransferEngine.swift",
                "Queue/TransferQueue.swift"
            ]
        )
    ]
)
