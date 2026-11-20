import UIKit

// These screens are intentionally self-contained so the export flow can be
// presented from Settings without adding storyboard-only dependencies.
// swiftlint:disable file_length type_body_length function_body_length

final class FileExportViewController: UIViewController {
    private let format: HealthExportFileFormat
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let primaryButton = UIButton(type: .system)
    private var snapshot: HealthExportSnapshot?
    private var exportedURLs: [URL] = []
    private var snapshotBuilder: HealthExportSnapshotBuilder?
    private var hasStarted = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init(format: HealthExportFileFormat) {
        self.format = format
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "导出 \(format.displayName)"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "关闭",
            style: .done,
            target: self,
            action: #selector(close)
        )
        configureView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasStarted else { return }
        hasStarted = true
        beginExport()
    }

    deinit {
        endBackgroundTask()
    }

    private func configureView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 18
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor,
                constant: 24
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor,
                constant: -24
            ),
            contentStack.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor,
                constant: 32
            ),
            contentStack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor,
                constant: -32
            ),
            contentStack.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor,
                constant: -48
            )
        ])

        let card = makeCard()
        iconView.image = UIImage(
            systemName: format == .json ? "curlybraces" : "tablecells"
        )
        iconView.tintColor = format == .json ? .systemOrange : .systemGreen
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 50).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 50).isActive = true

        titleLabel.text = format == .json
            ? "正在整理完整健康快照"
            : "正在整理三份健康表格"
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.numberOfLines = 0

        detailLabel.text = format == .json
            ? "文件包含每日汇总、运动记录和已启用的原始 HealthKit 数据。"
            : "将生成每日健康、运动记录和原始健康数据三个 CSV 文件。"
        detailLabel.font = .preferredFont(forTextStyle: .body)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0

        activityIndicator.hidesWhenStopped = true
        statusLabel.text = "准备读取 Apple 健康"
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0

        let statusRow = UIStackView(
            arrangedSubviews: [activityIndicator, statusLabel]
        )
        statusRow.axis = .horizontal
        statusRow.alignment = .center
        statusRow.spacing = 10

        primaryButton.setTitle("生成文件", for: .normal)
        primaryButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        primaryButton.backgroundColor = format == .json
            ? .systemOrange
            : .systemGreen
        primaryButton.setTitleColor(.white, for: .normal)
        primaryButton.layer.cornerRadius = 14
        primaryButton.layer.cornerCurve = .continuous
        primaryButton.heightAnchor.constraint(equalToConstant: 52).isActive = true
        primaryButton.addTarget(
            self,
            action: #selector(primaryAction),
            for: .touchUpInside
        )
        primaryButton.isHidden = true

        let stack = UIStackView(arrangedSubviews: [
            iconView,
            titleLabel,
            detailLabel,
            statusRow,
            primaryButton
        ])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24)
        ])
        contentStack.addArrangedSubview(card)
    }

    private func beginExport() {
        activityIndicator.startAnimating()
        beginBackgroundTask()
        let builder = HealthExportSnapshotBuilder()
        snapshotBuilder = builder
        builder.build(includeRawRecords: true, progress: { [weak self] text in
            self?.statusLabel.text = text
        }) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.snapshotBuilder = nil
                switch result {
                case .failure(let error):
                    self.showFailure(error)
                case .success(let snapshot):
                    self.snapshot = snapshot
                    self.statusLabel.text = "正在写入 \(self.format.displayName) 文件"
                    self.write(snapshot: snapshot)
                }
            }
        }
    }

    private func write(snapshot: HealthExportSnapshot) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let urls = try HealthExportFileService.write(
                    snapshot: snapshot,
                    format: self.format
                )
                DispatchQueue.main.async {
                    self.showSuccess(snapshot: snapshot, urls: urls)
                }
            } catch {
                DispatchQueue.main.async {
                    self.showFailure(error)
                }
            }
        }
    }

    private func showSuccess(
        snapshot: HealthExportSnapshot,
        urls: [URL]
    ) {
        self.snapshot = snapshot
        self.exportedURLs = urls
        activityIndicator.stopAnimating()
        endBackgroundTask()
        titleLabel.text = "导出完成"
        statusLabel.text = [
            "\(snapshot.daily.count) 天每日健康",
            "\(snapshot.workouts.count) 条运动",
            snapshot.rawRecords.isEmpty
                ? nil
                : "\(snapshot.rawRecords.count) 条原始记录"
        ].compactMap { $0 }.joined(separator: " · ")
        primaryButton.setTitle(
            urls.count == 1 ? "分享文件" : "分享 \(urls.count) 个文件",
            for: .normal
        )
        primaryButton.isHidden = false
    }

    private func showFailure(_ error: Error) {
        activityIndicator.stopAnimating()
        endBackgroundTask()
        titleLabel.text = "导出未完成"
        statusLabel.text = error.localizedDescription
        primaryButton.setTitle("重试", for: .normal)
        primaryButton.isHidden = false
    }

    @objc private func primaryAction() {
        if exportedURLs.isEmpty {
            primaryButton.isHidden = true
            beginExport()
            return
        }

        let activity = UIActivityViewController(
            activityItems: exportedURLs,
            applicationActivities: nil
        )
        if let popover = activity.popoverPresentationController {
            popover.sourceView = primaryButton
            popover.sourceRect = primaryButton.bounds
        }
        present(activity, animated: true)
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    private func makeCard() -> UIView {
        let view = UIView()
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 22
        view.layer.cornerCurve = .continuous
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.06
        view.layer.shadowRadius = 20
        view.layer.shadowOffset = CGSize(width: 0, height: 8)
        return view
    }

    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "HadgeFileExport"
        ) { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}

