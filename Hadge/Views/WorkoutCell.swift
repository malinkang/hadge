import UIKit
import HealthKit

class WorkoutCell: UITableViewCell {
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var emojiLabel: UILabel!
    @IBOutlet weak var dateLabel: UILabel!
    @IBOutlet weak var distanceLabel: UILabel!
    @IBOutlet weak var durationLabel: UILabel!
    @IBOutlet weak var energyLabel: UILabel!
    @IBOutlet weak var sourceLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()

        emojiLabel.superview?.layer.cornerRadius = 17.0
    }

    func setStartDate(_ date: Date) {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full

        dateLabel?.text = formatter.localizedString(for: date, relativeTo: Date())
    }

    func setDistance(_ distance: HKQuantity?) {
        let formatter = LengthFormatter()
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = 1

        if let meters = distance?.doubleValue(for: HKUnit.meter()), meters > 0 {
            distanceLabel?.text = formatter.string(fromValue: meters / 1000, unit: .kilometer)
        } else {
            distanceLabel?.text = ""
        }
    }

    func setDuration(_ duration: TimeInterval) {
        let time = NSInteger(duration)

        let seconds = time % 60
        let minutes = (time / 60) % 60
        let hours = (time / 3600)

        durationLabel?.text = String(format: "%0.2d:%0.2d:%0.2d", hours, minutes, seconds)
    }

    func setEnergy(_ energy: HKQuantity?) {
        if let calories = energy?.doubleValue(for: HKUnit.kilocalorie()) {
            energyLabel?.text = String(format: "%0.0fcal", calories)
        } else {
            energyLabel?.text = String(format: "")
        }
    }
}

enum WorkoutPresentation {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = .current
        calendar.firstWeekday = 1
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func weekDays(containing date: Date) -> [Date] {
        let calendar = self.calendar
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return []
        }
        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }
    }

    static func title(for date: Date) -> String {
        if calendar.isDateInToday(date) {
            return "Today"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    static func longDate(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEE, MMM d, yyyy"
        return formatter.string(from: date)
    }

    static func compactDate(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    static func weekday(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }

    static func sourceAndTime(for workout: HKWorkout) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.unitsStyle = .full
        let relativeTime = formatter.localizedString(for: workout.startDate, relativeTo: Date())
        return "\(workout.sourceRevision.source.name) · \(relativeTime)"
    }

    static func distance(for workout: HKWorkout) -> String {
        guard let meters = workout.totalDistance?.doubleValue(for: .meter()), meters > 0 else {
            return "—"
        }
        return String(format: "%.1f km", meters / 1_000)
    }

    static func duration(for workout: HKWorkout) -> String {
        let totalSeconds = max(Int(workout.duration.rounded()), 0)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func energy(for workout: HKWorkout) -> String {
        guard let calories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) else {
            return "—"
        }
        return String(format: "%.0f kcal", calories)
    }

    static func symbol(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running:
            return "figure.run"
        case .walking:
            return "figure.walk"
        case .cycling:
            return "bicycle"
        case .swimming:
            return "figure.pool.swim"
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            return "dumbbell"
        case .hiking:
            return "figure.hiking"
        case .yoga:
            return "figure.yoga"
        case .highIntensityIntervalTraining:
            return "bolt.heart"
        default:
            return "figure.walk"
        }
    }

    static func accentColor(for type: HKWorkoutActivityType) -> UIColor {
        switch type {
        case .running:
            return .systemGreen
        case .walking, .hiking:
            return .systemTeal
        case .cycling:
            return .systemBlue
        case .swimming:
            return .systemCyan
        case .yoga:
            return .systemPurple
        case .highIntensityIntervalTraining:
            return .systemOrange
        default:
            return .systemIndigo
        }
    }
}

final class WorkoutJournalHeaderView: UIView {
    var onSelectDate: ((Date) -> Void)?
    var onFilter: (() -> Void)?
    var onSettings: (() -> Void)?

