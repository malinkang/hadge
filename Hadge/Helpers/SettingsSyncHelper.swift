import UIKit

class SettingsSyncHelper: NSObject {
    func numberOfRows() -> Int {
        return HealthExportModule.allCases.count + 1
    }

    func tableView(_ tableView: UITableView, cellForRow: Int) -> UITableViewCell {
        let identifier = "SettingsCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell.init(style: .subtitle, reuseIdentifier: identifier)
        cell.separatorInset = UIEdgeInsets.init(top: 0, left: 15.0, bottom: 0, right: 0)

        switch cellForRow {
        case 0:
            cell.textLabel?.text = "Re-upload all data"
            cell.detailTextLabel?.text = nil
            cell.accessoryView = nil
        default:
            let module = HealthExportModule.allCases[cellForRow - 1]
            cell.textLabel?.text = module.title
            cell.detailTextLabel?.text = "Export to \(module.rawValue)/YYYY.csv"
            let toggle = UISwitch()
            toggle.isOn = module.isEnabled
            toggle.accessibilityIdentifier = module.rawValue
            toggle.addTarget(self, action: #selector(moduleSwitchChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRow: Int, viewController: SettingsViewController) {
        switch didSelectRow {
        case 0:
            NotificationCenter.default.addObserver(viewController, selector: #selector(SettingsViewController.didFinishUpload), name: .didSetUpRepository, object: nil)
            viewController.performSegue(withIdentifier: "UploadSegue", sender: self)
        default: // No op
            break
        }
    }

    @objc func moduleSwitchChanged(_ sender: UISwitch) {
        guard
            let identifier = sender.accessibilityIdentifier,
            let module = HealthExportModule(rawValue: identifier)
        else { return }
        module.setEnabled(sender.isOn)
        if sender.isOn {
            Health.shared().requestAuthorization(for: [module]) { _ in }
        }
    }
}
