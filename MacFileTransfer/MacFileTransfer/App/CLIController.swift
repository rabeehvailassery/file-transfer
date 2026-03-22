import Foundation

// MARK: - CLIController
final class CLIController {

    private let coordinator = CLITransferCoordinator()

    // Dedicated serial queue for stdin so readLine() never blocks networking or main thread
    private let stdinQueue = DispatchQueue(label: "com.filetransfer.stdin")

    func run(args: [String]) {
        guard let command = args.first else { printHelp(); exit(0) }
        switch command {
        case "discover": runDiscover()
        case "send":
            guard args.count >= 3 else { print("Usage: file-transfer send <file-path> <ip>"); exit(1) }
            runSend(path: args[1], ip: args[2])
        case "receive": runReceive()
        default: printHelp(); exit(0)
        }
        RunLoop.main.run()
    }

    // MARK: - Discover

    private func runDiscover() {
        print("🔍 Scanning for devices on local WiFi (30s)…\n")
        coordinator.startDiscovery { device in
            let status = device.isActive ? "🟢" : "⚪"
            print("  \(status)  \(device.name)  [\(device.type.rawValue)]  \(device.ipAddress):\(device.listeningPort)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            print("\nDone."); exit(0)
        }
    }

    // MARK: - Send

    private func runSend(path: String, ip: String) {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ File not found: \(url.path)"); exit(1)
        }
        print("📤 Connecting to \(ip)…")
        coordinator.send(fileURL: url, toIP: ip) { event in
            switch event {
            case .connecting:       print("   Connected. Sending transfer request…")
            case .waitingApproval:  print("   ⏳ Waiting for receiver to accept…")
            case .rejected:         print("   ❌ Transfer rejected by receiver."); exit(1)
            case .progress(let pct, let speed):
                print("\r   \(Self.bar(pct))  \(String(format: "%5.1f", pct))%  \(speed)           ",
                      terminator: ""); fflush(stdout)
            case .completed(let name):
                print("\n   ✅ \(name) sent successfully."); exit(0)
            case .failed(let err):  print("\n   ❌ Failed: \(err)"); exit(1)
            }
        }
    }

    // MARK: - Receive

    private func runReceive() {
        let dl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        print("📥 Receiver started. Incoming files → \(dl.path)\n   Press Ctrl+C to stop.\n")

        coordinator.startReceiving(saveDirectory: dl) { [weak self] (event: ReceiveEvent) in
            guard let self else { return }
            switch event {
            case .incomingRequest(let sender, let files, let totalMB, let accept):
                // Run readLine() on the dedicated stdin queue so we never block
                // the networking queue that called this callback.
                self.stdinQueue.async {
                    print("\n─────────────────────────────────────")
                    print("📨 Incoming from \(sender)")
                    files.forEach { print("   • \($0.name)  (\(String(format: "%.1f", Double($0.size)/1_048_576)) MB)") }
                    print("   Total: \(String(format: "%.1f", totalMB)) MB")
                    print("Accept? [y/n]: ", terminator: ""); fflush(stdout)
                    let answer = readLine()?.lowercased().trimmingCharacters(in: .whitespaces) ?? "n"
                    accept(answer == "y" || answer == "yes")
                }
            case .progress(let pct, let speed):
                print("\r   \(Self.bar(pct))  \(String(format: "%5.1f", pct))%  \(speed)           ",
                      terminator: ""); fflush(stdout)
            case .completed(let name):
                print("\n   ✅ Saved: \(dl.appendingPathComponent(name).path)")
            case .failed(let err):
                print("\n   ❌ Error: \(err)")
            case .idle: break
            }
        }
    }

    // MARK: - Helpers

    private func printHelp() {
        print("""
        file-transfer — Local WiFi file transfer

        Usage:
          file-transfer discover              List devices on your WiFi network
          file-transfer send <path> <ip>      Send a file to the device at <ip>
          file-transfer receive               Listen for incoming transfers

        Examples:
          file-transfer discover
          file-transfer send ~/Desktop/photo.jpg 192.168.1.42
          file-transfer receive
        """)
    }

    private static func bar(_ pct: Double) -> String {
        let f = Int(pct / 5); let e = 20 - f
        return "[" + String(repeating: "█", count: f) + String(repeating: "░", count: e) + "]"
    }
}