    private let titleLabel = UILabel()
    private let dateLabel = UILabel()
    private let statusDot = UIView()
    private let statusLabel = UILabel()
    private let weekStack = UIStackView()
    private let filterButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    func configure(
        weekDays: [Date],
        selectedDate: Date,
        workoutDates: Set<Date>,
        syncText: String,
        syncIsActive: Bool,
        filterIsActive: Bool
    ) {
        titleLabel.text = WorkoutPresentation.title(for: selectedDate)
        dateLabel.text = WorkoutPresentation.longDate(for: selectedDate)

        weekStack.arrangedSubviews.forEach {
            weekStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        weekDays.forEach { day in
            let control = WorkoutWeekDayControl(date: day)
            control.isSelected = WorkoutPresentation.calendar.isDate(day, inSameDayAs: selectedDate)
            control.hasWorkout = workoutDates.contains(WorkoutPresentation.startOfDay(day))
            control.addTarget(self, action: #selector(selectDay(_:)), for: .touchUpInside)
            weekStack.addArrangedSubview(control)
        }

        setSyncStatus(syncText, isActive: syncIsActive)
        setFilterActive(filterIsActive)
    }

    func setSyncStatus(_ text: String, isActive: Bool) {
        statusLabel.text = text
        statusDot.backgroundColor = isActive ? .systemOrange : .systemGreen
    }

    func setFilterActive(_ active: Bool) {
        let tint = active ? UIColor.systemGreen : UIColor.secondaryLabel
        filterButton.tintColor = tint
        filterButton.backgroundColor = active
            ? UIColor.systemGreen.withAlphaComponent(0.14)
            : UIColor.secondarySystemFill
        filterButton.accessibilityValue = active ? "Filter active" : "No filter"
    }

    private func configureView() {
        backgroundColor = .clear

        titleLabel.font = .systemFont(ofSize: 34, weight: .bold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label

        dateLabel.font = .preferredFont(forTextStyle: .subheadline)
        dateLabel.adjustsFontForContentSizeCategory = true
        dateLabel.textColor = .secondaryLabel

        let headingStack = UIStackView(arrangedSubviews: [titleLabel, dateLabel])
        headingStack.axis = .vertical
        headingStack.spacing = 2

        configureIconButton(
            filterButton,
            symbol: "line.3.horizontal.decrease",
            accessibilityLabel: "Filter workouts"
        )
        filterButton.addTarget(self, action: #selector(filterTapped), for: .touchUpInside)

        configureIconButton(
            settingsButton,
            symbol: "gearshape",
            accessibilityLabel: "Settings"
        )
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)

        let actionsStack = UIStackView(arrangedSubviews: [filterButton, settingsButton])
        actionsStack.axis = .horizontal
        actionsStack.spacing = 8
        actionsStack.alignment = .center

        let topRow = UIStackView(arrangedSubviews: [headingStack, actionsStack])
        topRow.axis = .horizontal
        topRow.alignment = .top
        topRow.spacing = 12
        headingStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        weekStack.axis = .horizontal
        weekStack.distribution = .fillEqually
        weekStack.alignment = .fill
        weekStack.spacing = 5
        weekStack.heightAnchor.constraint(equalToConstant: 74).isActive = true

        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.layer.cornerRadius = 3
        statusDot.backgroundColor = .systemGreen
        NSLayoutConstraint.activate([
            statusDot.widthAnchor.constraint(equalToConstant: 6),
            statusDot.heightAnchor.constraint(equalToConstant: 6)
        ])

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .secondaryLabel

        let statusStack = UIStackView(arrangedSubviews: [statusDot, statusLabel])
        statusStack.axis = .horizontal
        statusStack.alignment = .center
        statusStack.spacing = 7

        let contentStack = UIStackView(arrangedSubviews: [topRow, weekStack, statusStack])
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 16
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])
    }

    private func configureIconButton(_ button: UIButton, symbol: String, accessibilityLabel: String) {
        let configuration = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        button.setImage(UIImage(systemName: symbol, withConfiguration: configuration), for: .normal)
        button.tintColor = .secondaryLabel
        button.backgroundColor = .secondarySystemFill
        button.layer.cornerRadius = 18
        button.accessibilityLabel = accessibilityLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 36),
            button.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    @objc private func selectDay(_ sender: WorkoutWeekDayControl) {
        onSelectDate?(sender.date)
    }

    @objc private func filterTapped() {
        onFilter?()
    }

    @objc private func settingsTapped() {
        onSettings?()
    }
}

final class WorkoutWeekDayControl: UIControl {
    let date: Date
    var hasWorkout: Bool = false {
        didSet {
            dotView.isHidden = !hasWorkout
            updateAccessibilityValue()
        }
    }

    override var isSelected: Bool {
        didSet {
            backgroundColor = isSelected
                ? UIColor.systemGreen.withAlphaComponent(0.12)
                : .clear
            layer.borderWidth = isSelected ? 1 : 0
            layer.borderColor = UIColor.systemGreen.withAlphaComponent(0.35).cgColor
            weekdayLabel.textColor = isSelected ? .label : .secondaryLabel
            dayLabel.textColor = isSelected ? .label : .secondaryLabel
            updateAccessibilityValue()
        }
    }

