import UIKit

class SettingsAccountHelper {
    func numberOfRows() -> Int {
        return GitHub.shared().isSignedIn() ? 2 : 1
    }

    func tableView(_ tableView: UITableView, cellForRow: Int) -> UITableViewCell {
        guard GitHub.shared().isSignedIn() else {
            let identifier = "SettingsCell"
            let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
                ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
            cell.separatorInset = UIEdgeInsets(top: 0, left: 15.0, bottom: 0, right: 0)
            cell.textLabel?.text = "登录 GitHub"
            cell.textLabel?.textColor = .label
            cell.detailTextLabel?.text = "可选，登录后可自动同步健康数据"
            cell.imageView?.image = UIImage(systemName: "person.crop.circle.badge.plus")
            cell.imageView?.tintColor = .label
            cell.accessoryType = .disclosureIndicator
            return cell
        }

        switch cellForRow {
        case 0:
            let identifier = "AccountCell"
            let cell = tableView.dequeueReusableCell(withIdentifier: identifier) as? AccountCell
            let username = GitHub.shared().returnAuthenticatedUsername()
            let avatarURL = "https://github.com/\(username).png?size=102"
            cell?.avatarView.sd_setImage(with: URL(string: avatarURL), completed: nil)

            let fullname = GitHub.shared().fullname()
            if fullname == nil || fullname!.isEmpty {
                cell?.nameLabel.text = "@\(GitHub.shared().username() ?? "")"
                cell?.loginLabel.text = repositoryConfigurationText()
            } else {
                cell?.nameLabel.text = GitHub.shared().fullname() ?? ""
                cell?.loginLabel.text = repositoryConfigurationText()
            }
            cell?.accessoryType = UserDefaults.standard.bool(forKey: UserDefaultKeys.setupFinished)
                ? .none
                : .disclosureIndicator
            return cell!
        default:
            let identifier = "SettingsCell"
            let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell.init(style: .subtitle, reuseIdentifier: identifier)
            cell.separatorInset = UIEdgeInsets.init(top: 0, left: 15.0, bottom: 0, right: 0)
            cell.textLabel?.text = "退出登录"
            cell.textLabel?.textColor = UIColor.systemRed
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRow: Int, viewController: SettingsViewController) {
        guard GitHub.shared().isSignedIn() else {
            presentGitHubSetup(viewController: viewController)
            return
        }

        switch didSelectRow {
        case 0:
            if !UserDefaults.standard.bool(forKey: UserDefaultKeys.setupFinished) {
                presentGitHubSetup(viewController: viewController)
            }
        case 1:
            GitHub.shared().signOut()
            Health.shared().healthStore?.disableAllBackgroundDelivery { _, _ in }
            UserDefaults.standard.set(false, forKey: UserDefaultKeys.setupFinished)
            UserDefaults.standard.synchronize()
            viewController.dismiss(animated: false) {
                NotificationCenter.default.post(name: .didSignOut, object: nil)
            }
        default:
            break
        }
    }

    private func repositoryConfigurationText() -> String {
        let username = "@\(GitHub.shared().username() ?? "")"
        if UserDefaults.standard.bool(forKey: UserDefaultKeys.setupFinished) {
            return username
        }
        return "\(username) · 尚未连接健康仓库"
    }

    private func presentGitHubSetup(viewController: SettingsViewController) {
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
        guard let setup = storyboard.instantiateViewController(
            withIdentifier: "SetupPageViewController"
        ) as? SetupPageViewController else {
            return
        }
        setup.startsAtGitHub = true
        setup.modalPresentationStyle = .fullScreen
        viewController.present(setup, animated: true)
    }
}
