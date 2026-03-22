import Foundation

// MARK: - CLI Entry Point
// Run as: ./file-transfer <command> [args]
//
//   discover              – discover devices on local WiFi
//   send <path> <ip>      – send a file to device at <ip>
//   receive               – listen for incoming transfers (auto-saves to ~/Downloads)
//   help                  – show usage

let cli = CLIController()
cli.run(args: Array(CommandLine.arguments.dropFirst()))
