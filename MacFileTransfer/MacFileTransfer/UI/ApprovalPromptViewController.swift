import AppKit

final class ApprovalPromptViewController: NSViewController {

    var request: FileTransferRequest?
    var onDecision: ((Bool) -> Void)?

    private lazy var titleLabel = NSTextField(labelWithString: "Incoming Transfer Request")
    private lazy var fromLabel  = NSTextField(labelWithString: "")
    private lazy var sizeLabel  = NSTextField(labelWithString: "")

    private lazy var fileListView: NSTableView = {
        let tv = NSTableView()
        let col = NSTableColumn(identifier: .init("Files")); col.title = "Files"
        tv.addTableColumn(col); tv.delegate = self; tv.dataSource = self
        tv.usesAlternatingRowBackgroundColors = true
        return tv
    }()

    private lazy var acceptButton: NSButton = {
        let b = NSButton(title: "Accept", target: self, action: #selector(acceptTapped))
        b.bezelStyle = .rounded; b.keyEquivalent = "\r"; return b
    }()
    private lazy var rejectButton: NSButton = {
        let b = NSButton(title: "Reject", target: self, action: #selector(rejectTapped))
        b.bezelStyle = .rounded; b.keyEquivalent = "\u{1B}"; return b
    }()

    override func loadView() {
        let v = NSView(); v.setFrameSize(NSSize(width: 420, height: 310)); self.view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.font = .boldSystemFont(ofSize: 15)
        if let req = request {
            fromLabel.stringValue = "From: \(req.sourceDevice.name)"
            sizeLabel.stringValue = String(format: "%d file(s)  •  %.1f MB total",
                                           req.files.count, Double(req.totalSize) / 1_048_576)
        }
        [fromLabel, sizeLabel].forEach { $0.textColor = .secondaryLabelColor; $0.font = .systemFont(ofSize: 12) }

        let scroll = NSScrollView()
        scroll.documentView = fileListView; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder

        let btnRow = NSStackView(views: [rejectButton, NSView(), acceptButton])
        btnRow.orientation = .horizontal

        let stack = NSStackView(views: [titleLabel, fromLabel, sizeLabel, scroll, btnRow])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            scroll.heightAnchor.constraint(equalToConstant: 120),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    @objc private func acceptTapped() { dismiss(self); onDecision?(true)  }
    @objc private func rejectTapped() { dismiss(self); onDecision?(false) }
}

extension ApprovalPromptViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { request?.files.count ?? 0 }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let file = request?.files[row] else { return nil }
        let cell = NSTableCellView()
        let lbl  = NSTextField(labelWithString: "\(file.name)  –  \(String(format: "%.1f MB", Double(file.size)/1_048_576))")
        lbl.translatesAutoresizingMaskIntoConstraints = false; lbl.font = .systemFont(ofSize: 12)
        cell.addSubview(lbl)
        NSLayoutConstraint.activate([lbl.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                                     lbl.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4)])
        return cell
    }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 28 }
}
