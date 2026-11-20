import UIKit
import HealthKit

final class AppTabBarController: UITabBarController {
    private var didConfigureTabs = false

    init(workoutsNavigationController: UINavigationController) {
        super.init(nibName: nil, bundle: nil)
        configureTabs(workoutsNavigationController: workoutsNavigationController)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(setupFinished),
            name: .didSetUpRepository,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(signedOut),
            name: .didSignOut,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureAppearance()
        if !didConfigureTabs {
            let storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
            guard let workouts = storyboard.instantiateInitialViewController() as? UINavigationController else {
                return
            }
            configureTabs(workoutsNavigationController: workouts)
        }
        selectedIndex = UserDefaults.standard.bool(forKey: UserDefaultKeys.setupFinished) ? 0 : 1
        if let argument = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix("--tab=")
        }), let index = Int(argument.dropFirst("--tab=".count)), (0..<4).contains(index) {
            selectedIndex = index
        } else if let value = ProcessInfo.processInfo.environment["HADGE_INITIAL_TAB"],
                  let index = Int(value),
                  (0..<4).contains(index) {
            selectedIndex = index
        }
    }

    private func configureTabs(workoutsNavigationController: UINavigationController) {
        didConfigureTabs = true

        let overview = EntireNavigationController(
            rootViewController: DashboardOverviewViewController()
        )
        overview.tabBarItem = UITabBarItem(
            title: "概览",
            image: UIImage(systemName: "square.grid.2x2"),
            selectedImage: UIImage(systemName: "square.grid.2x2.fill")
        )

        workoutsNavigationController.tabBarItem = UITabBarItem(
            title: "运动",
            image: UIImage(systemName: "figure.run"),
            selectedImage: UIImage(systemName: "figure.run")
        )

        let health = EntireNavigationController(
            rootViewController: HealthDashboardViewController()
        )
        health.tabBarItem = UITabBarItem(
            title: "健康",
            image: UIImage(systemName: "heart.text.square"),
            selectedImage: UIImage(systemName: "heart.text.square.fill")
        )

        let storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
        let settingsController = storyboard.instantiateViewController(
            withIdentifier: "SettingsViewController"
        )
        settingsController.navigationItem.rightBarButtonItem = nil
        let settings = EntireNavigationController(rootViewController: settingsController)
        settings.tabBarItem = UITabBarItem(
            title: "设置",
            image: UIImage(systemName: "gearshape"),
            selectedImage: UIImage(systemName: "gearshape.fill")
        )

        setViewControllers(
            [overview, workoutsNavigationController, health, settings],
            animated: false
        )
    }

    private func configureAppearance() {
        tabBar.tintColor = DashboardPalette.green
        tabBar.unselectedItemTintColor = .secondaryLabel
        tabBar.isTranslucent = true

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        appearance.shadowColor = UIColor.separator.withAlphaComponent(0.28)
        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }
    }

    @objc private func setupFinished() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.selectedIndex = 0
        }
    }

    @objc private func signedOut() {
        selectedIndex = 1
    }
}

final class DashboardOverviewViewController: EntireViewController {
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let dateLabel = UILabel()
    private let syncLabel = UILabel()
    private let ringsView = ActivityRingsView()
    private let ringsTitleLabel = UILabel()
    private let ringSummaryLabel = UILabel()
    private let moveLabel = UILabel()
    private let exerciseLabel = UILabel()
    private let standLabel = UILabel()
    private let stepsCard = DashboardMetricCard(title: "步数", symbol: "shoeprints.fill", tint: .systemGreen)
    private let sleepCard = DashboardMetricCard(title: "睡眠", symbol: "moon.zzz.fill", tint: DashboardPalette.purple)
    private let waterCard = DashboardMetricCard(title: "饮水", symbol: "drop.fill", tint: DashboardPalette.blue)
    private let workoutCard = DashboardMetricCard(title: "跑步", symbol: "figure.run", tint: DashboardPalette.green)
    private let heatmapView = AnnualHeatmapView()
    private let recentStack = UIStackView()
    private var hasLoaded = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DashboardPalette.pageBackground
        configureView()
        observeHealthChanges()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        if !hasLoaded {
            reloadData()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DashboardHealthData.shared.requestAuthorization { [weak self] in
            DispatchQueue.main.async {
                self?.reloadData()
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .always
        scrollView.refreshControl = UIRefreshControl()
        scrollView.refreshControl?.addTarget(
            self,
            action: #selector(refreshRequested),
            for: .valueChanged
        )
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 14
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 14),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])

