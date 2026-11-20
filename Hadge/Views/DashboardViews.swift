import UIKit
import HealthKit

enum DashboardPalette {
    static let green = UIColor(red: 0.20, green: 0.84, blue: 0.29, alpha: 1)
    static let blue = UIColor(red: 0.13, green: 0.59, blue: 0.83, alpha: 1)
    static let purple = UIColor(red: 0.53, green: 0.40, blue: 0.84, alpha: 1)
    static let orange = UIColor(red: 0.96, green: 0.58, blue: 0.11, alpha: 1)
    static let red = UIColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1)
    static let pink = UIColor(red: 0.96, green: 0.26, blue: 0.49, alpha: 1)

    static var pageBackground: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.082, green: 0.082, blue: 0.086, alpha: 1)
                : UIColor(red: 0.965, green: 0.965, blue: 0.945, alpha: 1)
        }
    }

    static var cardBackground: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
                : UIColor.white
        }
    }

    static var elevatedBackground: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 1)
                : UIColor(red: 0.95, green: 0.96, blue: 0.94, alpha: 1)
        }
    }
}

enum AnnualHeatmapStyle {
    case workout
    case sleep
    case steps
    case water
    case rings

    var colors: [UIColor] {
        switch self {
        case .workout:
            return [
                UIColor(red: 0.61, green: 0.91, blue: 0.66, alpha: 1),
                UIColor(red: 0.25, green: 0.77, blue: 0.39, alpha: 1),
                UIColor(red: 0.19, green: 0.63, blue: 0.31, alpha: 1),
                UIColor(red: 0.13, green: 0.44, blue: 0.23, alpha: 1)
            ]
        case .sleep:
            return [
                UIColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1),
                UIColor(red: 0.96, green: 0.58, blue: 0.11, alpha: 1),
                UIColor(red: 0.98, green: 0.79, blue: 0.08, alpha: 1),
                UIColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 1)
            ]
        case .steps:
            return [
                UIColor(red: 0.71, green: 0.91, blue: 0.79, alpha: 1),
                UIColor(red: 0.35, green: 0.78, blue: 0.52, alpha: 1),
                UIColor(red: 0.13, green: 0.66, blue: 0.38, alpha: 1),
                UIColor(red: 0.06, green: 0.43, blue: 0.26, alpha: 1)
            ]
        case .water:
            return [
                UIColor(red: 0.67, green: 0.88, blue: 0.98, alpha: 1),
                UIColor(red: 0.37, green: 0.73, blue: 0.91, alpha: 1),
                UIColor(red: 0.13, green: 0.59, blue: 0.83, alpha: 1),
                UIColor(red: 0.06, green: 0.35, blue: 0.60, alpha: 1)
            ]
        case .rings:
            return [
                UIColor(red: 0.96, green: 0.30, blue: 0.33, alpha: 1),
                UIColor(red: 0.97, green: 0.64, blue: 0.15, alpha: 1),
                UIColor(red: 0.91, green: 0.83, blue: 0.15, alpha: 1),
                UIColor(red: 0.20, green: 0.84, blue: 0.29, alpha: 1)
            ]
        }
    }

    var legendLow: String {
        switch self {
        case .sleep: return "不足"
        case .workout, .steps, .water: return "少"
        case .rings: return "未完成"
        }
    }

    var legendHigh: String {
        switch self {
        case .sleep, .rings: return "充足"
        case .workout, .steps, .water: return "多"
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .workout:
            return String(format: "%.1f 公里", value)
        case .sleep:
            return DashboardFormatters.duration(minutes: value)
        case .steps:
            return "\(Int(value.rounded()).formatted()) 步"
        case .water:
            if value >= 1_000 {
                return String(format: "%.2f 升", value / 1_000)
            }
            return "\(Int(value.rounded())) 毫升"
        case .rings:
            return "\(Int((value * 100).rounded()))%"
        }
    }
}

