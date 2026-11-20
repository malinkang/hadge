import Foundation
import HealthKit

// This builder keeps the related HealthKit queries together so they can share
// one authorization pass and merge their results into a single snapshot.
// swiftlint:disable file_length type_body_length function_body_length

final class HealthExportSnapshotBuilder {
    private let healthStore: HKHealthStore?
    private var calendar: Calendar
    private let lock = NSLock()

    init(healthStore: HKHealthStore? = Health.shared().healthStore) {
        self.healthStore = healthStore
        self.calendar = Calendar(identifier: .gregorian)
        self.calendar.locale = Locale(identifier: "zh_CN")
        self.calendar.timeZone = .current
        self.calendar.firstWeekday = 1
        self.calendar.minimumDaysInFirstWeek = 1
    }

    func build(
        includeRawRecords: Bool,
        progress: ((String) -> Void)? = nil,
        completion: @escaping (Result<HealthExportSnapshot, Error>) -> Void
    ) {
        guard let healthStore = healthStore else {
            completion(.failure(HealthExportSnapshotError.healthStoreUnavailable))
            return
        }

        let end = Date()
        let start = calendar.date(
            from: DateComponents(year: 2014, month: 1, day: 1)
        ) ?? end

        let readTypes = exportReadTypes()
        healthStore.requestAuthorization(
            toShare: [],
            read: readTypes
        ) { [weak self] success, error in
            guard let self = self else { return }
            guard success else {
                completion(.failure(HealthExportSnapshotError.authorizationFailed(
                    error?.localizedDescription
                )))
                return
            }
            self.updateProgress("读取每日健康数据", handler: progress)

            let group = DispatchGroup()
            var stepsByDay: [Date: Double] = [:]
            var waterByDay: [Date: Double] = [:]
            var sleepByDay: [Date: Double] = [:]
            var summaries: [HKActivitySummary] = []
            var workouts: [WorkoutHealthRecord] = []
            var rawRecords: [RawHealthExportRecord] = []

            group.enter()
            self.loadDailyQuantity(
                identifier: .stepCount,
                unit: .count(),
                start: start,
                end: end
            ) { values in
                self.lock.lock()
                stepsByDay = values
                self.lock.unlock()
                group.leave()
            }

            group.enter()
            self.loadDailyQuantity(
                identifier: .dietaryWater,
                unit: .literUnit(with: .milli),
                start: start,
                end: end
            ) { values in
                self.lock.lock()
                waterByDay = values
                self.lock.unlock()
                group.leave()
            }

            group.enter()
            self.loadSleep(start: start, end: end) { values in
                self.lock.lock()
                sleepByDay = values
                self.lock.unlock()
                group.leave()
            }

            group.enter()
            self.loadActivitySummaries(start: start, end: end) { values in
                self.lock.lock()
                summaries = values
                self.lock.unlock()
                group.leave()
            }

            group.enter()
            self.updateProgress("读取运动记录、心率与路线", handler: progress)
            self.loadWorkouts(start: start, end: end) { values in
                self.lock.lock()
                workouts = values
                self.lock.unlock()
                group.leave()
            }

            if includeRawRecords {
                group.enter()
                self.updateProgress("读取原始健康记录", handler: progress)
                let modules = Health.enabledExportModules()
                self.collectRawRecords(
                    modules: modules,
                    index: 0,
                    start: start,
                    end: end,
                    accumulator: []
                ) { values in
                    self.lock.lock()
                    rawRecords = values
                    self.lock.unlock()
                    group.leave()
                }
            }

            group.notify(queue: .global(qos: .userInitiated)) {
                self.lock.lock()
                let collectedSteps = stepsByDay
                let collectedWater = waterByDay
                let collectedSleep = sleepByDay
                let collectedSummaries = summaries
                let collectedWorkouts = workouts
                let collectedRawRecords = rawRecords
                self.lock.unlock()

                let daily = self.makeDailyRecords(
                    stepsByDay: collectedSteps,
                    waterByDay: collectedWater,
                    sleepByDay: collectedSleep,
                    summaries: collectedSummaries
                )
                let snapshot = HealthExportSnapshot(
                    schemaVersion: 1,
                    exportedAt: Date(),
                    range: HealthExportDateRange(start: start, end: end),
                    daily: daily,
                    workouts: collectedWorkouts,
                    rawRecords: collectedRawRecords.sorted { $0.date < $1.date }
                )
                completion(.success(snapshot))
            }
        }
    }