        contentStack.addArrangedSubview(makeHeader())
        contentStack.addArrangedSubview(makeRingsCard())
        contentStack.addArrangedSubview(makeMetricGrid())
        contentStack.addArrangedSubview(makeSectionHeader(title: "年度跑步热力图", detail: "\(currentYear) 年"))
        contentStack.addArrangedSubview(makeCard(containing: heatmapView))
        contentStack.addArrangedSubview(makeSectionHeader(title: "最近运动", detail: "Apple 健康"))
        contentStack.addArrangedSubview(makeCard(containing: recentStack))
    }

    private func makeHeader() -> UIView {
        let title = UILabel()
        title.text = "概览"
        title.font = .systemFont(ofSize: 34, weight: .bold)
        title.textColor = .label

        dateLabel.text = DashboardFormatters.ChineseDate.string(from: Date())
        dateLabel.font = .preferredFont(forTextStyle: .subheadline)
        dateLabel.textColor = .secondaryLabel

        syncLabel.text = syncText()
        syncLabel.font = .systemFont(ofSize: 11, weight: .medium)
        syncLabel.textColor = DashboardPalette.green
        syncLabel.textAlignment = .right
        syncLabel.numberOfLines = 2

        let titleStack = UIStackView(arrangedSubviews: [title, dateLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 1
        let row = UIStackView(arrangedSubviews: [titleStack, syncLabel])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 12
        return row
    }

    private func makeRingsCard() -> UIView {
        ringsView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            ringsView.widthAnchor.constraint(equalToConstant: 116),
            ringsView.heightAnchor.constraint(equalToConstant: 116)
        ])

        ringsTitleLabel.text = "今日圆环"
        ringsTitleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        ringsTitleLabel.textColor = .secondaryLabel

        ringSummaryLabel.text = "等待 Apple 健康数据"
        ringSummaryLabel.font = .systemFont(ofSize: 19, weight: .semibold)
        ringSummaryLabel.textColor = .label

        [moveLabel, exerciseLabel, standLabel].forEach {
            $0.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            $0.textColor = .secondaryLabel
            $0.text = "—"
        }
        let details = UIStackView(arrangedSubviews: [moveLabel, exerciseLabel, standLabel])
        details.axis = .vertical
        details.spacing = 5
        let copy = UIStackView(arrangedSubviews: [ringsTitleLabel, ringSummaryLabel, details])
        copy.axis = .vertical
        copy.spacing = 5

        let row = UIStackView(arrangedSubviews: [ringsView, copy])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 16
        return makeCard(containing: row, padding: 14)
    }

    private func makeMetricGrid() -> UIView {
        let firstRow = UIStackView(arrangedSubviews: [stepsCard, sleepCard])
        firstRow.axis = .horizontal
        firstRow.distribution = .fillEqually
        firstRow.spacing = 9

        let secondRow = UIStackView(arrangedSubviews: [waterCard, workoutCard])
        secondRow.axis = .horizontal
        secondRow.distribution = .fillEqually
        secondRow.spacing = 9

        let stack = UIStackView(arrangedSubviews: [firstRow, secondRow])
        stack.axis = .vertical
        stack.spacing = 9
        return stack
    }

    private func makeSectionHeader(title: String, detail: String) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .label
        let detailLabel = UILabel()
        detailLabel.text = detail
        detailLabel.font = .systemFont(ofSize: 10, weight: .medium)
        detailLabel.textColor = .secondaryLabel
        let row = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        row.axis = .horizontal
        row.alignment = .firstBaseline
        return row
    }

    private func makeCard(containing content: UIView, padding: CGFloat = 12) -> UIView {
        let card = UIView()
        card.backgroundColor = DashboardPalette.cardBackground
        card.layer.cornerRadius = 22
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.separator.withAlphaComponent(0.16).cgColor
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: padding),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -padding),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: padding),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -padding)
        ])
        return card
    }

    private func reloadData() {
        hasLoaded = true
        syncLabel.text = syncText()
        let year = currentYear
        loadActivityRings()
        loadMetric(.steps, update: stepsCard)
        loadMetric(.water, update: waterCard)
        loadMetric(.sleep, update: sleepCard)
        loadWorkouts(year: year)
    }

    private func loadActivityRings() {
        DashboardHealthData.shared.loadLatestActivityRings { [weak self] rings in
            guard let self = self else { return }
            guard let rings = rings else {
                self.ringsTitleLabel.text = "今日圆环"
                self.ringsView.setProgress(move: 0, exercise: 0, stand: 0)
                return
            }
            self.ringsView.setProgress(
                move: rings.moveProgress,
                exercise: rings.exerciseProgress,
                stand: rings.standProgress
            )
            self.ringsTitleLabel.text = DashboardCalendar.calendar.isDateInToday(rings.date)
                ? "今日圆环"
                : "最近圆环 · \(DashboardFormatters.MonthDay.string(from: rings.date))"
            self.moveLabel.text = String(format: "活动  %.0f / %.0f kcal", rings.move, rings.moveGoal)
            self.exerciseLabel.text = String(
                format: "锻炼  %.0f / %.0f 分钟",
                rings.exercise,
                rings.exerciseGoal
            )
            self.standLabel.text = String(format: "站立  %.0f / %.0f 小时", rings.stand, rings.standGoal)
            let completion = (rings.moveProgress + rings.exerciseProgress + rings.standProgress) / 3
            self.ringSummaryLabel.text = "\(Int((completion * 100).rounded()))% 完成"
        }
    }

    private func loadMetric(_ metric: DashboardHealthMetric, update card: DashboardMetricCard) {
        DashboardHealthData.shared.load(metric: metric, year: currentYear) { records in
            let latest = records.last
            switch metric {
            case .sleep:
                card.configure(
                    value: latest.map { DashboardFormatters.duration(minutes: $0.value) } ?? "暂无数据",
                    caption: latest.map { DashboardFormatters.MonthDay.string(from: $0.date) } ?? "等待健康授权"
                )
            case .steps:
                card.configure(
                    value: latest.map { Int($0.value.rounded()).formatted() } ?? "暂无数据",
                    caption: latest.map { "\(DashboardFormatters.MonthDay.string(from: $0.date)) · 步" } ?? "等待健康授权"
                )
            case .water:
                card.configure(
                    value: latest.map { String(format: "%.1f L", $0.value / 1_000) } ?? "暂无数据",
                    caption: latest.map { DashboardFormatters.MonthDay.string(from: $0.date) } ?? "等待健康授权"
                )
            case .rings:
                break
            }
        }
    }

    private func loadWorkouts(year: Int) {
        let interval = DashboardCalendar.yearInterval(year)
        Health.shared().getWorkoutsForDates(start: interval.start, end: interval.end) { [weak self] samples in
            guard let self = self else { return }
            let workouts = (samples as? [HKWorkout] ?? []).filter {
                $0.workoutActivityType == .running
            }.sorted { $0.startDate > $1.startDate }
            DispatchQueue.main.async {
                let latest = workouts.first
                self.workoutCard.configure(
                    value: latest.map { WorkoutPresentation.distance(for: $0) } ?? "暂无数据",
                    caption: latest.map {
                        DashboardFormatters.MonthDay.string(from: $0.startDate)
                    } ?? "等待健康授权"
                )
                self.heatmapView.configure(
                    year: year,
                    records: self.workoutRecords(workouts),
                    style: .workout
                )
                self.renderRecentWorkouts(Array(workouts.prefix(3)))
            }
        }
    }

    private func workoutRecords(_ workouts: [HKWorkout]) -> [DailyHealthMetric] {
        let calendar = DashboardCalendar.calendar
        let grouped = Dictionary(grouping: workouts) {
            calendar.startOfDay(for: $0.startDate)
        }
        return grouped.compactMap { date, workouts in
            let meters = workouts.reduce(0.0) {
                $0 + ($1.totalDistance?.doubleValue(for: .meter()) ?? 0)
            }
            guard meters > 0 else { return nil }
            return DailyHealthMetric(date: date, value: meters / 1_000)
        }.sorted { $0.date < $1.date }
    }

    private func renderRecentWorkouts(_ workouts: [HKWorkout]) {
        recentStack.arrangedSubviews.forEach {
            recentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        recentStack.axis = .vertical
        recentStack.spacing = 0
        guard !workouts.isEmpty else {
            recentStack.addArrangedSubview(emptyLabel("还没有跑步记录"))
            return
        }
        workouts.forEach { workout in
            recentStack.addArrangedSubview(DashboardActivityRow(workout: workout))
        }
    }

    private func emptyLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.textAlignment = .center
        return label
    }

    private func syncText() -> String {
        guard let date = UserDefaults.standard.object(forKey: UserDefaultKeys.lastSyncDate) as? Date else {
            return "尚未同步"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return "同步于 \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    private var currentYear: Int {
        DashboardCalendar.calendar.component(.year, from: Date())
    }

    private func observeHealthChanges() {
        [
            Notification.Name.didReceiveHealthAccess,
            .didFinishExport,
            .didSetUpRepository
        ].forEach {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(healthDataChanged),
                name: $0,
                object: nil
            )
        }
    }

    @objc private func refreshRequested() {
        reloadData()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.scrollView.refreshControl?.endRefreshing()
        }
    }

    @objc private func healthDataChanged() {
        reloadData()
    }
}