    private let weekdayLabel = UILabel()
    private let dayLabel = UILabel()
    private let dotView = UIView()

    init(date: Date) {
        self.date = date
        super.init(frame: .zero)
        configureView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        layer.borderColor = UIColor.systemGreen.withAlphaComponent(0.35).cgColor
    }

    private func configureView() {
        layer.cornerRadius = 17
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityTraits = .button

        weekdayLabel.text = WorkoutPresentation.weekday(for: date)
        weekdayLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        weekdayLabel.textColor = .secondaryLabel
        weekdayLabel.textAlignment = .center

        dayLabel.text = String(WorkoutPresentation.calendar.component(.day, from: date))
        dayLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        dayLabel.textColor = .secondaryLabel
        dayLabel.textAlignment = .center
        dayLabel.setContentHuggingPriority(.required, for: .vertical)

        dotView.backgroundColor = .systemGreen
        dotView.layer.cornerRadius = 2.5
        dotView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dotView.widthAnchor.constraint(equalToConstant: 5),
            dotView.heightAnchor.constraint(equalToConstant: 5)
        ])

        let dotContainer = UIView()
        dotContainer.addSubview(dotView)
        NSLayoutConstraint.activate([
            dotView.centerXAnchor.constraint(equalTo: dotContainer.centerXAnchor),
            dotView.centerYAnchor.constraint(equalTo: dotContainer.centerYAnchor),
            dotContainer.heightAnchor.constraint(equalToConstant: 8)
        ])

        let stack = UIStackView(arrangedSubviews: [weekdayLabel, dayLabel, dotContainer])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 1
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7)
        ])

        accessibilityLabel = WorkoutPresentation.longDate(for: date)
        updateAccessibilityValue()
    }

    private func updateAccessibilityValue() {
        if isSelected && hasWorkout {
            accessibilityValue = "Selected, workout recorded"
        } else if isSelected {
            accessibilityValue = "Selected"
        } else if hasWorkout {
            accessibilityValue = "Workout recorded"
        } else {
            accessibilityValue = nil
        }
    }
}

final class WorkoutJournalHeroCell: UITableViewCell {
    static let reuseIdentifier = "WorkoutJournalHeroCell"

