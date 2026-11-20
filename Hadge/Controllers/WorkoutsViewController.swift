import UIKit
import HealthKit
import SDWebImage
import SwiftDate

// swiftlint:disable:next type_body_length
class WorkoutsViewController: EntireTableViewController {
    var data: [[String: Any]] = []
    var filter: [UInt] = []
    var dataLoaded: Bool = false
    private var selectedDate = WorkoutPresentation.startOfDay(Date())
    private var selectedYear = DashboardCalendar.calendar.component(.year, from: Date())
    private var selectedFamily: WorkoutActivityFamily = .running
    private var allWorkouts: [HKWorkout] = []
    private var selectedWorkout: HKWorkout?
    private var journalHeader: WorkoutDashboardHeaderView?
    private var heroWorkout: HKWorkout?
    private var recentWorkouts: [HKWorkout] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        self.extendedLayoutIncludesOpaqueBars = true
        tableView.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.systemBackground
                : UIColor(red: 0.985, green: 0.982, blue: 0.965, alpha: 1)
        }
        tableView.separatorStyle = .none
        tableView.contentInsetAdjustmentBehavior = .always
        tableView.register(
            WorkoutJournalHeroCell.self,
            forCellReuseIdentifier: WorkoutJournalHeroCell.reuseIdentifier
        )
        tableView.register(
            WorkoutJournalTimelineCell.self,
            forCellReuseIdentifier: WorkoutJournalTimelineCell.reuseIdentifier
        )
        tableView.register(
            WorkoutJournalEmptyCell.self,
            forCellReuseIdentifier: WorkoutJournalEmptyCell.reuseIdentifier
        )

        setUpRefreshControl()
        restoreState()
        installJournalHeader()
        addObservers()
        tableView.reloadData()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        navigationController?.setToolbarHidden(true, animated: false)

        if GitHub.shared().isSignedIn()
            && UserDefaults.standard.bool(forKey: UserDefaultKeys.setupFinished)
            && !dataLoaded {
            GitHub.shared().refreshCurrentUser()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !dataLoaded {
            Health.shared().requestEnabledExportAuthorizationIfNeeded { _ in
                DispatchQueue.main.async {
                    self.loadData(false)
                }
            }
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "DetailSegue" {
            let workoutViewController = segue.destination as? WorkoutViewController
            workoutViewController?.workout = selectedWorkout
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? 1 : recentWorkouts.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            if !dataLoaded {
                guard let cell = tableView.dequeueJournalCell(
                    WorkoutJournalEmptyCell.self,
                    identifier: WorkoutJournalEmptyCell.reuseIdentifier,
                    for: indexPath
                ) else { return UITableViewCell() }
                cell.configure(title: "正在读取运动", subtitle: "正在从 Apple 健康获取最新记录…")
                return cell
            }

            if data.isEmpty {
                guard let cell = tableView.dequeueJournalCell(
                    WorkoutJournalEmptyCell.self,
                    identifier: WorkoutJournalEmptyCell.reuseIdentifier,
                    for: indexPath
                ) else { return UITableViewCell() }
                cell.configure(
                    title: "还没有\(selectedFamily.title)记录",
                    subtitle: "请确认“健康”App 中已允许 Hadge 读取体能训练数据。"
                )
                return cell
            }

            guard let workout = heroWorkout else {
                guard let cell = tableView.dequeueJournalCell(
                    WorkoutJournalEmptyCell.self,
                    identifier: WorkoutJournalEmptyCell.reuseIdentifier,
                    for: indexPath
                ) else { return UITableViewCell() }
                cell.configure(
                    title: "休息日",
                    subtitle: "这一天没有\(selectedFamily.title)记录，可以点击上方热力图切换日期。"
                )
                return cell
            }

            guard let cell = tableView.dequeueJournalCell(
                WorkoutJournalHeroCell.self,
                identifier: WorkoutJournalHeroCell.reuseIdentifier,
                for: indexPath
            ) else { return UITableViewCell() }
            cell.configure(with: workout)
            return cell
        }

        guard let cell = tableView.dequeueJournalCell(
            WorkoutJournalTimelineCell.self,
            identifier: WorkoutJournalTimelineCell.reuseIdentifier,
            for: indexPath
        ) else { return UITableViewCell() }
        cell.configure(with: recentWorkouts[indexPath.row])
        return cell
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = WorkoutJournalSectionHeaderView()
        if section == 0 {
            let date = "\(WorkoutPresentation.title(for: selectedDate)) · "
                + WorkoutPresentation.longDate(for: selectedDate)
            header.configure(title: date, subtitle: nil, isOverline: true)
        } else {
            header.configure(title: "最近运动", subtitle: "\(selectedYear) 年的\(selectedFamily.title)记录")
        }
        return header
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return section == 0 ? 34 : 64
    }

    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return section == 0 ? 4 : 20
    }

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        selectedWorkout = indexPath.section == 0 ? heroWorkout : recentWorkouts[indexPath.row]
        guard selectedWorkout != nil else { return }
        performSegue(withIdentifier: "DetailSegue", sender: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeJournalHeader()
    }

    @objc func didSignIn() {
        DispatchQueue.main.async {
            self.loadData(false)
        }
    }

    @objc func didSignOut() {
        DispatchQueue.main.async {
            self.refreshJournalHeader()
            self.tableView.reloadData()
        }
    }

    @objc func didChangeInterfaceStyle() {
        DispatchQueue.main.async {
            self.setInterfaceStyle()
            self.navigationController?.setInterfaceStyle()
        }
    }

    @objc func collectingActivityData() {
        updateStatusLabel("正在刷新活动数据…")
    }

    @objc func collectingDistanceData() {
        updateStatusLabel("正在刷新距离数据…")
    }

    @objc func collectingHealthData(_ notification: Notification) {
        let title = notification.object as? String ?? "健康数据"
        updateStatusLabel("正在刷新\(title)…")
    }

    @objc func didFinishExport() {
        let lastSyncDate = UserDefaults.standard.object(forKey: UserDefaultKeys.lastSyncDate) as? Date
        let formatter = DateFormatter.init()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        if lastSyncDate != nil && data.count > 0 {
            updateStatusLabel("已同步 \(formatter.string(from: lastSyncDate!))")
        } else {
            updateStatusLabel("尚未同步")
        }
    }

    @objc func refreshWasRequested(_ refreshControl: UIRefreshControl) {
        startRefreshing()
        loadData()
    }

    @objc func openSafari(sender: Any) {
        UIApplication.shared.open(URL.init(string: "https://github.com/\(GitHub.shared().username()!)/\(GitHub.defaultRepository)")!)
    }

    func startRefreshing(_ visible: Bool = true) {
        DispatchQueue.main.async {
            if self.tableView.refreshControl != nil && visible {
                self.tableView.refreshControl?.beginRefreshing()
            }

            self.journalHeader?.setSyncStatus("正在读取健康数据…", isActive: true)
        }
    }

    func updateStatusLabel(_ text: String) {
        DispatchQueue.main.async {
            self.journalHeader?.setSyncStatus(
                text,
                isActive: text.contains("刷新") || text.contains("读取")
            )
        }
    }

    func stopRefreshing(_ visible: Bool = true) {
        DispatchQueue.main.async {
            if self.tableView.refreshControl != nil {
                self.tableView.refreshControl?.endRefreshing()
            }
        }
    }

    func installJournalHeader() {
        let header = WorkoutDashboardHeaderView()
        header.onDateSelected = { [weak self] date in
            self?.selectedDate = WorkoutPresentation.startOfDay(date)
            self?.rebuildWorkoutSnapshot()
            self?.tableView.reloadData()
            self?.sizeJournalHeader()
        }
        header.onActivityChanged = { [weak self] family in
            self?.selectedFamily = family
            self?.applyFamilyFilter()
        }
        header.onYearChanged = { [weak self] year in
            self?.selectedYear = year
            self?.selectedDate = DashboardCalendar.date(year: year, month: 1, day: 1) ?? Date()
            self?.loadData(false)
        }
        journalHeader = header
        tableView.tableHeaderView = header
        refreshJournalHeader()
    }

    func refreshJournalHeader() {
        let workouts = data.compactMap { $0["workout"] as? HKWorkout }
        let lastSyncDate = UserDefaults.standard.object(forKey: UserDefaultKeys.lastSyncDate) as? Date
        let syncText: String
        if !GitHub.shared().isSignedIn() {
            syncText = "GitHub 未连接"
        } else if let lastSyncDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.unitsStyle = .short
            syncText = "同步于 \(formatter.localizedString(for: lastSyncDate, relativeTo: Date()))"
        } else {
            syncText = "尚未同步"
        }

        journalHeader?.render(
            family: selectedFamily,
            year: selectedYear,
            selectedDate: selectedDate,
            workouts: workouts,
            syncText: syncText,
            isLoading: !dataLoaded
        )
    }

    func sizeJournalHeader() {
        guard let header = journalHeader, tableView.bounds.width > 0 else { return }
        let size = header.systemLayoutSizeFitting(
            CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let width = tableView.bounds.width
        guard abs(header.frame.width - width) > 0.5
                || abs(header.frame.height - size.height) > 0.5 else {
            return
        }
        header.frame = CGRect(x: 0, y: 0, width: width, height: size.height)
        tableView.tableHeaderView = header
    }

    func setUpRefreshControl() {
        tableView.refreshControl = UIRefreshControl()
        tableView.refreshControl?.addTarget(self, action: #selector(WorkoutsViewController.refreshWasRequested(_:)), for: UIControl.Event.valueChanged)
    }

    func restoreState() {
        filter = [selectedFamily.activityType.rawValue]
    }

    func saveState() {
        UserDefaults.standard.set(self.filter, forKey: UserDefaultKeys.workoutFilter)
        UserDefaults.standard.synchronize()
    }

    func addObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(WorkoutsViewController.didSignIn), name: .didSetUpRepository, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(WorkoutsViewController.didSignOut), name: .didSignOut, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(WorkoutsViewController.didChangeInterfaceStyle), name: .didChangeInterfaceStyle, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(WorkoutsViewController.collectingActivityData), name: .collectingActivityData, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(WorkoutsViewController.collectingDistanceData), name: .collectingDistanceData, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(WorkoutsViewController.collectingHealthData(_:)), name: .collectingHealthData, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(WorkoutsViewController.didFinishExport), name: .didFinishExport, object: nil)
    }

    func loadData(_ visible: Bool = true) {
        dataLoaded = false
        startRefreshing(visible)
        loadWorkouts(visible)
    }

    func loadWorkouts(_ visible: Bool = true) {
        let interval = DashboardCalendar.yearInterval(selectedYear)
        Health.shared().getWorkoutsForDates(start: interval.start, end: interval.end) { workouts in
            self.allWorkouts = (workouts as? [HKWorkout] ?? []).sorted {
                $0.startDate > $1.startDate
            }
            self.dataLoaded = true
            self.applyFamilyFilter()
        }
        BackgroundTaskHelper.shared().handleForegroundFetch()
    }

    func reloadWithEmptyWorkout() {
        DispatchQueue.main.async {
            self.stopRefreshing(true)
            self.data = []
            self.rebuildWorkoutSnapshot()
            self.tableView.reloadData()
            self.sizeJournalHeader()
        }
    }

    func applyFamilyFilter() {
        DispatchQueue.main.async {
            let workouts = self.allWorkouts.filter(self.selectedFamily.matches)
            guard !workouts.isEmpty else {
                self.filter = [self.selectedFamily.activityType.rawValue]
                self.reloadWithEmptyWorkout()
                return
            }

            if WorkoutPresentation.calendar.component(.year, from: self.selectedDate) != self.selectedYear {
                self.selectedDate = WorkoutPresentation.startOfDay(workouts[0].startDate)
            } else if self.workoutForSelectedDate(workouts) == nil {
                self.selectedDate = WorkoutPresentation.startOfDay(workouts[0].startDate)
            }

            self.filter = [self.selectedFamily.activityType.rawValue]
            self.data = workouts.map { workout in
                [
                    "title": workout.workoutActivityType.name,
                    "workout": workout
                ]
            }
            self.stopRefreshing(true)
            self.rebuildWorkoutSnapshot()
            self.tableView.reloadData()
            self.sizeJournalHeader()
            self.saveState()
        }
    }

    func rebuildWorkoutSnapshot() {
        let workouts = data.compactMap { $0["workout"] as? HKWorkout }
        let selectedWorkouts = workouts.filter {
            WorkoutPresentation.calendar.isDate($0.startDate, inSameDayAs: selectedDate)
        }
        heroWorkout = selectedWorkouts.first
        if let heroWorkout {
            recentWorkouts = workouts.filter { $0.uuid != heroWorkout.uuid }
        } else {
            recentWorkouts = workouts
        }
        refreshJournalHeader()
    }

    private func workoutForSelectedDate(_ workouts: [HKWorkout]) -> HKWorkout? {
        workouts.first {
            WorkoutPresentation.calendar.isDate($0.startDate, inSameDayAs: selectedDate)
        }
    }
}

private extension UITableView {
    func dequeueJournalCell<Cell: UITableViewCell>(
        _ type: Cell.Type,
        identifier: String,
        for indexPath: IndexPath
    ) -> Cell? {
        dequeueReusableCell(withIdentifier: identifier, for: indexPath) as? Cell
    }
}
