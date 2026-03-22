import AppKit

final class TransferQueueViewController: NSViewController {

    var queue: TransferQueue?
    var transferCoordinator: TransferCoordinator?

    private lazy var tableView: NSTableView = {
        let tv = NSTableView()
        tv.style = .inset; tv.usesAlternatingRowBackgroundColors = true
        tv.delegate = self; tv.dataSource = self
        for (id, title, w): (String, String, CGFloat) in
            [("Name","File",160),("Status","Status",90),("Progress","Progress",80),("Speed","Speed",90),("ETA","ETA",70)] {
            let col = NSTableColumn(identifier: .init(id)); col.title = title; col.width = w
            tv.addTableColumn(col)
        }
        return tv
    }()

    private var sections: [(title: String, items: [TransferItem])] = []
    private var timer: Timer?

    override func loadView() { self.view = NSView() }

    override func viewDidLoad() {
        super.viewDidLoad()

        let scroll = NSScrollView()
        scroll.documentView = tableView; scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder; scroll.translatesAutoresizingMaskIntoConstraints = false

        let clearBtn = NSButton(title: "Clear Completed", target: self, action: #selector(clearTapped))
        clearBtn.bezelStyle = .rounded; clearBtn.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scroll); view.addSubview(clearBtn)
        NSLayoutConstraint.activate([
            clearBtn.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            clearBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: clearBtn.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    override func viewDidDisappear() { super.viewDidDisappear(); timer?.invalidate() }

    private func refresh() {
        guard let q = queue else { return }
        sections = []
        if !q.pendingItems.isEmpty   { sections.append(("Pending Approval", q.pendingItems)) }
        if !q.activeItems.isEmpty    { sections.append(("Active Transfers",  q.activeItems))  }
        if !q.completedItems.isEmpty { sections.append(("Completed",         q.completedItems)) }
        tableView.reloadData()
    }

    @objc private func clearTapped() { queue?.clearCompleted() }

    private func resolve(row: Int) -> (title: String?, item: TransferItem?) {
        var offset = 0
        for section in sections {
            if row == offset { return (section.title, nil) }
            offset += 1
            let local = row - offset
            if local < section.items.count { return (nil, section.items[local]) }
            offset += section.items.count
        }
        return (nil, nil)
    }
}

extension TransferQueueViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        sections.reduce(0) { $0 + $1.items.count + 1 }
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        resolve(row: row).title != nil
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let r = resolve(row: row)
        if let title = r.title {
            let l = NSTextField(labelWithString: title)
            l.font = .boldSystemFont(ofSize: 11); l.textColor = .secondaryLabelColor; return l
        }
        guard let item = r.item else { return nil }
        let cell = NSTableCellView()
        var text = ""
        switch tableColumn?.identifier.rawValue {
        case "Name":     text = item.files.first?.name ?? "—"
        case "Status":   text = item.status.rawValue.capitalized
        case "Progress": text = String(format: "%.0f%%", item.overallPercentage)
        case "Speed":    text = item.currentSpeedFormatted
        case "ETA":      text = item.estimatedTimeRemainingFormatted
        default: break
        }
        let l = NSTextField(labelWithString: text)
        l.translatesAutoresizingMaskIntoConstraints = false; l.font = .systemFont(ofSize: 12)
        cell.addSubview(l)
        NSLayoutConstraint.activate([l.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                                     l.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4)])
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        resolve(row: row).title != nil ? 22 : 36
    }
}