final class HealthDashboardViewController: EntireViewController {
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let metricControl = UISegmentedControl(
        items: DashboardHealthMetric.allCases.map(\.title)
    )
    private let heroTitleLabel = UILabel()
    private let heroValueLabel = UILabel()
    private let heroCaptionLabel = UILabel()
    private let recentStack = UIStackView()
    private let heatmapView = AnnualHeatmapView()
    private var selectedMetric: DashboardHealthMetric = .sleep
    private var selectedYear = DashboardCalendar.calendar.component(.year, from: Date())
    private var records: [DailyHealthMetric] = []
    private var requestToken = UUID()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DashboardPalette.pageBackground
        configureView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        reloadData()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DashboardHealthData.shared.requestAuthorization { [weak self] in
            DispatchQueue.main.async {
                self?.reloadData()
            }
        }
    }

    private func configureView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .always
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 14
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 14),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])

        contentStack.addArrangedSubview(makeHeader())
        contentStack.addArrangedSubview(makeMetricSelector())
        contentStack.addArrangedSubview(makeHeroCard())
        contentStack.addArrangedSubview(makeHeatmapCard())
        contentStack.addArrangedSubview(makeRecentCard())
    }

    private func makeHeader() -> UIView {
        let title = UILabel()
        title.text = "健康"
        title.font = .systemFont(ofSize: 34, weight: .bold)
        title.textColor = .label
        let subtitle = UILabel()
        subtitle.text = "Apple 健康 · 实时读取"
        subtitle.font = .preferredFont(forTextStyle: .subheadline)
        subtitle.textColor = .secondaryLabel
        let titleStack = UIStackView(arrangedSubviews: [title, subtitle])
        titleStack.axis = .vertical
        titleStack.spacing = 1
        return titleStack
    }

    private func makeMetricSelector() -> UIView {
        metricControl.selectedSegmentIndex = selectedMetric.rawValue
        metricControl.selectedSegmentTintColor = DashboardPalette.purple
        metricControl.setTitleTextAttributes(
            [.foregroundColor: UIColor.white],
            for: .selected
        )
        metricControl.setTitleTextAttributes(
            [.font: UIFont.systemFont(ofSize: 12, weight: .semibold)],
            for: .normal
        )
        metricControl.addTarget(self, action: #selector(metricChanged), for: .valueChanged)
        return metricControl
    }

    private func makeHeroCard() -> UIView {
        heroTitleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        heroTitleLabel.textColor = .secondaryLabel
        heroValueLabel.font = .systemFont(ofSize: 28, weight: .bold)
        heroValueLabel.textColor = .label
        heroValueLabel.adjustsFontSizeToFitWidth = true
        heroValueLabel.minimumScaleFactor = 0.65
        heroCaptionLabel.font = .preferredFont(forTextStyle: .footnote)
        heroCaptionLabel.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [heroTitleLabel, heroValueLabel, heroCaptionLabel])
        stack.axis = .vertical
        stack.spacing = 5
        return makeCard(containing: stack, background: DashboardPalette.elevatedBackground)
    }

    private func makeHeatmapCard() -> UIView {
        heatmapView.onYearChanged = { [weak self] year in
            self?.selectedYear = year
            self?.reloadData()
        }
        heatmapView.onDateSelected = { [weak self] date in
            guard let self = self else { return }
            self.updateHero(for: date)
        }
        return makeCard(containing: heatmapView)
    }

    private func makeRecentCard() -> UIView {
        let header = UILabel()
        header.text = "最近记录"
        header.font = .systemFont(ofSize: 14, weight: .semibold)
        header.textColor = .label
        let stack = UIStackView(arrangedSubviews: [header, recentStack])
        stack.axis = .vertical
        stack.spacing = 9
        return makeCard(containing: stack)
    }

    private func makeCard(
        containing content: UIView,
        background: UIColor = DashboardPalette.cardBackground
    ) -> UIView {
        let card = UIView()
        card.backgroundColor = background
        card.layer.cornerRadius = 22
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.separator.withAlphaComponent(0.16).cgColor
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        return card
    }

    private func reloadData() {
        let token = UUID()
        requestToken = token
        heroTitleLabel.text = "\(selectedMetric.title) · \(selectedYear) 年"
        heroValueLabel.text = "正在读取…"
        heroCaptionLabel.text = "数据来自 Apple HealthKit"

        DashboardHealthData.shared.load(metric: selectedMetric, year: selectedYear) { [weak self] records in
            guard let self = self, self.requestToken == token else { return }
            self.records = records.sorted { $0.date < $1.date }
            self.heatmapView.configure(
                year: self.selectedYear,
                records: self.records,
                style: self.heatmapStyle,
                selectedDate: self.records.last?.date
            )
            self.updateHero(for: self.records.last?.date ?? Date())
            self.renderRecentRecords()
        }
    }

    private var heatmapStyle: AnnualHeatmapStyle {
        switch selectedMetric {
        case .sleep: return .sleep
        case .steps: return .steps
        case .water: return .water
        case .rings: return .rings
        }
    }

    private func updateHero(for date: Date) {
        heroTitleLabel.text = "\(selectedMetric.title) · \(selectedYear) 年"
        guard let value = records.value(on: date) else {
            heroValueLabel.text = "没有记录"
            heroCaptionLabel.text = "\(DashboardFormatters.MonthDay.string(from: date)) · 未授权或当日无数据"
            return
        }
        heroValueLabel.text = formatted(value: value)
        let stats = statistics()
        heroCaptionLabel.text = "\(DashboardFormatters.MonthDay.string(from: date)) · \(stats)"
    }

    private func formatted(value: Double) -> String {
        switch selectedMetric {
        case .sleep:
            return DashboardFormatters.duration(minutes: value)
        case .steps:
            return "\(Int(value.rounded()).formatted()) 步"
        case .water:
            return String(format: "%.2f 升", value / 1_000)
        case .rings:
            return "\(Int((value * 100).rounded()))% 完成"
        }
    }

    private func statistics() -> String {
        guard !records.isEmpty else { return "暂无记录" }
        let total = records.reduce(0) { $0 + $1.value }
        let average = total / Double(records.count)
        let suffix: String
        switch selectedMetric {
        case .sleep:
            suffix = "共 \(records.count) 晚，平均 \(DashboardFormatters.duration(minutes: average))"
        case .steps:
            suffix = "共 \(records.count) 天，日均 \(Int(average.rounded()).formatted()) 步"
        case .water:
            suffix = String(format: "共 %d 天，日均 %.0f 毫升", records.count, average)
        case .rings:
            let closed = records.filter { $0.value >= 0.995 }.count
            suffix = "闭合 \(closed) 天，平均 \(Int((average * 100).rounded()))%"
        }
        return suffix
    }

    private func renderRecentRecords() {
        recentStack.arrangedSubviews.forEach {
            recentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        recentStack.axis = .vertical
        recentStack.spacing = 0
        guard !records.isEmpty else {
            let label = UILabel()
            label.text = "没有可展示的数据。请到“健康”App 允许 Hadge 读取\(selectedMetric.title)数据。"
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.textColor = .secondaryLabel
            label.numberOfLines = 0
            label.textAlignment = .center
            recentStack.addArrangedSubview(label)
            return
        }
        records.suffix(7).reversed().forEach { record in
            recentStack.addArrangedSubview(
                DashboardHealthRow(
                    date: record.date,
                    value: formatted(value: record.value),
                    metric: selectedMetric
                )
            )
        }
    }

    @objc private func metricChanged() {
        guard let metric = DashboardHealthMetric(rawValue: metricControl.selectedSegmentIndex) else {
            return
        }
        selectedMetric = metric
        reloadData()
    }
}