final class NotionExportViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let tokenField = UITextField()
    private let templateField = UITextField()
    private let scopeControl = UISegmentedControl(
        items: NotionExportScope.allCases.map(\.title)
    )
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let syncButton = UIButton(type: .system)
    private let templateButton = UIButton(type: .system)
    private let integrationButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var snapshotBuilder: HealthExportSnapshotBuilder?
    private var notionExporter: NotionHealthExporter?
    private var isSyncing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "导入 Notion"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "关闭",
            style: .done,
            target: self,
            action: #selector(close)
        )
        configureView()
        loadConfiguration()
    }

    deinit {
        endBackgroundTask()
    }

    private func configureView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 18
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor,
                constant: 20
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor,
                constant: -20
            ),
            contentStack.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor,
                constant: 20
            ),
            contentStack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor,
                constant: -32
            ),
            contentStack.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor,
                constant: -40
            )
        ])

        let intro = makeCallout()
        contentStack.addArrangedSubview(intro)
        templateButton.setTitle("在 Notion 中打开模板", for: .normal)
        templateButton.contentHorizontalAlignment = .leading
        templateButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        templateButton.addTarget(
            self,
            action: #selector(openTemplate),
            for: .touchUpInside
        )
        contentStack.addArrangedSubview(templateButton)

        integrationButton.setTitle("打开 Notion 集成设置", for: .normal)
        integrationButton.contentHorizontalAlignment = .leading
        integrationButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        integrationButton.addTarget(
            self,
            action: #selector(openIntegrationSettings),
            for: .touchUpInside
        )
        contentStack.addArrangedSubview(integrationButton)

        tokenField.placeholder = "ntn_..."
        tokenField.textContentType = .password
        tokenField.autocorrectionType = .no
        tokenField.autocapitalizationType = .none
        tokenField.isSecureTextEntry = true
        tokenField.clearButtonMode = .whileEditing
        tokenField.accessibilityIdentifier = "notionTokenField"
        contentStack.addArrangedSubview(makeTextFieldCard(
            title: "集成 Token",
            detail: "在 Notion 集成设置中创建，并只保存在本机 Keychain。",
            field: tokenField
        ))

        templateField.placeholder = "粘贴复制后的 Hadge 健康模板页面链接"
        templateField.autocorrectionType = .no
        templateField.autocapitalizationType = .none
        templateField.keyboardType = .URL
        templateField.clearButtonMode = .whileEditing
        templateField.accessibilityIdentifier = "notionTemplateField"
        contentStack.addArrangedSubview(makeTextFieldCard(
            title: "模板页面",
            detail: "Hadge 会从页面中自动识别“每日健康”和“运动记录”数据库。",
            field: templateField
        ))

        let scopeCard = makeCard()
        let scopeTitle = UILabel()
        scopeTitle.text = "首次导入范围"
        scopeTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        let scopeDetail = UILabel()
        scopeDetail.text = "之后同步只更新最近 7 天，并按“同步 ID”更新已有记录。"
        scopeDetail.font = .preferredFont(forTextStyle: .footnote)
        scopeDetail.textColor = .secondaryLabel
        scopeDetail.numberOfLines = 0
        scopeControl.selectedSegmentIndex = NotionExportScope.all.rawValue
        scopeControl.accessibilityIdentifier = "notionScopeControl"
        let scopeStack = UIStackView(
            arrangedSubviews: [scopeTitle, scopeDetail, scopeControl]
        )
        scopeStack.axis = .vertical
        scopeStack.spacing = 10
        scopeStack.translatesAutoresizingMaskIntoConstraints = false
        scopeCard.addSubview(scopeStack)
        NSLayoutConstraint.activate([
            scopeStack.leadingAnchor.constraint(equalTo: scopeCard.leadingAnchor, constant: 18),
            scopeStack.trailingAnchor.constraint(equalTo: scopeCard.trailingAnchor, constant: -18),
            scopeStack.topAnchor.constraint(equalTo: scopeCard.topAnchor, constant: 18),
            scopeStack.bottomAnchor.constraint(equalTo: scopeCard.bottomAnchor, constant: -18)
        ])
        contentStack.addArrangedSubview(scopeCard)

        let statusRow = UIStackView(
            arrangedSubviews: [activityIndicator, statusLabel]
        )
        statusRow.axis = .horizontal
        statusRow.alignment = .center
        statusRow.spacing = 10
        activityIndicator.hidesWhenStopped = true
        statusLabel.text = "填写完成后即可开始增量同步。"
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        contentStack.addArrangedSubview(statusRow)

        syncButton.setTitle("开始同步", for: .normal)
        syncButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        syncButton.setTitleColor(.white, for: .normal)
        syncButton.backgroundColor = .systemBlue
        syncButton.layer.cornerRadius = 14
        syncButton.layer.cornerCurve = .continuous
        syncButton.heightAnchor.constraint(equalToConstant: 52).isActive = true
        syncButton.accessibilityIdentifier = "notionSyncButton"
        syncButton.addTarget(
            self,
            action: #selector(sync),
            for: .touchUpInside
        )
        contentStack.addArrangedSubview(syncButton)

        clearButton.setTitle("清除本机 Notion 凭证", for: .normal)
        clearButton.setTitleColor(.systemRed, for: .normal)
        clearButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        clearButton.addTarget(
            self,
            action: #selector(clearCredentials),
            for: .touchUpInside
        )
        contentStack.addArrangedSubview(clearButton)
    }

    private func loadConfiguration() {
        tokenField.text = NotionExportSettings.token
        templateField.text = NotionExportSettings.templateURL
        scopeControl.selectedSegmentIndex = NotionExportSettings.scope.rawValue
    }

    @objc private func sync() {
        guard !isSyncing else { return }
        view.endEditing(true)

        let token = tokenField.text?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else {
            presentMessage("缺少 Notion Token", "请先填写 Notion 集成 Token。")
            return
        }
        let pageValue = templateField.text ?? ""
        guard let pageID = NotionExportClient.normalizePageID(from: pageValue) else {
            presentMessage(
                "模板链接无效",
                "请粘贴“Hadge 健康模板”页面链接或 32 位页面 ID。"
            )
            return
        }
        let scope = NotionExportScope(
            rawValue: max(0, scopeControl.selectedSegmentIndex)
        ) ?? .all

        if NotionExportSettings.templatePageID != pageID {
            NotionExportSettings.lastSuccessfulSync = nil
            NotionExportSettings.lastScope = nil
        }
        NotionExportSettings.token = token
        NotionExportSettings.templatePageID = pageID
        NotionExportSettings.templateURL = pageValue
        NotionExportSettings.scope = scope

        isSyncing = true
        syncButton.isEnabled = false
        syncButton.alpha = 0.55
        activityIndicator.startAnimating()
        statusLabel.text = "准备读取 Apple 健康"
        beginBackgroundTask()

        let builder = HealthExportSnapshotBuilder()
        snapshotBuilder = builder
        builder.build(includeRawRecords: false, progress: { [weak self] text in
            self?.updateStatus(text)
        }) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.snapshotBuilder = nil
                switch result {
                case .failure(let error):
                    self.finishSync(error: error)
                case .success(let snapshot):
                    let exporter = NotionHealthExporter(
                        token: token,
                        pageID: pageID
                    )
                    self.notionExporter = exporter
                    exporter.sync(
                        snapshot: snapshot,
                        scope: scope,
                        progress: { [weak self] text in
                            self?.updateStatus(text)
                        },
                        completion: { [weak self] result in
                            DispatchQueue.main.async {
                                guard let self = self else { return }
                                self.notionExporter = nil
                                switch result {
                                case .failure(let error):
                                    self.finishSync(error: error)
                                case .success(let result):
                                    self.finishSync(result: result)
                                }
                            }
                        }
                    )
                }
            }
        }
    }

    private func updateStatus(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.text = text
        }
    }

    private func finishSync(result: NotionSyncResult) {
        isSyncing = false
        syncButton.isEnabled = true
        syncButton.alpha = 1
        activityIndicator.stopAnimating()
        endBackgroundTask()

        let message = result.total == 0
            ? "所选范围暂无新的健康记录。"
            : "新增 \(result.dailyCreated + result.workoutsCreated) 条，更新 \(result.dailyUpdated + result.workoutsUpdated) 条。"
        statusLabel.text = message
        let alert = UIAlertController(
            title: "Notion 同步完成",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "完成", style: .default))
        alert.addAction(UIAlertAction(
            title: "打开 Notion",
            style: .default,
            handler: { [weak self] _ in
                self?.openTemplate()
            }
        ))
        present(alert, animated: true)
    }

    private func finishSync(error: Error) {
        isSyncing = false
        syncButton.isEnabled = true
        syncButton.alpha = 1
        activityIndicator.stopAnimating()
        endBackgroundTask()
        statusLabel.text = error.localizedDescription
        presentMessage("Notion 同步失败", error.localizedDescription)
    }

    @objc private func openTemplate() {
        let value = templateField.text?.isEmpty == false
            ? templateField.text
            : NotionExportSettings.defaultTemplateURL
        guard
            let value = value,
            let url = URL(string: value)
        else {
            return
        }
        UIApplication.shared.open(url)
    }

    @objc private func openIntegrationSettings() {
        guard let url = URL(string: "https://www.notion.so/my-integrations") else {
            return
        }
        UIApplication.shared.open(url)
    }

    @objc private func clearCredentials() {
        let alert = UIAlertController(
            title: "清除 Notion 凭证？",
            message: "Token 和上次同步时间会从本机删除，Notion 中的数据不会受影响。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(
            title: "清除",
            style: .destructive,
            handler: { [weak self] _ in
                NotionExportSettings.clear()
                self?.tokenField.text = nil
                self?.statusLabel.text = "本机 Notion 凭证已清除。"
            }
        ))
        present(alert, animated: true)
    }

    @objc private func close() {
        guard !isSyncing else {
            presentMessage(
                "同步正在进行",
                "请等待当前同步完成后再关闭。"
            )
            return
        }
        dismiss(animated: true)
    }

    private func makeCallout() -> UIView {
        let card = makeCard()
        let icon = UIImageView(image: UIImage(systemName: "sparkles"))
        icon.tintColor = .systemBlue
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let text = UILabel()
        text.text = "Hadge 会把每日步数、饮水、睡眠、活动圆环和每条运动记录写入模板。复制模板页后，请把副本连接到同一个 Notion 集成；重复同步会更新原记录。"
        text.font = .preferredFont(forTextStyle: .body)
        text.textColor = .label
        text.numberOfLines = 0

        let row = UIStackView(arrangedSubviews: [icon, text])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])
        return card
    }

    private func makeTextFieldCard(
        title: String,
        detail: String,
        field: UITextField
    ) -> UIView {
        let card = makeCard()
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        let detailLabel = UILabel()
        detailLabel.text = detail
        detailLabel.font = .preferredFont(forTextStyle: .footnote)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 15)
        field.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let stack = UIStackView(
            arrangedSubviews: [titleLabel, detailLabel, field]
        )
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])
        return card
    }

    private func makeCard() -> UIView {
        let view = UIView()
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 18
        view.layer.cornerCurve = .continuous
        return view
    }

    private func presentMessage(_ title: String, _ message: String) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }

    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "HadgeNotionExport"
        ) { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
