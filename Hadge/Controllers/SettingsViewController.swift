import UIKit
import SDWebImage

protocol ReusableViewEnum {}

extension ReusableViewEnum where Self: RawRepresentable, Self.RawValue == Int {
    static var all: [Self] {
        var index = 0
        var allItems = [Self]()
        while let item = Self(rawValue: index) {
            allItems.append(item)
            index += 1
        }
        return allItems
    }

    static func build(with value: Int) -> Self {
        guard let row = Self(rawValue: value) else {
            fatalError("Unimplemented value: \(value)")
        }
        return row
    }
}

private enum SettingsSections: Int, ReusableViewEnum {
    case account = 0
    case appearance
    case export
    case sync
    case about
    case debug
}

class SettingsViewController: EntireTableViewController {
    var accountHelper = SettingsAccountHelper()
    var appearanceHelper = SettingsAppearanceHelper()
    var debugHelper = SettingsDebugHelper()
    var aboutHelper = SettingsAboutHelper()
    var syncHelper = SettingsSyncHelper()
    var exportHelper = SettingsExportDestinationsHelper()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设置"
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return SettingsSections.all.count - debugOffset()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch SettingsSections.build(with: section) {
        case .account:
            return accountHelper.numberOfRows()
        case .appearance:
            return 3
        case .sync:
            return syncHelper.numberOfRows()
        case .export:
            return exportHelper.numberOfRows
        case .about:
            return 1
        case .debug:
            return 3
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch SettingsSections.build(with: indexPath.section) {
        case .account:
            return accountHelper.tableView(tableView, cellForRow: indexPath.row)
        case .appearance:
            appearanceHelper.overrideUserInterfaceStyle = self.overrideUserInterfaceStyle
            return appearanceHelper.tableView(tableView, cellForRow: indexPath.row)
        case .sync:
            return syncHelper.tableView(tableView, cellForRow: indexPath.row)
        case .export:
            return exportHelper.tableView(tableView, cellForRow: indexPath.row)
        case .about:
            return aboutHelper.tableView(tableView, cellForRow: indexPath.row)
        case .debug:
            return debugHelper.tableView(tableView, cellForRow: indexPath.row)
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch SettingsSections.build(with: indexPath.section) {
        case .account:
            accountHelper.tableView(tableView, didSelectRow: indexPath.row, viewController: self)
        case .appearance:
            appearanceHelper.tableView(tableView, didSelectRow: indexPath.row, viewController: self)
        case .sync:
            syncHelper.tableView(tableView, didSelectRow: indexPath.row, viewController: self)
        case .export:
            exportHelper.tableView(tableView, didSelectRow: indexPath.row, viewController: self)
        case .about:
            aboutHelper.tableView(tableView, didSelectRow: indexPath.row, viewController: self)
        case .debug:
            debugHelper.tableView(tableView, didSelectRow: indexPath.row, viewController: self)
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch SettingsSections.build(with: section) {
        case .account:
            return "账号"
        case .appearance:
            return "外观"
        case .sync:
            return "自动同步"
        case .export:
            return "数据导出"
        case .about:
            return "关于"
        case .debug:
            return "调试"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch SettingsSections.build(with: section) {
        case .account:
            return nil
        case .appearance:
            return nil
        case .sync:
            return "选择需要导出到 GitHub 的 HealthKit 数据。关闭模块只会停止后续上传，不会删除已有文件。重新上传会刷新所有可用年份的活动、距离、运动和健康数据。"
        case .export:
            return "GitHub 会上传到你的私有健康仓库；Notion 使用“同步 ID”增量更新模板；JSON 和 CSV 导出保存在本机并通过系统分享。Obsidian 入口将在后续版本提供。"
        case .about:
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            return "Hadge \(version!) (\(build!))\n健康数据只会上传到你在“数据导出”中选择的目的地。"
        case .debug:
            return "此区域只会在调试构建中显示。"
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "UploadSegue" {
            let setupViewController = segue.destination as? SetupViewController
            setupViewController?.delegate = self
        }
    }

    @IBAction func dismiss(_ sender: Any) {
        self.navigationController!.dismiss(animated: true)
    }

    @objc func didFinishUpload() {
        NotificationCenter.default.removeObserver(self, name: .didSetUpRepository, object: nil)
        tableView.reloadData()
    }

    func debugOffset() -> Int {
        return Constants.debug ? 0 : 1
    }
}

private enum SettingsExportDestination: Int, CaseIterable {
    case github
    case notion
    case obsidian
    case json
    case csv

    var title: String {
        switch self {
        case .github: return "GitHub"
        case .notion: return "Notion"
        case .obsidian: return "Obsidian"
        case .json: return "JSON"
        case .csv: return "CSV"
        }
    }

    var detail: String {
        switch self {
        case .github: return "同步到你的私有健康仓库"
        case .notion: return "导出到指定的 Notion 数据库"
        case .obsidian: return "导出到 Obsidian Vault"
        case .json: return "导出完整健康数据快照"
        case .csv: return "按数据类型导出表格文件"
        }
    }

    var symbolName: String {
        switch self {
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .notion: return "doc.text.fill"
        case .obsidian: return "diamond.fill"
        case .json: return "curlybraces"
        case .csv: return "tablecells"
        }
    }

    var tintColor: UIColor {
        switch self {
        case .github: return .label
        case .notion: return .systemBlue
        case .obsidian: return .systemPurple
        case .json: return .systemOrange
        case .csv: return .systemGreen
        }
    }

    var availabilityText: String {
        switch self {
        case .github, .notion, .json, .csv: return "已支持"
        case .obsidian: return "即将支持"
        }
    }
}

final class SettingsExportDestinationsHelper: NSObject {
    var numberOfRows: Int {
        SettingsExportDestination.allCases.count
    }

    func tableView(_ tableView: UITableView, cellForRow row: Int) -> UITableViewCell {
        guard let destination = SettingsExportDestination(rawValue: row) else {
            return UITableViewCell()
        }
        let identifier = "SettingsExportCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        cell.textLabel?.text = destination.title
        cell.detailTextLabel?.text = "\(destination.detail) · \(destination.availabilityText)"
        cell.imageView?.image = UIImage(systemName: destination.symbolName)
        cell.imageView?.tintColor = destination.tintColor
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityLabel = "\(destination.title)，\(destination.detail)，\(destination.availabilityText)"
        return cell
    }

    func tableView(
        _ tableView: UITableView,
        didSelectRow row: Int,
        viewController: SettingsViewController
    ) {
        guard let destination = SettingsExportDestination(rawValue: row) else {
            return
        }

        switch destination {
        case .github:
            exportToGitHub(from: viewController)
        case .notion:
            present(
                NotionExportViewController(),
                from: viewController
            )
        case .json:
            present(
                FileExportViewController(format: .json),
                from: viewController
            )
        case .csv:
            present(
                FileExportViewController(format: .csv),
                from: viewController
            )
        case .obsidian:
            let alert = UIAlertController(
                title: "Obsidian",
                message: "Obsidian Vault 导出入口将在后续版本提供。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "知道了", style: .default))
            viewController.present(alert, animated: true)
        }
    }

    private func exportToGitHub(from viewController: SettingsViewController) {
        guard GitHub.shared().isSignedIn() else {
            let storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
            guard let setup = storyboard.instantiateViewController(
                withIdentifier: "SetupPageViewController"
            ) as? SetupPageViewController else {
                return
            }
            setup.startsAtGitHub = true
            setup.modalPresentationStyle = .fullScreen
            viewController.present(setup, animated: true)
            return
        }

        NotificationCenter.default.addObserver(
            viewController,
            selector: #selector(SettingsViewController.didFinishUpload),
            name: .didSetUpRepository,
            object: nil
        )
        viewController.performSegue(
            withIdentifier: "UploadSegue",
            sender: self
        )
    }

    private func present(
        _ destination: UIViewController,
        from viewController: SettingsViewController
    ) {
        let navigation = UINavigationController(rootViewController: destination)
        navigation.navigationBar.prefersLargeTitles = false
        navigation.modalPresentationStyle = .pageSheet
        viewController.present(navigation, animated: true)
    }
}