enum DashboardFormatters {
    static var ChineseDate: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }

    static var MonthDay: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }

    static func duration(minutes: Double) -> String {
        let totalMinutes = max(Int(minutes.rounded()), 0)
        let hours = totalMinutes / 60
        let remainder = totalMinutes % 60
        if hours == 0 {
            return "\(remainder) 分钟"
        }
        if remainder == 0 {
            return "\(hours) 小时"
        }
        return "\(hours) 小时 \(remainder) 分钟"
    }

    static func shortDuration(minutes: Double) -> String {
        let totalMinutes = max(Int(minutes.rounded()), 0)
        return String(format: "%d:%02d", totalMinutes / 60, totalMinutes % 60)
    }
}

// swiftlint:disable:next type_body_length
final class AnnualHeatmapView: UIView {
    var onYearChanged: ((Int) -> Void)?
    var onDateSelected: ((Date) -> Void)?

    private let titleLabel = UILabel()
    private let summaryLabel = UILabel()
    private let yearButton = UIButton(type: .system)
    private let previousButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let weekdaysContainer = UIView()
    private let scrollView = UIScrollView()
    private let gridCanvas = UIView()
    private let detailLabel = UILabel()
    private let legendStack = UIStackView()

    private var records: [DailyHealthMetric] = []
    private var style: AnnualHeatmapStyle = .workout
    private var selectedYear = DashboardCalendar.calendar.component(.year, from: Date())
    private var selectedDate: Date?
    private var cellDates: [Date] = []
    private var latestCanvasWidth: CGFloat = 0
    private var pendingScrollToLatest = true
    private var lastRenderedYear: Int?
    private var lastRecordDate: Date?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.layoutIfNeeded()
        guard pendingScrollToLatest, latestCanvasWidth > 0, scrollView.bounds.width > 0 else {
            return
        }
        pendingScrollToLatest = false
        scrollToLatest()
    }

    func configure(
        year: Int,
        records: [DailyHealthMetric],
        style: AnnualHeatmapStyle,
        selectedDate: Date? = nil
    ) {
        let latestRecordDate = records.last?.date
        pendingScrollToLatest = lastRenderedYear != year
            || (latestRecordDate != nil && latestRecordDate != lastRecordDate)
        lastRenderedYear = year
        lastRecordDate = latestRecordDate
        self.selectedYear = year
        self.records = records
        self.style = style
        if let selectedDate = selectedDate {
            self.selectedDate = selectedDate
        } else if self.selectedDate == nil {
            self.selectedDate = records.last?.date
        }
        updateHeader()
        rebuildGrid()
    }

    func select(date: Date) {
        selectedDate = date
        rebuildGrid()
    }

    private func configureView() {
        backgroundColor = .clear

        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .label

        summaryLabel.font = .preferredFont(forTextStyle: .footnote)
        summaryLabel.textColor = .secondaryLabel
        summaryLabel.numberOfLines = 0

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, summaryLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 4

        let controls = UIStackView(arrangedSubviews: [previousButton, yearButton, nextButton])
        controls.axis = .horizontal
        controls.alignment = .center
        controls.spacing = 2
        controls.setContentHuggingPriority(.required, for: .horizontal)

        [previousButton, yearButton, nextButton].forEach {
            $0.tintColor = .label
            $0.titleLabel?.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            $0.backgroundColor = DashboardPalette.elevatedBackground
            $0.layer.cornerRadius = 12
        }
        previousButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        nextButton.setImage(UIImage(systemName: "chevron.right"), for: .normal)
        previousButton.addTarget(self, action: #selector(previousYear), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextYear), for: .touchUpInside)
        yearButton.showsMenuAsPrimaryAction = true

        NSLayoutConstraint.activate([
            previousButton.widthAnchor.constraint(equalToConstant: 30),
            previousButton.heightAnchor.constraint(equalToConstant: 30),
            yearButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 54),
            yearButton.heightAnchor.constraint(equalToConstant: 30),
            nextButton.widthAnchor.constraint(equalToConstant: 30),
            nextButton.heightAnchor.constraint(equalToConstant: 30)
        ])

        let heading = UIStackView(arrangedSubviews: [titleStack, controls])
        heading.axis = .horizontal
        heading.alignment = .center
        heading.spacing = 10
        titleStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        weekdaysContainer.translatesAutoresizingMaskIntoConstraints = false
        weekdaysContainer.backgroundColor = .clear

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(gridCanvas)

        let chartRow = UIStackView(arrangedSubviews: [weekdaysContainer, scrollView])
        chartRow.axis = .horizontal
        chartRow.spacing = 5
        chartRow.alignment = .fill
        chartRow.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 1
        detailLabel.adjustsFontForContentSizeCategory = true

        legendStack.axis = .horizontal
        legendStack.alignment = .center
        legendStack.spacing = 4
        legendStack.distribution = .fill
        legendStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        let content = UIStackView(arrangedSubviews: [heading, chartRow, detailLabel, legendStack])
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 12
        addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            weekdaysContainer.widthAnchor.constraint(equalToConstant: 18),
            chartRow.heightAnchor.constraint(equalToConstant: 148)
        ])

        buildWeekdayLabels()
    }

    private func updateHeader() {
        titleLabel.text = "\(selectedYear) 年"
        yearButton.setTitle("\(selectedYear)", for: .normal)
        previousButton.isEnabled = selectedYear > 2014
        nextButton.isEnabled = selectedYear < DashboardCalendar.calendar.component(.year, from: Date())
        configureYearMenu()
        updateSummary()
        buildLegend()
    }

    private func updateSummary() {
        let activeCount = records.count
        let total = records.reduce(0) { $0 + $1.value }
        let average = activeCount > 0 ? total / Double(activeCount) : 0
        switch style {
        case .workout:
            summaryLabel.text = String(
                format: "%.1f 公里 · %d 个活动日",
                total,
                activeCount
            )
        case .sleep:
            summaryLabel.text = "平均 \(DashboardFormatters.duration(minutes: average)) · \(activeCount) 晚"
        case .steps:
            summaryLabel.text = "\(Int(total.rounded()).formatted()) 步 · 日均 \(Int(average.rounded()).formatted())"
        case .water:
            summaryLabel.text = String(format: "%.1f 升 · 日均 %.0f 毫升", total / 1_000, average)
        case .rings:
            let closed = records.filter { $0.value >= 0.995 }.count
            summaryLabel.text = "闭合 \(closed) 天 · 平均完成 \(Int((average * 100).rounded()))%"
        }
    }

    private func buildWeekdayLabels() {
        weekdaysContainer.subviews.forEach { $0.removeFromSuperview() }
        let weekdays = ["日", "", "二", "", "四", "", "六"]
        weekdays.enumerated().forEach { index, text in
            guard !text.isEmpty else { return }
            let label = UILabel(frame: CGRect(x: 0, y: 25 + CGFloat(index) * 17, width: 18, height: 14))
            label.text = text
            label.font = .systemFont(ofSize: 9, weight: .medium)
            label.textColor = .tertiaryLabel
            label.textAlignment = .center
            weekdaysContainer.addSubview(label)
        }
    }

    private func rebuildGrid() {
        gridCanvas.subviews.forEach { $0.removeFromSuperview() }
        cellDates = []

        let calendar = DashboardCalendar.calendar
        let interval = DashboardCalendar.yearInterval(selectedYear)
        let startWeekday = calendar.component(.weekday, from: interval.start)
        let leadingDays = (startWeekday - calendar.firstWeekday + 7) % 7
        guard let alignedStart = calendar.date(
            byAdding: .day,
            value: -leadingDays,
            to: interval.start
        ) else { return }
        let totalDays = calendar.dateComponents([.day], from: alignedStart, to: interval.end).day ?? 1
        let weekCount = Int(ceil(Double(totalDays) / 7.0))
        let cellSize: CGFloat = 14
        let spacing: CGFloat = 3
        let rowHeight: CGFloat = 17
        let columnWidth: CGFloat = 17
        let top: CGFloat = 22
        let canvasWidth = CGFloat(weekCount) * columnWidth - spacing
        let canvasHeight = top + 7 * rowHeight
        latestCanvasWidth = canvasWidth

        gridCanvas.frame = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
        scrollView.contentSize = gridCanvas.bounds.size
        addMonthLabels(
            alignedStart: alignedStart,
            weekCount: weekCount,
            columnWidth: columnWidth,
            yPosition: 0
        )

        let groupedValues = Dictionary(grouping: records) {
            calendar.startOfDay(for: $0.date)
        }
        let values = groupedValues.mapValues { records in
            records.map(\.value).max() ?? 0
        }
        let thresholds = valueThresholds()

        for week in 0..<weekCount {
            for weekday in 0..<7 {
                guard let date = calendar.date(
                    byAdding: .day,
                    value: week * 7 + weekday,
                    to: alignedStart
                ) else { continue }
                guard date >= interval.start, date < interval.end else { continue }

                let button = UIButton(type: .custom)
                button.frame = CGRect(
                    x: CGFloat(week) * columnWidth,
                    y: top + CGFloat(weekday) * rowHeight,
                    width: cellSize,
                    height: cellSize
                )
                button.layer.cornerRadius = 3
                button.clipsToBounds = true
                button.tag = cellDates.count
                button.addTarget(self, action: #selector(dayTapped(_:)), for: .touchUpInside)

                let value = values[calendar.startOfDay(for: date)]
                button.backgroundColor = heatColor(value: value, thresholds: thresholds)
                if isSelected(date) {
                    button.layer.borderWidth = 2
                    button.layer.borderColor = UIColor.label.cgColor
                }
                let detail = value.map { style.format($0) } ?? "无数据"
                button.accessibilityLabel = "\(DashboardFormatters.MonthDay.string(from: date))，\(detail)"
                button.accessibilityTraits = .button
                cellDates.append(date)
                gridCanvas.addSubview(button)
            }
        }

        let targetDate = selectedDate
            ?? records.last?.date
            ?? calendar.date(byAdding: .day, value: -1, to: interval.end)
            ?? interval.end
        updateDetail(for: targetDate)
        setNeedsLayout()
    }

    private func addMonthLabels(
        alignedStart: Date,
        weekCount: Int,
        columnWidth: CGFloat,
        yPosition: CGFloat
    ) {
        let calendar = DashboardCalendar.calendar
        var lastX: CGFloat = -100
        for month in 1...12 {
            guard let monthDate = DashboardCalendar.date(year: selectedYear, month: month, day: 1) else {
                continue
            }
            let dayOffset = calendar.dateComponents([.day], from: alignedStart, to: monthDate).day ?? 0
            let week = min(max(dayOffset / 7, 0), max(weekCount - 1, 0))
            let xPosition = CGFloat(week) * columnWidth
            guard xPosition - lastX >= 27 else { continue }
            let label = UILabel(frame: CGRect(x: xPosition, y: yPosition, width: 25, height: 14))
            label.text = "\(month)月"
            label.font = .systemFont(ofSize: 9, weight: .medium)
            label.textColor = .tertiaryLabel
            gridCanvas.addSubview(label)
            lastX = xPosition
        }
    }

    private func heatColor(value: Double?, thresholds: [Double]) -> UIColor {
        guard let value = value, value > 0 else {
            return UIColor.tertiarySystemFill
        }
        let level: Int
        switch style {
        case .sleep:
            switch value {
            case ..<300: level = 0
            case ..<390: level = 1
            case ..<450: level = 2
            default: level = 3
            }
        case .rings:
            switch value {
            case ..<0.40: level = 0
            case ..<0.70: level = 1
            case ..<0.995: level = 2
            default: level = 3
            }
        default:
            if value <= thresholds[0] {
                level = 0
            } else if value <= thresholds[1] {
                level = 1
            } else if value <= thresholds[2] {
                level = 2
            } else {
                level = 3
            }
        }
        return style.colors[level]
    }

    private func valueThresholds() -> [Double] {
        let values = records.map(\.value).filter { $0 > 0 }.sorted()
        guard !values.isEmpty else { return [1, 2, 3] }
        func percentile(_ ratio: Double) -> Double {
            let index = min(Int(Double(values.count - 1) * ratio), values.count - 1)
            return values[index]
        }
        return [percentile(0.25), percentile(0.5), percentile(0.75)]
    }

    private func buildLegend() {
        legendStack.arrangedSubviews.forEach {
            legendStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let low = UILabel()
        low.text = style.legendLow
        low.font = .systemFont(ofSize: 10, weight: .medium)
        low.textColor = .tertiaryLabel
        legendStack.addArrangedSubview(low)
        legendStack.addArrangedSubview(UIView())

        style.colors.forEach { color in
            let square = UIView()
            square.translatesAutoresizingMaskIntoConstraints = false
            square.backgroundColor = color
            square.layer.cornerRadius = 2
            NSLayoutConstraint.activate([
                square.widthAnchor.constraint(equalToConstant: 10),
                square.heightAnchor.constraint(equalToConstant: 10)
            ])
            legendStack.addArrangedSubview(square)
        }

        legendStack.addArrangedSubview(UIView())
        let high = UILabel()
        high.text = style.legendHigh
        high.font = .systemFont(ofSize: 10, weight: .medium)
        high.textColor = .tertiaryLabel
        legendStack.addArrangedSubview(high)
    }

    private func scrollToLatest() {
        guard let targetDate = records.last?.date ?? selectedDate else {
            return
        }
        let calendar = DashboardCalendar.calendar
        let interval = DashboardCalendar.yearInterval(selectedYear)
        let startWeekday = calendar.component(.weekday, from: interval.start)
        let leadingDays = (startWeekday - calendar.firstWeekday + 7) % 7
        let dayOffset = calendar.dateComponents([.day], from: interval.start, to: targetDate).day ?? 0
        let week = CGFloat((leadingDays + dayOffset) / 7)
        let maxOffset = max(latestCanvasWidth - scrollView.bounds.width, 0)
        let offset = min(max(week * 17 - scrollView.bounds.width * 0.72, 0), maxOffset)
        scrollView.setContentOffset(CGPoint(x: offset, y: 0), animated: false)
    }

    private func isSelected(_ date: Date) -> Bool {
        guard let selectedDate = selectedDate else { return false }
        return DashboardCalendar.calendar.isDate(date, inSameDayAs: selectedDate)
    }

    private func updateDetail(for date: Date) {
        selectedDate = date
        let value = records.value(on: date)
        let formatted = value.map { style.format($0) } ?? "没有记录"
        detailLabel.text = "\(DashboardFormatters.MonthDay.string(from: date)) · \(formatted)"
    }

    @objc private func dayTapped(_ sender: UIButton) {
        guard cellDates.indices.contains(sender.tag) else { return }
        let date = cellDates[sender.tag]
        selectedDate = date
        updateDetail(for: date)
        rebuildGrid()
        onDateSelected?(date)
    }

    @objc private func previousYear() {
        changeYear(selectedYear - 1)
    }

    @objc private func nextYear() {
        changeYear(selectedYear + 1)
    }

    private func configureYearMenu() {
        let currentYear = DashboardCalendar.calendar.component(.year, from: Date())
        let actions = (2014...currentYear).reversed().map { year in
            UIAction(
                title: "\(year) 年",
                state: year == selectedYear ? .on : .off
            ) { [weak self] _ in
                self?.changeYear(year)
            }
        }
        yearButton.menu = UIMenu(title: "选择年份", children: actions)
    }

    private func changeYear(_ year: Int) {
        let currentYear = DashboardCalendar.calendar.component(.year, from: Date())
        guard year >= 2014, year <= currentYear else { return }
        selectedDate = nil
        onYearChanged?(year)
    }
}

final class WorkoutDashboardHeaderView: UIView {
    var onActivityChanged: ((WorkoutActivityFamily) -> Void)?
    var onDateSelected: ((Date) -> Void)?
    var onYearChanged: ((Int) -> Void)?

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let syncLabel = UILabel()
    private let activityControl = UISegmentedControl(items: WorkoutActivityFamily.allCases.map(\.title))
    private let summaryStack = UIStackView()
    private let weekTitleLabel = UILabel()
    private let weekStack = UIStackView()
    private let heatmapView = AnnualHeatmapView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    func render(
        family: WorkoutActivityFamily,
        year: Int,
        selectedDate: Date,
        workouts: [HKWorkout],
        syncText: String,
        isLoading: Bool
    ) {
        activityControl.selectedSegmentIndex = family.rawValue
        titleLabel.text = family.title
        subtitleLabel.text = DashboardFormatters.ChineseDate.string(from: selectedDate)
        syncLabel.text = syncText
        syncLabel.textColor = isLoading ? DashboardPalette.orange : .secondaryLabel
        renderSummary(workouts)
        renderWeek(selectedDate: selectedDate, workouts: workouts)

        heatmapView.configure(
            year: year,
            records: records(for: workouts),
            style: .workout,
            selectedDate: selectedDate
        )
    }

    func selectHeatmapDate(_ date: Date) {
        heatmapView.select(date: date)
    }

    func setSyncStatus(_ text: String, isActive: Bool) {
        syncLabel.text = text
        syncLabel.textColor = isActive ? DashboardPalette.orange : .secondaryLabel
    }

    private func configureView() {
        backgroundColor = .clear

        titleLabel.font = .systemFont(ofSize: 34, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true

        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.adjustsFontForContentSizeCategory = true

        syncLabel.font = .systemFont(ofSize: 11, weight: .medium)
        syncLabel.textAlignment = .right
        syncLabel.numberOfLines = 2
        syncLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 2
        let topRow = UIStackView(arrangedSubviews: [titleStack, syncLabel])
        topRow.axis = .horizontal
        topRow.alignment = .top
        topRow.spacing = 12

        activityControl.selectedSegmentIndex = WorkoutActivityFamily.running.rawValue
        activityControl.selectedSegmentTintColor = DashboardPalette.green
        activityControl.addTarget(self, action: #selector(activityChanged), for: .valueChanged)
        activityControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        activityControl.setTitleTextAttributes(
            [.font: UIFont.systemFont(ofSize: 12, weight: .semibold)],
            for: .normal
        )

        summaryStack.axis = .horizontal
        summaryStack.spacing = 8
        summaryStack.distribution = .fillEqually

        weekTitleLabel.text = "本周"
        weekTitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        weekTitleLabel.textColor = .secondaryLabel

        weekStack.axis = .horizontal
        weekStack.distribution = .fillEqually
        weekStack.spacing = 5
        weekStack.heightAnchor.constraint(equalToConstant: 68).isActive = true

        heatmapView.onDateSelected = { [weak self] date in
            self?.onDateSelected?(date)
        }
        heatmapView.onYearChanged = { [weak self] year in
            self?.onYearChanged?(year)
        }

        let content = UIStackView(
            arrangedSubviews: [
                topRow,
                activityControl,
                summaryStack,
                weekTitleLabel,
                weekStack,
                heatmapView
            ]
        )
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 14
        content.setCustomSpacing(18, after: activityControl)
        content.setCustomSpacing(18, after: weekStack)
        addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18)
        ])
    }

    private func renderSummary(_ workouts: [HKWorkout]) {
        summaryStack.arrangedSubviews.forEach {
            summaryStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let meters = workouts.reduce(0.0) {
            $0 + ($1.totalDistance?.doubleValue(for: .meter()) ?? 0)
        }
        let duration = workouts.reduce(0.0) { $0 + $1.duration }
        let activeDays = Set(workouts.map {
            DashboardCalendar.calendar.startOfDay(for: $0.startDate)
        }).count

        summaryStack.addArrangedSubview(
            DashboardSummaryPill(value: String(format: "%.1f km", meters / 1_000), label: "里程")
        )
        summaryStack.addArrangedSubview(
            DashboardSummaryPill(value: "\(workouts.count)", label: "活动")
        )
        summaryStack.addArrangedSubview(
            DashboardSummaryPill(
                value: DashboardFormatters.duration(minutes: duration / 60),
                label: "\(activeDays) 天"
            )
        )
    }

    private func renderWeek(selectedDate: Date, workouts: [HKWorkout]) {
        weekStack.arrangedSubviews.forEach {
            weekStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let workoutDays = Set(workouts.map {
            DashboardCalendar.calendar.startOfDay(for: $0.startDate)
        })
        WorkoutPresentation.weekDays(containing: selectedDate).forEach { day in
            let control = WorkoutWeekDayControl(date: day)
            control.isSelected = DashboardCalendar.calendar.isDate(day, inSameDayAs: selectedDate)
            control.hasWorkout = workoutDays.contains(DashboardCalendar.calendar.startOfDay(for: day))
            control.addTarget(self, action: #selector(weekDaySelected(_:)), for: .touchUpInside)
            weekStack.addArrangedSubview(control)
        }
    }

    private func records(for workouts: [HKWorkout]) -> [DailyHealthMetric] {
        let calendar = DashboardCalendar.calendar
        let grouped = Dictionary(grouping: workouts) {
            calendar.startOfDay(for: $0.startDate)
        }
        return grouped.compactMap { date, dayWorkouts in
            let distance = dayWorkouts.reduce(0.0) {
                $0 + ($1.totalDistance?.doubleValue(for: .meter()) ?? 0)
            } / 1_000
            guard distance > 0 else { return nil }
            return DailyHealthMetric(date: date, value: distance)
        }.sorted { $0.date < $1.date }
    }

    @objc private func activityChanged() {
        guard let family = WorkoutActivityFamily(rawValue: activityControl.selectedSegmentIndex) else {
            return
        }
        onActivityChanged?(family)
    }

    @objc private func weekDaySelected(_ sender: WorkoutWeekDayControl) {
        onDateSelected?(sender.date)
    }
}

final class DashboardSummaryPill: UIView {
    private let valueLabel = UILabel()
    private let captionLabel = UILabel()

    init(value: String, label: String) {
        super.init(frame: .zero)
        configureView(value: value, label: label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureView(value: String, label: String) {
        backgroundColor = DashboardPalette.cardBackground
        layer.cornerRadius = 14

        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        valueLabel.textColor = .label
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.72

        captionLabel.text = label
        captionLabel.font = .systemFont(ofSize: 10, weight: .medium)
        captionLabel.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [valueLabel, captionLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9)
        ])
        isAccessibilityElement = true
        accessibilityLabel = "\(label)，\(value)"
    }
}

final class ActivityRingsView: UIView {
    private var progressValues: [Double] = [0, 0, 0]
    private let ringColors = [
        DashboardPalette.pink,
        DashboardPalette.green,
        DashboardPalette.blue
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
    }

    func setProgress(move: Double, exercise: Double, stand: Double) {
        progressValues = [
            min(max(move, 0), 1),
            min(max(exercise, 0), 1),
            min(max(stand, 0), 1)
        ]
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let available = min(rect.width, rect.height)
        for index in 0..<3 {
            let radius = available / 2 - 7 - CGFloat(index) * 9
            let path = UIBezierPath(
                arcCenter: center,
                radius: radius,
                startAngle: -.pi / 2,
                endAngle: .pi * 1.5,
                clockwise: true
            )
            path.lineWidth = 6
            path.lineCapStyle = .round
            ringColors[index].withAlphaComponent(0.16).setStroke()
            path.stroke()

            guard progressValues[index] > 0 else { continue }
            let progress = UIBezierPath(
                arcCenter: center,
                radius: radius,
                startAngle: -.pi / 2,
                endAngle: -.pi / 2 + .pi * 2 * progressValues[index],
                clockwise: true
            )
            progress.lineWidth = 6
            progress.lineCapStyle = .round
            ringColors[index].setStroke()
            progress.stroke()
        }
    }
}
