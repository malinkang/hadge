import UIKit

class SetupPageViewController: EntirePageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    var startsAtGitHub = false

    lazy var orderedViewControllers = [
        self.viewControllerForIdentifier("HealthRequestViewController"),
        self.viewControllerForIdentifier("LoginViewController")
    ]

    override func viewDidLoad() {
        super.viewDidLoad()

        self.isModalInPresentation = !startsAtGitHub
        self.dataSource = self
        self.delegate = self

        let appearance = UIPageControl.appearance(whenContainedInInstancesOf: [UIPageViewController.self])
        appearance.pageIndicatorTintColor = UIColor.secondaryLabel
        appearance.currentPageIndicatorTintColor = UIColor.label
        self.view.backgroundColor = UIColor.systemBackground

        let firstViewController = startsAtGitHub
            ? orderedViewControllers[1]
            : orderedViewControllers[0]
        setViewControllers([firstViewController], direction: .forward, animated: true, completion: nil)

        if startsAtGitHub {
            installDismissButton()
            DispatchQueue.main.async {
                self.view.subviews.compactMap { $0 as? UIPageControl }.forEach {
                    $0.isHidden = true
                }
            }
        }

        addObservers()
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let viewControllerIndex = orderedViewControllers.firstIndex(of: viewController) else { return nil }

        let previousIndex = viewControllerIndex - 1

        guard previousIndex >= 0 else { return nil }
        guard orderedViewControllers.count > previousIndex else { return nil }

        return orderedViewControllers[previousIndex]
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let viewControllerIndex = orderedViewControllers.firstIndex(of: viewController) else { return nil }

        let nextIndex = viewControllerIndex + 1
        let orderedViewControllersCount = orderedViewControllers.count

        guard orderedViewControllersCount != nextIndex else { return nil }
        guard orderedViewControllersCount > nextIndex else { return nil }

        return orderedViewControllers[nextIndex]
    }

    func viewControllerForIdentifier(_ identifier: String) -> UIViewController {
        return UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: identifier)
    }

    func presentationCount(for pageViewController: UIPageViewController) -> Int {
        return orderedViewControllers.count
    }

    func presentationIndex(for pageViewController: UIPageViewController) -> Int {
        guard let firstViewController = viewControllers?.first,
              let firstViewControllerIndex = orderedViewControllers.firstIndex(of: firstViewController) else {
                return 0
        }

        return firstViewControllerIndex
    }

    func addObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(forwardToLoginViewController), name: .didReceiveHealthAccess, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(forwardToSetupViewController), name: .didSignIn, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(forwardToInitialViewController), name: .didSetUpRepository, object: nil)
    }

    func removeObservers() {
        NotificationCenter.default.removeObserver(self, name: .didReceiveHealthAccess, object: nil)
        NotificationCenter.default.removeObserver(self, name: .didSignIn, object: nil)
        NotificationCenter.default.removeObserver(self, name: .didSetUpRepository, object: nil)
    }

    func goToNextPage(animated: Bool = true) {
        guard let currentViewController = self.viewControllers?.first else { return }
        guard let nextViewController = dataSource?.pageViewController(self, viewControllerAfter: currentViewController) else { return }
        setViewControllers([nextViewController], direction: .forward, animated: animated, completion: nil)
    }

    @objc func forwardToLoginViewController() {
        DispatchQueue.main.async {
            self.goToNextPage(animated: true)
        }
    }

    @objc func forwardToSetupViewController() {
        DispatchQueue.main.async {
            for subView in self.view.subviews where subView is UIPageControl {
                subView.isHidden = true
            }

            self.setViewControllers([self.viewControllerForIdentifier("SetupViewController")], direction: .forward, animated: true, completion: nil)
        }
    }

    @objc func forwardToInitialViewController() {
        DispatchQueue.main.async {
            self.removeObservers()
            self.dismiss(animated: true, completion: nil)
        }
    }

    @objc private func dismissSetup() {
        dismiss(animated: true)
    }

    private func installDismissButton() {
        let button = UIButton(type: .system)
        button.setTitle("稍后设置", for: .normal)
        button.setTitleColor(.secondaryLabel, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(dismissSetup), for: .touchUpInside)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            button.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            button.heightAnchor.constraint(equalToConstant: 36)
        ])
    }
}
