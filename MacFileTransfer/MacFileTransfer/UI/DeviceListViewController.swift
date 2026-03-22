import AppKit

final class DeviceListViewController: NSViewController {

    var transferCoordinator: TransferCoordinator?

    private lazy var tableView: NSTableView = {
        let tv = NSTableView()
        tv.style = .inset; tv.usesAlternatingRowBackgroundColors = true
        tv.delegate = self; tv.dataSource = self
        let col = NSTableColumn(identifier: .init("DeviceCol"))
        col.title = "Devices"; col.minWidth = 200
        tv.addTableColumn(col); tv.headerView = nil
        tv.registerForDraggedTypes([.fileURL])
        return tv
    }()

    private lazy var emptyLabel: NSTextField = {
        let l = NSTextField(labelWithString: "Searching for devices on your WiFi…")
        l.textColor = .secondaryLabelColor; l.alignment = .center; l.font = .systemFont(ofSize: 13)
        return l
    }()

    private var devices: [Device] = []

    override func loadView() { self.view = NSView() }

    override func viewDidLoad() {
        super.viewDidLoad()

        let scroll = NSScrollView()
        scroll.documentView = tableView; scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let refreshBtn = NSButton(title: "Refresh",        target: self, action: #selector(refreshTapped))
        let manualBtn  = NSButton(title: "Add Manually…",  target: self, action: #selector(manualIPTapped))
        [refreshBtn, manualBtn].forEach { $0.bezelStyle = .rounded }

        let btnStack = NSStackView(views: [refreshBtn, manualBtn])
        btnStack.orientation = .horizontal; btnStack.spacing = 8

        [btnStack, scroll, emptyLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0)
        }
        NSLayoutConstraint.activate([
            btnStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            btnStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scroll.topAnchor.constraint(equalTo: btnStack.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor)
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(devicesChanged),
                                               name: .devicesDidChange, object: nil)
    }

    @objc private func refreshTapped() {
        transferCoordinator?.discoveryService.broadcastMessage()
    }

    @objc private func manualIPTapped() {
        let alert = NSAlert()
        alert.messageText    = "Connect to Device"
        alert.informativeText = "Enter the IP address of the Android device on your WiFi:"
        let ipField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        ipField.placeholderString = "e.g. 192.168.1.5"
        alert.accessoryView = ipField
        alert.addButton(withTitle: "Connect"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let ip = ipField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !ip.isEmpty else { return }
        transferCoordinator?.discoveryService.addDeviceManually(
            ip: ip, port: Int(DeviceDiscoveryService.tcpPort), name: "Android Device")
    }

    @objc private func devicesChanged() {
        devices = Array(transferCoordinator?.discoveryService.discoveredDevices.values ?? [:].values)
        tableView.reloadData()
        emptyLabel.isHidden = !devices.isEmpty
    }
}

extension DeviceListViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { devices.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let device = devices[row]
        let cell = NSTableCellView()
        let label  = NSTextField(labelWithString: "\(device.name) (\(device.type.rawValue))")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        let status = NSTextField(labelWithString: device.isActive ? "● Online" : "○ Offline")
        status.textColor = device.isActive ? .systemGreen : .secondaryLabelColor
        status.font = .systemFont(ofSize: 11)
        let stack = NSStackView(views: [label, status])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 2
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8)
        ])
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 50 }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation: NSTableView.DropOperation) -> NSDragOperation {
        row < devices.count ? .copy : []
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                   row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard row < devices.count,
              let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
        else { return false }
        transferCoordinator?.initiateTransfer(urls: urls, toDevice: devices[row])
        return true
    }
}

extension Notification.Name {
    static let devicesDidChange = Notification.Name("com.filetransfer.devicesDidChange")
}
