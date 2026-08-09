import UIKit
import HealthKit

class HealthRequestViewController: EntireViewController {
    @IBOutlet weak var healthButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()

        healthButton.layer.cornerRadius = 4

        for subView in self.view.subviews where subView is UITextView {
            guard let textView = subView as? UITextView else { continue }
            textView.textContainerInset = UIEdgeInsets.init(top: 0, left: 0, bottom: 0, right: 0)
        }
    }

    @IBAction func requestHealthAccess(_ sender: Any) {
        let objectTypes = Health.shared().readObjectTypes()
        guard let healthStore = Health.shared().healthStore else { return }

        healthStore.getRequestStatusForAuthorization(toShare: [], read: objectTypes) { status, _ in
            switch status {
            case .unnecessary:
                self.finishHealthAuthorization()
            case .shouldRequest, .unknown:
                healthStore.requestAuthorization(toShare: [], read: objectTypes) { success, _ in
                    guard success else { return }
                    self.finishHealthAuthorization()
                }
            @unknown default:
                return
            }
        }
    }

    private func finishHealthAuthorization() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .didReceiveHealthAccess, object: nil)
        }
    }
}