    private let cardView = UIView()
    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let sourceLabel = UILabel()
    private let distanceMetric = WorkoutMetricView()
    private let durationMetric = WorkoutMetricView()
    private let energyMetric = WorkoutMetricView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with workout: HKWorkout) {
        let accent = WorkoutPresentation.accentColor(for: workout.workoutActivityType)
        cardView.backgroundColor = UIColor { traits in
            accent.resolvedColor(with: traits).withAlphaComponent(
                traits.userInterfaceStyle == .dark ? 0.18 : 0.10
            )
        }
        iconContainer.backgroundColor = accent
        iconView.image = UIImage(
            systemName: WorkoutPresentation.symbol(for: workout.workoutActivityType),
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .semibold)
        )

        titleLabel.text = workout.workoutActivityType.name
        sourceLabel.text = WorkoutPresentation.sourceAndTime(for: workout)
        distanceMetric.configure(
            value: WorkoutPresentation.distance(for: workout),
            label: "Distance",
            color: accent
        )
        durationMetric.configure(
            value: WorkoutPresentation.duration(for: workout),
            label: "Time",
            color: accent
        )
        energyMetric.configure(
            value: WorkoutPresentation.energy(for: workout),
            label: "Energy",
            color: .systemPink
        )

        isAccessibilityElement = true
        accessibilityLabel = [
            workout.workoutActivityType.name,
            sourceLabel.text,
            distanceMetric.accessibilityLabel,
            durationMetric.accessibilityLabel,
            energyMetric.accessibilityLabel
        ].compactMap { $0 }.joined(separator: ", ")
        accessibilityTraits = .button
    }

    private func configureView() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .default

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.layer.cornerRadius = 22
        cardView.clipsToBounds = true
        contentView.addSubview(cardView)

        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.layer.cornerRadius = 15
        cardView.addSubview(iconContainer)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconContainer.addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 21, weight: .semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label

        sourceLabel.font = .preferredFont(forTextStyle: .footnote)
        sourceLabel.adjustsFontForContentSizeCategory = true
        sourceLabel.textColor = .secondaryLabel
        sourceLabel.numberOfLines = 1
        sourceLabel.lineBreakMode = .byTruncatingTail

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, sourceLabel])
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.axis = .vertical
        titleStack.spacing = 3
        cardView.addSubview(titleStack)

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = .tertiaryLabel
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        cardView.addSubview(chevron)

        let firstDivider = UIView()
        firstDivider.backgroundColor = UIColor.separator.withAlphaComponent(0.35)
        firstDivider.translatesAutoresizingMaskIntoConstraints = false
        durationMetric.addSubview(firstDivider)
        NSLayoutConstraint.activate([
            firstDivider.leadingAnchor.constraint(equalTo: durationMetric.leadingAnchor),
            firstDivider.topAnchor.constraint(equalTo: durationMetric.topAnchor, constant: 5),
            firstDivider.bottomAnchor.constraint(equalTo: durationMetric.bottomAnchor, constant: -5),
            firstDivider.widthAnchor.constraint(equalToConstant: 1)
        ])

        let secondDivider = UIView()
        secondDivider.backgroundColor = UIColor.separator.withAlphaComponent(0.35)
        secondDivider.translatesAutoresizingMaskIntoConstraints = false
        energyMetric.addSubview(secondDivider)
        NSLayoutConstraint.activate([
            secondDivider.leadingAnchor.constraint(equalTo: energyMetric.leadingAnchor),
            secondDivider.topAnchor.constraint(equalTo: energyMetric.topAnchor, constant: 5),
            secondDivider.bottomAnchor.constraint(equalTo: energyMetric.bottomAnchor, constant: -5),
            secondDivider.widthAnchor.constraint(equalToConstant: 1)
        ])

        let metricsStack = UIStackView(
            arrangedSubviews: [distanceMetric, durationMetric, energyMetric]
        )
        metricsStack.translatesAutoresizingMaskIntoConstraints = false
        metricsStack.axis = .horizontal
        metricsStack.distribution = .fillEqually
        metricsStack.spacing = 0
        cardView.addSubview(metricsStack)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            iconContainer.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            iconContainer.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 20),
            iconContainer.widthAnchor.constraint(equalToConstant: 48),
            iconContainer.heightAnchor.constraint(equalToConstant: 48),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 25),
            iconView.heightAnchor.constraint(equalToConstant: 25),

            titleStack.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 14),
            titleStack.topAnchor.constraint(equalTo: iconContainer.topAnchor, constant: 1),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -12),

            chevron.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20),
            chevron.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 8),

            metricsStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            metricsStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20),
            metricsStack.topAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: 20),
            metricsStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -20),
            metricsStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 52)
        ])
    }
}

final class WorkoutMetricView: UIView {
    private let valueLabel = UILabel()
    private let captionLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    func configure(value: String, label: String, color: UIColor) {
        valueLabel.text = value
        valueLabel.textColor = color
        captionLabel.text = label
        accessibilityLabel = "\(label), \(value)"
    }

    private func configureView() {
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.numberOfLines = 1
        valueLabel.minimumScaleFactor = 0.75
        valueLabel.adjustsFontSizeToFitWidth = true

        captionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        captionLabel.adjustsFontForContentSizeCategory = true
        captionLabel.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [valueLabel, captionLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        isAccessibilityElement = true
    }
}

final class WorkoutJournalTimelineCell: UITableViewCell {
    static let reuseIdentifier = "WorkoutJournalTimelineCell"

    private let railView = UIView()
    private let dotView = UIView()
    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let sourceLabel = UILabel()
    private let distanceLabel = UILabel()
    private let detailsLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with workout: HKWorkout) {
        let accent = WorkoutPresentation.accentColor(for: workout.workoutActivityType)
        dotView.backgroundColor = accent
        iconContainer.backgroundColor = accent.withAlphaComponent(0.12)
        iconView.tintColor = accent
        iconView.image = UIImage(
            systemName: WorkoutPresentation.symbol(for: workout.workoutActivityType),
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        )

        titleLabel.text = workout.workoutActivityType.name
        sourceLabel.text = WorkoutPresentation.sourceAndTime(for: workout)
        distanceLabel.text = WorkoutPresentation.distance(for: workout)

        let details = NSMutableAttributedString(
            string: WorkoutPresentation.duration(for: workout),
            attributes: [
                .foregroundColor: accent,
                .font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            ]
        )
        details.append(
            NSAttributedString(
                string: " · \(WorkoutPresentation.energy(for: workout))",
                attributes: [
                    .foregroundColor: UIColor.systemPink,
                    .font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
                ]
            )
        )
        detailsLabel.attributedText = details

        isAccessibilityElement = true
        accessibilityLabel = [
            workout.workoutActivityType.name,
            sourceLabel.text,
            distanceLabel.text,
            WorkoutPresentation.duration(for: workout),
            WorkoutPresentation.energy(for: workout)
        ].compactMap { $0 }.joined(separator: ", ")
        accessibilityTraits = .button
    }