final class DashboardMetricCard: UIView {
    private let titleLabel = UILabel()
    private let iconView = UIImageView()
    private let valueLabel = UILabel()
    private let captionLabel = UILabel()
    private let tint: UIColor

    init(title: String, symbol: String, tint: UIColor) {
        self.tint = tint
        super.init(frame: .zero)
        titleLabel.text = title
        iconView.image = UIImage(systemName: symbol)
        configureView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(value: String, caption: String) {
        valueLabel.text = value
        captionLabel.text = caption
        accessibilityLabel = "\(titleLabel.text ?? "")，\(value)，\(caption)"
    }

    private func configureView() {
        backgroundColor = DashboardPalette.cardBackground
        layer.cornerRadius = 18
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.withAlphaComponent(0.16).cgColor

        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabel

        iconView.tintColor = tint
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16)
        ])

        let top = UIStackView(arrangedSubviews: [titleLabel, iconView])
        top.axis = .horizontal

        valueLabel.text = "—"
        valueLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        valueLabel.textColor = .label
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7

        captionLabel.text = "等待健康数据"
        captionLabel.font = .systemFont(ofSize: 9, weight: .medium)
        captionLabel.textColor = .secondaryLabel
        captionLabel.lineBreakMode = .byTruncatingTail

        let stack = UIStackView(arrangedSubviews: [top, valueLabel, captionLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 6
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 92)
        ])
        isAccessibilityElement = true
    }
}

