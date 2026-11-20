import Foundation
import HealthKit

struct DailyHealthMetric {
    let date: Date
    let value: Double
}

struct DashboardActivityRings {
    let date: Date
    let move: Double
    let moveGoal: Double
    let exercise: Double
    let exerciseGoal: Double
    let stand: Double
    let standGoal: Double

    var moveProgress: Double {
        progress(move, goal: moveGoal)
    }

    var exerciseProgress: Double {
        progress(exercise, goal: exerciseGoal)
    }

    var standProgress: Double {
        progress(stand, goal: standGoal)
    }

    private func progress(_ value: Double, goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        return min(max(value / goal, 0), 1)
    }
}

enum DashboardHealthMetric: Int, CaseIterable {
    case sleep
    case steps
    case water
    case rings

    var title: String {
        switch self {
        case .sleep: return "睡眠"
        case .steps: return "步数"
        case .water: return "饮水"
        case .rings: return "圆环"
        }
    }

    var unitLabel: String {
        switch self {
        case .sleep: return "小时"
        case .steps: return "步"
        case .water: return "毫升"
        case .rings: return "完成度"
        }
    }
}

enum DashboardCalendar {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .current
        calendar.firstWeekday = 1
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    static func yearInterval(_ year: Int) -> (start: Date, end: Date) {
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? start
        return (start, end)
    }

    static func date(year: Int, month: Int, day: Int) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

final class DashboardHealthData {
    static let shared = DashboardHealthData()

    private let healthStore = HKHealthStore()

    private init() {}

    func requestAuthorization(completion: @escaping () -> Void) {
        var types = Health.shared().readObjectTypes()
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        if let water = HKObjectType.quantityType(forIdentifier: .dietaryWater) {
            types.insert(water)
        }
        healthStore.requestAuthorization(toShare: [], read: types) { _, _ in
            completion()
        }
    }

    func load(
        metric: DashboardHealthMetric,
        year: Int,
        completion: @escaping ([DailyHealthMetric]) -> Void
    ) {
        switch metric {
        case .sleep:
            loadSleep(year: year, completion: completion)
        case .steps:
            loadDailyQuantity(
                identifier: .stepCount,
                unit: .count(),
                year: year,
                completion: completion
            )
        case .water:
            loadDailyQuantity(
                identifier: .dietaryWater,
                unit: .literUnit(with: .milli),
                year: year,
                completion: completion
            )
        case .rings:
            loadActivityRings(year: year, completion: completion)
        }
    }

    func loadActivityRings(
        year: Int,
        completion: @escaping ([DailyHealthMetric]) -> Void
    ) {
        let interval = DashboardCalendar.yearInterval(year)
        let calendar = DashboardCalendar.calendar
        var startComponents = calendar.dateComponents([.year, .month, .day], from: interval.start)
        var endComponents = calendar.dateComponents([.year, .month, .day], from: interval.end)
        startComponents.calendar = calendar
        endComponents.calendar = calendar

        let predicate = HKQuery.predicate(
            forActivitySummariesBetweenStart: startComponents,
            end: endComponents
        )
        let query = HKActivitySummaryQuery(predicate: predicate) { [weak self] _, summaries, _ in
            guard let self = self else { return }
            let records = (summaries ?? []).compactMap { summary -> DailyHealthMetric? in
                guard let date = calendar.date(from: summary.dateComponents(for: calendar)) else {
                    return nil
                }
                return DailyHealthMetric(
                    date: calendar.startOfDay(for: date),
                    value: self.ringProgress(for: summary)
                )
            }
            self.deliver(records.sorted { $0.date < $1.date }, completion: completion)
        }
        healthStore.execute(query)
    }