    private func configureView() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .default

        railView.translatesAutoresizingMaskIntoConstraints = false
        railView.backgroundColor = UIColor.separator.withAlphaComponent(0.45)
        contentView.addSubview(railView)

        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.layer.cornerRadius = 4
        contentView.addSubview(dotView)

        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.layer.cornerRadius = 13
        contentView.addSubview(iconContainer)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconContainer.addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label

        sourceLabel.font = .preferredFont(forTextStyle: .caption1)
        sourceLabel.adjustsFontForContentSizeCategory = true
        sourceLabel.textColor = .secondaryLabel
        sourceLabel.lineBreakMode = .byTruncatingTail

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, sourceLabel])
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.axis = .vertical
        titleStack.spacing = 3
        contentView.addSubview(titleStack)

        distanceLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        distanceLabel.adjustsFontForContentSizeCategory = true
        distanceLabel.textColor = .label
        distanceLabel.textAlignment = .right

        detailsLabel.font = .preferredFont(forTextStyle: .caption1)
        detailsLabel.adjustsFontForContentSizeCategory = true
        detailsLabel.textAlignment = .right
        detailsLabel.lineBreakMode = .byTruncatingTail

        let valueStack = UIStackView(arrangedSubviews: [distanceLabel, detailsLabel])
        valueStack.translatesAutoresizingMaskIntoConstraints = false
        valueStack.axis = .vertical
        valueStack.alignment = .trailing
        valueStack.spacing = 3
        contentView.addSubview(valueStack)

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = .tertiaryLabel
        contentView.addSubview(chevron)

        NSLayoutConstraint.activate([
            railView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 19),
            railView.topAnchor.constraint(equalTo: contentView.topAnchor),
            railView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            railView.widthAnchor.constraint(equalToConstant: 1),

            dotView.centerXAnchor.constraint(equalTo: railView.centerXAnchor),
            dotView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 29),
            dotView.widthAnchor.constraint(equalToConstant: 8),
            dotView.heightAnchor.constraint(equalToConstant: 8),

            iconContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 34),
            iconContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            iconContainer.widthAnchor.constraint(equalToConstant: 40),
            iconContainer.heightAnchor.constraint(equalToConstant: 40),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            titleStack.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            titleStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: valueStack.leadingAnchor, constant: -10),

            valueStack.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -10),
            valueStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            valueStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 108),

            chevron.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            chevron.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 7),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 68)
        ])
    }
}

final class WorkoutJournalEmptyCell: UITableViewCell {
    static let reuseIdentifier = "WorkoutJournalEmptyCell"

    private let cardView = UIView()
    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, subtitle: String) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        accessibilityLabel = "\(title). \(subtitle)"
    }

    private func configureView() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = .secondarySystemBackground
        cardView.layer.cornerRadius = 22
        contentView.addSubview(cardView)

        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.12)
        iconContainer.layer.cornerRadius = 16
        cardView.addSubview(iconContainer)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(
            systemName: "leaf",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        )
        iconView.tintColor = .systemGreen
        iconContainer.addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label

        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 5
        cardView.addSubview(stack)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            iconContainer.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            iconContainer.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 22),
            iconContainer.widthAnchor.constraint(equalToConstant: 48),
            iconContainer.heightAnchor.constraint(equalToConstant: 48),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            stack.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20),
            stack.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: cardView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -20),
            cardView.bottomAnchor.constraint(greaterThanOrEqualTo: iconContainer.bottomAnchor, constant: 20)
        ])

        isAccessibilityElement = true
    }
}

final class WorkoutJournalSectionHeaderView: UIView {
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    func configure(title: String, subtitle: String?, isOverline: Bool = false) {
        titleLabel.text = isOverline ? title.uppercased() : title
        titleLabel.font = isOverline
            ? .systemFont(ofSize: 11, weight: .semibold)
            : .systemFont(ofSize: 21, weight: .semibold)
        titleLabel.textColor = isOverline ? .secondaryLabel : .label
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
    }

    private func configureView() {
        backgroundColor = .clear

        titleLabel.adjustsFontForContentSizeCategory = true

        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 2
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }
}
