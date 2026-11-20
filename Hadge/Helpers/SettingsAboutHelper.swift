import UIKit

class SettingsAboutHelper {
    func tableView(_ tableView: UITableView, cellForRow: Int) -> UITableViewCell {
        let identifier = "AboutCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell.init(style: .subtitle, reuseIdentifier: identifier)
        cell.separatorInset = UIEdgeInsets.init(top: 0, left: 15.0, bottom: 0, right: 0)
        cell.accessoryType = .disclosureIndicator

        switch cellForRow {
        case 0:
            cell.accessoryView = UIImageView.init(image: UIImage.init(systemName: "link"))
            cell.textLabel?.text = "开源代码"
        default:
            cell.textLabel?.text = "未定义"
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRow: Int, viewController: SettingsViewController) {
        switch didSelectRow {
        case 0:
            UIApplication.shared.open(URL.init(string: "https://github.com/ashtom/hadge")!)
        default: // No op
            break
        }
    }
}
