import UIKit

class SettingsDebugHelper {
    var workoutSemaphore = false

    func tableView(_ tableView: UITableView, cellForRow: Int) -> UITableViewCell {
        let identifier = "SettingsCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell.init(style: .subtitle, reuseIdentifier: identifier)
        cell.separatorInset = UIEdgeInsets.init(top: 0, left: 15.0, bottom: 0, right: 0)

        switch cellForRow {
        case 0:
            cell.textLabel?.text = "下次刷新时强制上传"
        case 1:
            cell.textLabel?.text = "立即强制上传运动"
        case 2:
            cell.textLabel?.text = "下次启动显示设置流程"
        default:
            cell.textLabel?.text = "未定义"
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRow: Int, viewController: SettingsViewController) {
        switch didSelectRow {
        case 0:
            UserDefaults.standard.set(nil, forKey: UserDefaultKeys.lastWorkout)
            UserDefaults.standard.set(nil, forKey: UserDefaultKeys.lastSyncDate)
            UserDefaults.standard.set(nil, forKey: UserDefaultKeys.lastActivitySyncDate)
            UserDefaults.standard.synchronize()
        case 1:
            if workoutSemaphore { return }

            workoutSemaphore = true
            Health.shared().getWorkouts { workouts in
                guard let workouts = workouts, workouts.count > 0 else { return }

                let content = Health.shared().generateContentForWorkouts(workouts: workouts)
                let filename = "workouts/\(Health.shared().year).csv"
                GitHub.shared().updateFile(path: filename, content: content, message: "Update workouts") { _ in
                    self.workoutSemaphore = false
                }
            }
        case 2:
            UserDefaults.standard.set(false, forKey: UserDefaultKeys.setupFinished)
            UserDefaults.standard.synchronize()
        default: // No op
            break
        }
    }
}