    func loadLatestActivityRings(
        completion: @escaping (DashboardActivityRings?) -> Void
    ) {
        let calendar = DashboardCalendar.calendar
        let end = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -32, to: end) else {
            completion(nil)
            return
        }
        var startComponents = calendar.dateComponents([.year, .month, .day], from: start)
        var endComponents = calendar.dateComponents([.year, .month, .day], from: end)
        startComponents.calendar = calendar
        endComponents.calendar = calendar
        let predicate = HKQuery.predicate(
            forActivitySummariesBetweenStart: startComponents,
            end: endComponents
        )
        let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
            let result = (summaries ?? []).compactMap { summary -> DashboardActivityRings? in
                guard let date = calendar.date(from: summary.dateComponents(for: calendar)) else {
                    return nil
                }
                return DashboardActivityRings(
                    date: calendar.startOfDay(for: date),
                    move: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                    moveGoal: summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
                    exercise: summary.appleExerciseTime.doubleValue(for: .minute()),
                    exerciseGoal: summary.appleExerciseTimeGoal.doubleValue(for: .minute()),
                    stand: summary.appleStandHours.doubleValue(for: .count()),
                    standGoal: summary.appleStandHoursGoal.doubleValue(for: .count())
                )
            }.max { $0.date < $1.date }
            DispatchQueue.main.async {
                completion(result)
            }
        }
        healthStore.execute(query)
    }

    private func loadDailyQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        year: Int,
        completion: @escaping ([DailyHealthMetric]) -> Void
    ) {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            completion([])
            return
        }

        let interval = DashboardCalendar.yearInterval(year)
        let calendar = DashboardCalendar.calendar
        let predicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: .strictStartDate
        )
        let query = HKStatisticsCollectionQuery(
            quantityType: quantityType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum,
            anchorDate: interval.start,
            intervalComponents: DateComponents(day: 1)
        )
        query.initialResultsHandler = { [weak self] _, collection, _ in
            guard let self = self else { return }
            var records: [DailyHealthMetric] = []
            collection?.enumerateStatistics(from: interval.start, to: interval.end) { statistics, _ in
                guard let sum = statistics.sumQuantity() else { return }
                let value = sum.doubleValue(for: unit)
                if value > 0 {
                    records.append(
                        DailyHealthMetric(
                            date: calendar.startOfDay(for: statistics.startDate),
                            value: value
                        )
                    )
                }
            }
            self.deliver(records, completion: completion)
        }
        healthStore.execute(query)
    }

    private func loadSleep(
        year: Int,
        completion: @escaping ([DailyHealthMetric]) -> Void
    ) {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion([])
            return
        }

        let interval = DashboardCalendar.yearInterval(year)
        let calendar = DashboardCalendar.calendar
        let predicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: []
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { [weak self] _, samples, _ in
            guard let self = self else { return }
            let sleepSamples = (samples as? [HKCategorySample] ?? []).filter(isAsleep)
            let grouped = Dictionary(grouping: sleepSamples) {
                calendar.startOfDay(for: $0.endDate)
            }
            let records = grouped.compactMap { date, samples -> DailyHealthMetric? in
                let mergedSeconds = self.mergedDuration(
                    intervals: samples.map { ($0.startDate, $0.endDate) }
                )
                guard mergedSeconds > 0 else { return nil }
                return DailyHealthMetric(date: date, value: mergedSeconds / 60)
            }
            self.deliver(records.sorted { $0.date < $1.date }, completion: completion)
        }
        healthStore.execute(query)
    }

    private func isAsleep(_ sample: HKCategorySample) -> Bool {
        if #available(iOS 16.0, *) {
            switch sample.value {
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                 HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                 HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                 HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                return true
            default:
                return false
            }
        }
        return sample.value == HKCategoryValueSleepAnalysis.asleep.rawValue
    }

    private func mergedDuration(intervals: [(Date, Date)]) -> TimeInterval {
        let sorted = intervals.sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var currentStart: Date?
        var currentEnd: Date?

        sorted.forEach { interval in
            guard let start = currentStart, let end = currentEnd else {
                currentStart = interval.0
                currentEnd = interval.1
                return
            }
            if interval.0 <= end {
                currentEnd = max(end, interval.1)
            } else {
                total += end.timeIntervalSince(start)
                currentStart = interval.0
                currentEnd = interval.1
            }
        }
        if let start = currentStart, let end = currentEnd {
            total += end.timeIntervalSince(start)
        }
        return total
    }

    private func ringProgress(for summary: HKActivitySummary) -> Double {
        let move = ratio(
            summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
            goal: summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
        )
        let exercise = ratio(
            summary.appleExerciseTime.doubleValue(for: .minute()),
            goal: summary.appleExerciseTimeGoal.doubleValue(for: .minute())
        )
        let stand = ratio(
            summary.appleStandHours.doubleValue(for: .count()),
            goal: summary.appleStandHoursGoal.doubleValue(for: .count())
        )
        return (move + exercise + stand) / 3
    }

    private func ratio(_ value: Double, goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        return min(max(value / goal, 0), 1)
    }

    private func deliver(
        _ records: [DailyHealthMetric],
        completion: @escaping ([DailyHealthMetric]) -> Void
    ) {
        DispatchQueue.main.async {
            completion(records)
        }
    }
}

enum WorkoutActivityFamily: Int, CaseIterable {
    case running
    case walking
    case cycling

    var title: String {
        switch self {
        case .running: return "跑步"
        case .walking: return "步行"
        case .cycling: return "骑行"
        }
    }

    var activityType: HKWorkoutActivityType {
        switch self {
        case .running: return .running
        case .walking: return .walking
        case .cycling: return .cycling
        }
    }

    func matches(_ workout: HKWorkout) -> Bool {
        workout.workoutActivityType == activityType
    }
}

extension Array where Element == DailyHealthMetric {
    func value(on date: Date) -> Double? {
        let day = DashboardCalendar.calendar.startOfDay(for: date)
        return first {
            DashboardCalendar.calendar.isDate($0.date, inSameDayAs: day)
        }?.value
    }
}
