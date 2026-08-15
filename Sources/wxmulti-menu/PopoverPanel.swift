import AppKit
import Foundation

@MainActor
struct PanelModel {
    var runningSummary: String
    var rows: [PanelRowModel]
    var onCreate: () -> Void
    var onRefresh: () -> Void
    var onQuit: () -> Void
}

@MainActor
struct PanelRowModel {
    var id: String
    var title: String
    var detail: String
    var usage: String
    var status: String
    var statusColor: NSColor
    var accountIDs: [String]
    var isExpanded: Bool
    var actions: [PanelActionModel]
    var onToggle: () -> Void

    var renderKey: PanelRowRenderKey {
        PanelRowRenderKey(
            id: id,
            title: title,
            detail: detail,
            usage: usage,
            status: status,
            statusColorDescription: statusColor.description,
            accountIDs: accountIDs,
            isExpanded: isExpanded,
            actions: actions.map(\.renderKey)
        )
    }
}

@MainActor
struct PanelActionModel {
    enum Style {
        case normal
        case destroy
    }

    var title: String
    var style: Style
    var isEnabled = true
    var run: () -> Void

    var renderKey: PanelActionRenderKey {
        PanelActionRenderKey(title: title, style: style, isEnabled: isEnabled)
    }
}

struct PanelRowRenderKey: Equatable {
    var id: String
    var title: String
    var detail: String
    var usage: String
    var status: String
    var statusColorDescription: String
    var accountIDs: [String]
    var isExpanded: Bool
    var actions: [PanelActionRenderKey]
}

struct PanelActionRenderKey: Equatable {
    var title: String
    var style: PanelActionModel.Style
    var isEnabled: Bool
}

@MainActor
final class MultiWechatPanelViewController: NSViewController {
    private enum Layout {
        static let width: CGFloat = 500
        static let baseHeight: CGFloat = 118
        static let collapsedRowHeight: CGFloat = 42
        static let rowSpacing: CGFloat = 4
        static let detailsHeight: CGFloat = 58
        static let detailsReserve: CGFloat = detailsHeight + rowSpacing
        static let minHeight: CGFloat = 196
    }

    private var model: PanelModel
    private let summaryLabel = NSTextField(labelWithString: "")
    private let rowsStack = NSStackView()
    private var rowsHeightConstraint: NSLayoutConstraint?
    private var renderedRowKeys: [PanelRowRenderKey] = []

    init(model: PanelModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: Self.contentSize(rows: model.rows)))
        buildView()
    }

    func update(_ model: PanelModel) {
        self.model = model
        if isViewLoaded {
            let newSize = Self.contentSize(rows: model.rows)
            if view.frame.size != newSize {
                view.setFrameSize(newSize)
            }
            rowsHeightConstraint?.constant = Self.rowsHeight(rows: model.rows) + Layout.detailsReserve
            summaryLabel.stringValue = model.runningSummary
            renderRowsIfNeeded()
        }
    }

    static func contentSize(rows: [PanelRowModel]) -> NSSize {
        NSSize(width: Layout.width, height: max(Layout.minHeight, Layout.baseHeight + rowsHeight(rows: rows) + Layout.detailsReserve))
    }

    private static func rowsHeight(rows: [PanelRowModel]) -> CGFloat {
        guard !rows.isEmpty else {
            return 0
        }
        return CGFloat(rows.count) * Layout.collapsedRowHeight + CGFloat(rows.count - 1) * Layout.rowSpacing
    }

    private func buildView() {
        view.subviews.forEach { $0.removeFromSuperview() }

        let titleLabel = NSTextField(labelWithString: "MultiWechat")
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)

        summaryLabel.stringValue = model.runningSummary
        summaryLabel.font = .systemFont(ofSize: 11)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.lineBreakMode = .byTruncatingTail

        let titleBlock = NSStackView(views: [titleLabel, summaryLabel])
        titleBlock.orientation = .vertical
        titleBlock.alignment = .leading
        titleBlock.spacing = 2

        let createButton = PanelButton(title: "+ 新建", width: 64, action: model.onCreate)
        let header = NSStackView(views: [titleBlock, NSView(), createButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        rowsStack.orientation = .vertical
        rowsStack.alignment = .width
        rowsStack.spacing = Layout.rowSpacing
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        renderRows()

        let refreshButton = PanelButton(title: "刷新", width: 44, action: model.onRefresh)
        let quitButton = PanelButton(title: "退出", width: 44, action: model.onQuit)
        let footer = NSStackView(views: [NSView(), refreshButton, quitButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8

        for subview in [header, rowsStack, footer] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        rowsHeightConstraint = rowsStack.heightAnchor.constraint(equalToConstant: Self.rowsHeight(rows: model.rows) + Layout.detailsReserve)
        rowsHeightConstraint?.isActive = true
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),

            rowsStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            rowsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            rowsStack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),

            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
            rowsStack.bottomAnchor.constraint(lessThanOrEqualTo: footer.topAnchor, constant: -10),

            titleBlock.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
        ])
    }

    private func renderRowsIfNeeded() {
        let keys = model.rows.map(\.renderKey)
        guard keys != renderedRowKeys else {
            return
        }
        renderRows()
    }

    private func renderRows() {
        for subview in rowsStack.arrangedSubviews {
            rowsStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        for row in model.rows {
            let rowView = InstanceRowView(model: row)
            rowsStack.addArrangedSubview(rowView)
            rowView.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
            if row.isExpanded {
                let detailsView = InstanceDetailsView(model: row)
                rowsStack.addArrangedSubview(detailsView)
                detailsView.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
            }
        }
        renderedRowKeys = model.rows.map(\.renderKey)
    }
}