    private func exportReadTypes() -> Set<HKObjectType> {
        var types = Health.shared().readObjectTypes()
        if let water = HKObjectType.quantityType(forIdentifier: .dietaryWater) {
            types.insert(water)
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        return types
    }

    private func loadDailyQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date,
        completion: @escaping ([Date: Double]) -> Void
    ) {
        guard
            let healthStore = healthStore,
            let type = HKObjectType.quantityType(forIdentifier: identifier)
        else {
            completion([:])
            return
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )
        let query = HKStatisticsCollectionQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum,
            anchorDate: calendar.startOfDay(for: start),
            intervalComponents: DateComponents(day: 1)
        )
        query.initialResultsHandler = { [weak self] _, collection, _ in
            guard let self = self else { return }
            var values: [Date: Double] = [:]
            collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                guard let quantity = statistics.sumQuantity() else { return }
                let value = quantity.doubleValue(for: unit)
                guard value > 0 else { return }
                values[self.calendar.startOfDay(for: statistics.startDate)] = value
            }
            completion(values)
        }
        healthStore.execute(query)
    }

    private func loadSleep(
        start: Date,
        end: Date,
        completion: @escaping ([Date: Double]) -> Void
    ) {
        guard
            let healthStore = healthStore,
            let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        else {
            completion([:])
            return
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: []
        )
        let sort = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: true
        )
        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { [weak self] _, samples, _ in
            guard let self = self else { return }
            let sleepSamples = (samples as? [HKCategorySample] ?? [])
                .filter(self.isAsleep)
            let grouped = Dictionary(grouping: sleepSamples) {
                self.calendar.startOfDay(for: $0.endDate)
            }
            var values: [Date: Double] = [:]
            grouped.forEach { date, samples in
                let duration = self.mergedDuration(
                    intervals: samples.map { ($0.startDate, $0.endDate) }
                )
                if duration > 0 {
                    values[date] = duration / 60
                }
            }
            completion(values)
        }
        healthStore.execute(query)
    }

    private func loadActivitySummaries(
        start: Date,
        end: Date,
        completion: @escaping ([HKActivitySummary]) -> Void
    ) {
        guard let healthStore = healthStore else {
            completion([])
            return
        }

        var startComponents = calendar.dateComponents(
            [.year, .month, .day],
            from: start
        )
        var endComponents = calendar.dateComponents(
            [.year, .month, .day],
            from: end
        )
        startComponents.calendar = calendar
        endComponents.calendar = calendar
        let predicate = HKQuery.predicate(
            forActivitySummariesBetweenStart: startComponents,
            end: endComponents
        )
        let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
            completion(summaries ?? [])
        }
        healthStore.execute(query)
    }

    private func loadWorkouts(
        start: Date,
        end: Date,
        completion: @escaping ([WorkoutHealthRecord]) -> Void
    ) {
        guard let healthStore = healthStore else {
            completion([])
            return
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: []
        )
        let sort = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: true
        )
        let query = HKSampleQuery(
            sampleType: .workoutType(),
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { [weak self] _, samples, _ in
            guard let self = self else { return }
            let workouts = (samples as? [HKWorkout] ?? [])
            self.enrichWorkouts(workouts, completion: completion)
        }
        healthStore.execute(query)
    }

    private func enrichWorkouts(
        _ workouts: [HKWorkout],
        completion: @escaping ([WorkoutHealthRecord]) -> Void
    ) {
        guard !workouts.isEmpty else {
            completion([])
            return
        }

        let state = WorkoutEnrichmentState(count: workouts.count)
        enrichWorkoutBatch(
            workouts,
            startIndex: 0,
            state: state,
            completion: completion
        )
    }

    private func enrichWorkoutBatch(
        _ workouts: [HKWorkout],
        startIndex: Int,
        state: WorkoutEnrichmentState,
        completion: @escaping ([WorkoutHealthRecord]) -> Void
    ) {
        guard startIndex < workouts.count else {
            completion(state.records)
            return
        }

        let endIndex = min(startIndex + 4, workouts.count)
        let group = DispatchGroup()
        for index in startIndex..<endIndex {
            group.enter()
            enrichWorkout(workouts[index]) { record in
                state.set(record, at: index)
                group.leave()
            }
        }
        group.notify(queue: .global(qos: .userInitiated)) {
            self.enrichWorkoutBatch(
                workouts,
                startIndex: endIndex,
                state: state,
                completion: completion
            )
        }
    }

    private func enrichWorkout(
        _ workout: HKWorkout,
        completion: @escaping (WorkoutHealthRecord) -> Void
    ) {
        loadHeartRate(for: workout) { minimum, average, maximum in
            self.loadRoutePointCount(for: workout) { count, includesRoute in
                let category = self.notionCategory(for: workout.workoutActivityType)
                let time = DateFormatter.healthExportWorkoutTime.string(
                    from: workout.startDate
                )
                let distance = workout.totalDistance?
                    .doubleValue(for: .meter())
                    .divided(by: 1000)
                let energy = workout.totalEnergyBurned?
                    .doubleValue(for: .kilocalorie())
                completion(WorkoutHealthRecord(
                    syncID: "workout-\(workout.uuid.uuidString.lowercased())",
                    name: "\(time) \(category)",
                    startDate: workout.startDate,
                    endDate: workout.endDate,
                    activityType: workout.workoutActivityType.name,
                    activityCategory: category,
                    durationMinutes: workout.duration / 60,
                    distanceKilometers: distance,
                    activeEnergyKilocalories: energy,
                    minimumHeartRate: minimum,
                    averageHeartRate: average,
                    maximumHeartRate: maximum,
                    routePointCount: count,
                    includesRoute: includesRoute
                ))
            }
        }
    }

    private func loadHeartRate(
        for workout: HKWorkout,
        completion: @escaping (Double?, Double?, Double?) -> Void
    ) {
        guard
            let healthStore = healthStore,
            let type = HKObjectType.quantityType(forIdentifier: .heartRate)
        else {
            completion(nil, nil, nil)
            return
        }
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: []
        )
        let query = HKStatisticsQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: [.discreteMin, .discreteAverage, .discreteMax]
        ) { _, statistics, _ in
            let unit = HKUnit.count().unitDivided(by: .minute())
            completion(
                statistics?.minimumQuantity()?.doubleValue(for: unit),
                statistics?.averageQuantity()?.doubleValue(for: unit),
                statistics?.maximumQuantity()?.doubleValue(for: unit)
            )
        }
        healthStore.execute(query)
    }

    private func loadRoutePointCount(
        for workout: HKWorkout,
        completion: @escaping (Int, Bool) -> Void
    ) {
        guard let healthStore = healthStore else {
            completion(0, false)
            return
        }
        let predicate = HKQuery.predicateForObjects(from: workout)
        let sort = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: true
        )
        let query = HKSampleQuery(
            sampleType: HKSeriesType.workoutRoute(),
            predicate: predicate,
            limit: 1,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            guard
                let route = (samples as? [HKWorkoutRoute])?.first
            else {
                completion(0, false)
                return
            }

            var count = 0
            var finished = false
            let routeQuery = HKWorkoutRouteQuery(route: route) {
                _, locations, done, error in
                count += locations?.count ?? 0
                guard !finished else { return }
                if error != nil {
                    finished = true
                    completion(count, count > 0)
                    return
                }
                guard done else { return }
                finished = true
                completion(count, count > 0)
            }
            healthStore.execute(routeQuery)
        }
        healthStore.execute(query)
    }

    private func collectRawRecords(
        modules: [HealthExportModule],
        index: Int,
        start: Date,
        end: Date,
        accumulator: [RawHealthExportRecord],
        completion: @escaping ([RawHealthExportRecord]) -> Void
    ) {
        guard index < modules.count else {
            completion(accumulator)
            return
        }

        let module = modules[index]
        Health.shared().getHealthRecords(
            for: module,
            start: start,
            end: end
        ) { records in
            let mapped = records.map {
                RawHealthExportRecord(
                    module: module.rawValue,
                    date: $0.date,
                    fields: $0.fields
                )
            }
            self.collectRawRecords(
                modules: modules,
                index: index + 1,
                start: start,
                end: end,
                accumulator: accumulator + mapped,
                completion: completion
            )
        }
    }

    private func makeDailyRecords(
        stepsByDay: [Date: Double],
        waterByDay: [Date: Double],
        sleepByDay: [Date: Double],
        summaries: [HKActivitySummary]
    ) -> [DailyHealthRecord] {
        var summaryByDay: [Date: HKActivitySummary] = [:]
        summaries.forEach { summary in
            guard let date = calendar.date(
                from: summary.dateComponents(for: calendar)
            ) else {
                return
            }
            summaryByDay[calendar.startOfDay(for: date)] = summary
        }
        let allDates = Set(stepsByDay.keys)
            .union(waterByDay.keys)
            .union(sleepByDay.keys)
            .union(summaryByDay.keys)

        return allDates.sorted().compactMap { date in
            let summary = summaryByDay[date]
            let record = DailyHealthRecord(
                syncID: "daily-\(HealthExportFormatter.isoDay(date))",
                date: date,
                steps: stepsByDay[date],
                waterMilliliters: waterByDay[date],
                sleepMinutes: sleepByDay[date],
                activeEnergyKilocalories: summary?.activeEnergyBurned
                    .doubleValue(for: .kilocalorie()),
                exerciseMinutes: summary?.appleExerciseTime
                    .doubleValue(for: .minute()),
                standHours: summary?.appleStandHours
                    .doubleValue(for: .count()),
                activeEnergyGoal: summary?.activeEnergyBurnedGoal
                    .doubleValue(for: .kilocalorie()),
                exerciseGoal: summary?.appleExerciseTimeGoal
                    .doubleValue(for: .minute()),
                standGoal: summary?.appleStandHoursGoal
                    .doubleValue(for: .count())
            )
            let hasData = [
                record.steps,
                record.waterMilliliters,
                record.sleepMinutes,
                record.activeEnergyKilocalories,
                record.exerciseMinutes,
                record.standHours
            ].contains { ($0 ?? 0) > 0 }
            return hasData ? record : nil
        }
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

    private func mergedDuration(
        intervals: [(Date, Date)]
    ) -> TimeInterval {
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

    private func notionCategory(
        for activityType: HKWorkoutActivityType
    ) -> String {
        switch activityType {
        case .running:
            return "跑步"
        case .walking:
            return "步行"
        case .cycling, .handCycling:
            return "骑行"
        case .swimming:
            return "游泳"
        case .hiking:
            return "徒步"
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            return "力量训练"
        default:
            return "其他"
        }
    }

    private func updateProgress(
        _ text: String,
        handler: ((String) -> Void)?
    ) {
        DispatchQueue.main.async {
            handler?(text)
        }
    }
}

enum HealthExportSnapshotError: LocalizedError {
    case healthStoreUnavailable
    case authorizationFailed(String?)

    var errorDescription: String? {
        switch self {
        case .healthStoreUnavailable:
            return "HealthKit 当前不可用。"
        case .authorizationFailed(let detail):
            if let detail = detail, !detail.isEmpty {
                return "无法读取 Apple 健康数据：\(detail)"
            }
            return "无法获得 Apple 健康读取权限。请前往“设置 → 健康 → 数据访问与设备 → Hadge”检查授权。"
        }
    }
}

private final class WorkoutEnrichmentState {
    private let lock = NSLock()
    private var indexedRecords: [WorkoutHealthRecord?]

    init(count: Int) {
        indexedRecords = Array(repeating: nil, count: count)
    }

    var records: [WorkoutHealthRecord] {
        lock.lock()
        defer { lock.unlock() }
        return indexedRecords.compactMap { $0 }
    }

    func set(_ record: WorkoutHealthRecord, at index: Int) {
        lock.lock()
        indexedRecords[index] = record
        lock.unlock()
    }
}

private extension Double {
    func divided(by divisor: Double) -> Double {
        guard divisor != 0 else { return 0 }
        return self / divisor
    }
}

private extension DateFormatter {
    static let healthExportWorkoutTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}
