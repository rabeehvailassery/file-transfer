import AppKit

final class MainWindowController: NSWindowController {

    private let coordinator: TransferCoordinator

    init(coordinator: TransferCoordinator) {
        self.coordinator = coordinator
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title    = "File Transfer"
        window.center()
        window.minSize  = NSSize(width: 700, height: 450)
        super.init(window: window)
        setupSplitView()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupSplitView() {
        let splitVC = NSSplitViewController()

        let deviceVC = DeviceListViewController()
        deviceVC.transferCoordinator = coordinator
        let left = NSSplitViewItem(viewController: deviceVC)
        left.minimumThickness = 220
        left.maximumThickness = 320

        let queueVC = TransferQueueViewController()
        queueVC.queue = coordinator.queue
        queueVC.transferCoordinator = coordinator
        let right = NSSplitViewItem(viewController: queueVC)
        right.minimumThickness = 400

        splitVC.addSplitViewItem(left)
        splitVC.addSplitViewItem(right)
        splitVC.splitView.isVertical = true
        window?.contentViewController = splitVC
    }
}