@MainActor
private final class InstanceRowView: NSView {
    private enum Layout {
        static let titleWidth: CGFloat = 158
        static let usageWidth: CGFloat = 70
        static let statusWidth: CGFloat = 68
        static let columnSpacing: CGFloat = 8
        static let statusToActionsMinSpacing: CGFloat = 10
        static let actionSpacing: CGFloat = 6
    }

    private let model: PanelRowModel
    private var disclosureButton: DisclosureButton?
    private var detailLabel: NSTextField?

    init(model: PanelRowModel) {
        self.model = model
        super.init(frame: .zero)
        buildView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func buildView() {
        translatesAutoresizingMaskIntoConstraints = false
        let disclosureButton = DisclosureButton(isExpanded: model.isExpanded, action: model.onToggle)
        self.disclosureButton = disclosureButton

        let titleLabel = NSTextField(labelWithString: model.title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        let detailLabel = NSTextField(labelWithString: model.isExpanded ? "" : model.detail)
        detailLabel.font = .systemFont(ofSize: 10.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        self.detailLabel = detailLabel

        let titleStack = NSStackView(views: [titleLabel, detailLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2
        let click = NSClickGestureRecognizer(target: self, action: #selector(toggleRow))
        click.buttonMask = 0x1
        titleStack.addGestureRecognizer(click)

        let usageLabel = NSTextField(labelWithString: model.usage)
        usageLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        usageLabel.textColor = .secondaryLabelColor
        usageLabel.alignment = .right
        usageLabel.lineBreakMode = .byTruncatingTail

        let statusDot = StatusDotView(color: model.statusColor)
        let statusLabel = NSTextField(labelWithString: model.status)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        let statusStack = NSStackView(views: [statusDot, statusLabel])
        statusStack.orientation = .horizontal
        statusStack.alignment = .centerY
        statusStack.spacing = 7

        let actionsStack = NSStackView()
        actionsStack.orientation = .horizontal
        actionsStack.alignment = .centerY
        actionsStack.spacing = Layout.actionSpacing
        for action in model.actions.prefix(1) {
            switch action.style {
            case .normal:
                actionsStack.addArrangedSubview(PanelButton(
                    title: action.title,
                    width: 40,
                    isEnabled: action.isEnabled,
                    action: action.run
                ))
            case .destroy:
                actionsStack.addArrangedSubview(DangerConfirmButton(
                    title: action.title,
                    isEnabled: action.isEnabled,
                    action: action.run
                ))
            }
        }

        for subview in [disclosureButton, titleStack, usageLabel, statusStack, actionsStack] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }

        let constraints = [
            heightAnchor.constraint(equalToConstant: 42),

            disclosureButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            disclosureButton.topAnchor.constraint(equalTo: topAnchor, constant: 10),

            titleStack.leadingAnchor.constraint(equalTo: disclosureButton.trailingAnchor, constant: 6),
            titleStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            titleStack.widthAnchor.constraint(equalToConstant: Layout.titleWidth),
            titleStack.heightAnchor.constraint(equalToConstant: 30),
            detailLabel.heightAnchor.constraint(equalToConstant: 13),

            usageLabel.leadingAnchor.constraint(equalTo: titleStack.trailingAnchor, constant: Layout.columnSpacing),
            usageLabel.centerYAnchor.constraint(equalTo: titleStack.centerYAnchor),
            usageLabel.widthAnchor.constraint(equalToConstant: Layout.usageWidth),

            statusStack.leadingAnchor.constraint(equalTo: usageLabel.trailingAnchor, constant: Layout.columnSpacing),
            statusStack.centerYAnchor.constraint(equalTo: titleStack.centerYAnchor),
            statusStack.widthAnchor.constraint(equalToConstant: Layout.statusWidth),

            actionsStack.leadingAnchor.constraint(greaterThanOrEqualTo: statusStack.trailingAnchor, constant: Layout.statusToActionsMinSpacing),
            actionsStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            actionsStack.centerYAnchor.constraint(equalTo: titleStack.centerYAnchor),
        ]

        NSLayoutConstraint.activate(constraints)
        setExpanded(model.isExpanded)
    }

    @objc private func toggleRow() {
        model.onToggle()
    }

    func setExpanded(_ isExpanded: Bool) {
        disclosureButton?.setExpanded(isExpanded)
        detailLabel?.stringValue = isExpanded ? "" : model.detail
    }
}

@MainActor
private final class InstanceDetailsView: NSView {
    private let model: PanelRowModel

    init(model: PanelRowModel) {
        self.model = model
        super.init(frame: .zero)
        buildView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func buildView() {
        translatesAutoresizingMaskIntoConstraints = false

        let accountsText = model.accountIDs.isEmpty ? "账号 未发现" : "账号 " + model.accountIDs.joined(separator: "、")
        let accountsLabel = NSTextField(labelWithString: accountsText)
        accountsLabel.font = .systemFont(ofSize: 11)
        accountsLabel.textColor = .secondaryLabelColor
        accountsLabel.lineBreakMode = .byTruncatingTail

        let actionsStack = NSStackView()
        actionsStack.orientation = .horizontal
        actionsStack.alignment = .centerY
        actionsStack.spacing = 6
        for action in model.actions.dropFirst() {
            switch action.style {
            case .normal:
                actionsStack.addArrangedSubview(PanelButton(
                    title: action.title,
                    width: 40,
                    isEnabled: action.isEnabled,
                    action: action.run
                ))
            case .destroy:
                actionsStack.addArrangedSubview(DangerConfirmButton(
                    title: action.title,
                    isEnabled: action.isEnabled,
                    action: action.run
                ))
            }
        }

        for subview in [accountsLabel, actionsStack] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 58),

            accountsLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            accountsLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            accountsLabel.topAnchor.constraint(equalTo: topAnchor),

            actionsStack.leadingAnchor.constraint(equalTo: accountsLabel.leadingAnchor),
            actionsStack.topAnchor.constraint(equalTo: accountsLabel.bottomAnchor, constant: 8),
        ])
    }
}

@MainActor
private final class DisclosureButton: NSButton {
    private let runAction: () -> Void

    init(isExpanded: Bool, action: @escaping () -> Void) {
        self.runAction = action
        super.init(frame: .zero)
        title = ""
        bezelStyle = .disclosure
        state = isExpanded ? .on : .off
        setButtonType(.pushOnPushOff)
        controlSize = .small
        target = self
        self.action = #selector(run)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 14).isActive = true
        heightAnchor.constraint(equalToConstant: 14).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    @objc private func run() {
        runAction()
    }

    func setExpanded(_ isExpanded: Bool) {
        state = isExpanded ? .on : .off
    }
}

@MainActor
private final class PanelButton: NSButton {
    private let runAction: () -> Void

    init(title: String, width: CGFloat, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.runAction = action
        super.init(frame: .zero)
        self.title = title
        self.isEnabled = isEnabled
        bezelStyle = .rounded
        controlSize = .small
        font = .systemFont(ofSize: 12)
        target = self
        self.action = #selector(run)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    @objc private func run() {
        runAction()
    }
}

@MainActor
private final class DangerConfirmButton: NSButton {
    private let normalTitle: String
    private let runAction: () -> Void
    private var isArmed = false
    private var resetTimer: Timer?

    init(title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.normalTitle = title
        self.runAction = action
        super.init(frame: .zero)
        self.isEnabled = isEnabled
        bezelStyle = .rounded
        controlSize = .small
        font = .systemFont(ofSize: 12)
        target = self
        self.action = #selector(run)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 40).isActive = true
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    @objc private func run() {
        if isArmed {
            resetTimer?.invalidate()
            resetTimer = nil
            runAction()
            return
        }
        isArmed = true
        updateAppearance()
        resetTimer?.invalidate()
        resetTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isArmed = false
                self?.updateAppearance()
            }
        }
    }

    private func updateAppearance() {
        if isArmed {
            title = "确认"
            contentTintColor = .systemRed
            bezelColor = NSColor.systemRed.withAlphaComponent(0.12)
        } else {
            title = normalTitle
            contentTintColor = nil
            bezelColor = nil
        }
    }
}

@MainActor
private final class StatusDotView: NSView {
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = 3
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 6).isActive = true
        heightAnchor.constraint(equalToConstant: 6).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