final class DashboardActivityRow: UIView {
    init(workout: HKWorkout) {
        super.init(frame: .zero)
        configureView(workout: workout)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureView(workout: HKWorkout) {
        let icon = UIImageView(image: UIImage(systemName: "figure.run"))
        icon.tintColor = DashboardPalette.green
        icon.backgroundColor = DashboardPalette.green.withAlphaComponent(0.12)
        icon.layer.cornerRadius = 10
        icon.contentMode = .center
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = workout.workoutActivityType.name
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .label
        let subtitle = UILabel()
        subtitle.text = WorkoutPresentation.sourceAndTime(for: workout)
        subtitle.font = .preferredFont(forTextStyle: .caption1)
        subtitle.textColor = .secondaryLabel
        let titleStack = UIStackView(arrangedSubviews: [title, subtitle])
        titleStack.axis = .vertical
        titleStack.spacing = 2

        let value = UILabel()
        value.text = WorkoutPresentation.distance(for: workout)
        value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        value.textColor = .label
        value.textAlignment = .right
        let detail = UILabel()
        detail.text = WorkoutPresentation.duration(for: workout)
        detail.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        detail.textColor = DashboardPalette.green
        detail.textAlignment = .right
        let valueStack = UIStackView(arrangedSubviews: [value, detail])
        valueStack.axis = .vertical
        valueStack.spacing = 2

        let row = UIStackView(arrangedSubviews: [icon, titleStack, valueStack])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        addSubview(row)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 38),
            icon.heightAnchor.constraint(equalToConstant: 38),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
        isAccessibilityElement = true
        accessibilityLabel = "\(title.text ?? ""), \(value.text ?? "")"
    }
}

final class DashboardHealthRow: UIView {
    init(date: Date, value: String, metric: DashboardHealthMetric) {
        super.init(frame: .zero)
        configureView(date: date, value: value, metric: metric)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureView(date: Date, value: String, metric: DashboardHealthMetric) {
        let dot = UIView()
        dot.backgroundColor = metricColor(metric)
        dot.layer.cornerRadius = 5
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10)
        ])

        let dateLabel = UILabel()
        dateLabel.text = DashboardFormatters.MonthDay.string(from: date)
        dateLabel.font = .preferredFont(forTextStyle: .subheadline)
        dateLabel.textColor = .label

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        valueLabel.textColor = .secondaryLabel
        valueLabel.textAlignment = .right

        let row = UIStackView(arrangedSubviews: [dot, dateLabel, valueLabel])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 9
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }

    private func metricColor(_ metric: DashboardHealthMetric) -> UIColor {
        switch metric {
        case .sleep: return DashboardPalette.purple
        case .steps: return DashboardPalette.green
        case .water: return DashboardPalette.blue
        case .rings: return DashboardPalette.pink
        }
    }
}
