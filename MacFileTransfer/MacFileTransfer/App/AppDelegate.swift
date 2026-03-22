import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var mainWindowController: MainWindowController?
    let coordinator = TransferCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
        mainWindowController = MainWindowController(coordinator: coordinator)
        mainWindowController?.showWindow(self)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }
}
