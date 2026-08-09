import HealthKit
import SwiftCSV
import SwiftDate

enum HealthExportModule: String, CaseIterable {
    case body
    case heartRate = "heart-rate"
    case vitals
    case sleep
    case bloodPressure = "blood-pressure"
    case nutrition
    case mobility
    case mindfulness

    var title: String {
        switch self {
        case .body: return "Body measurements"
        case .heartRate: return "Heart rate summaries"
        case .vitals: return "Heart and vital signs"
        case .sleep: return "Sleep"
        case .bloodPressure: return "Blood pressure"
        case .nutrition: return "Nutrition and water"
        case .mobility: return "Mobility"
        case .mindfulness: return "Mindfulness"
        }
    }

    var defaultsKey: String {
        return "healthExport.\(rawValue)"
    }

    var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: defaultsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: defaultsKey)
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: defaultsKey)
    }
}

struct HealthMetricDefinition {
    let identifier: HKQuantityTypeIdentifier
    let name: String
    let unit: HKUnit
    let unitLabel: String
    let multiplier: Double

    init(
        identifier: HKQuantityTypeIdentifier,
        name: String,
        unit: HKUnit,
        unitLabel: String,
        multiplier: Double = 1
    ) {
        self.identifier = identifier
        self.name = name
        self.unit = unit
        self.unitLabel = unitLabel
        self.multiplier = multiplier
    }
}

struct HealthExportRecord {
    let date: Date
    let fields: [String]
}

extension Notification.Name {
    static let didReceiveHealthAccess = Notification.Name("didReceiveHealthAccess")
}

class Health {
    static let sharedInstance = Health()
    static let exportAuthorizationVersion = 1

    var healthStore: HKHealthStore?
    var distanceDataSource: DistanceDataSource?
    var locationDataSource: LocationDataSource?
    var sampleDataSource: SampleDataSource?
    var splitsDataSource: SplitsDataSource?

    var year: Int
    var firstOfYear: Date?
    var lastOfYear: Date?
    var today: Date?
    var yesterday: Date?
    var stopExport: Bool = false

    static func shared() -> Health {
        return sharedInstance
    }

    static func enabledExportModules() -> [HealthExportModule] {
        return HealthExportModule.allCases.filter { $0.isEnabled }
    }

    init() {
        self.healthStore = HKHealthStore()
        self.distanceDataSource = DistanceDataSource()
        self.locationDataSource = LocationDataSource()
        self.sampleDataSource = SampleDataSource()
        self.splitsDataSource = SplitsDataSource()

        let calendar = Calendar.current
        self.year = calendar.component(.year, from: Date())
        self.firstOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
        self.today = calendar.startOfDay(for: Date.init())
        self.yesterday = calendar.date(byAdding: .day, value: -1, to: self.today!)

        let firstOfNextYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))
        self.lastOfYear = calendar.date(byAdding: .day, value: -1, to: firstOfNextYear!)
    }
}

extension Health {
    func readObjectTypes() -> Set<HKObjectType> {
        var objectTypes: Set<HKObjectType> = [
            HKObjectType.activitySummaryType(),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
            HKObjectType.quantityType(forIdentifier: .distanceDownhillSnowSports)!,
            HKObjectType.quantityType(forIdentifier: .distanceSwimming)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .distanceWheelchair)!,
            HKObjectType.quantityType(forIdentifier: .flightsClimbed)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .swimmingStrokeCount)!,
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKObjectType.characteristicType(forIdentifier: .biologicalSex)!
        ]

        Health.enabledExportModules().forEach { module in
            objectTypes.formUnion(readObjectTypes(for: module))
        }
        return objectTypes
    }

    func readObjectTypes(for module: HealthExportModule) -> Set<HKObjectType> {
        var objectTypes = Set<HKObjectType>()
        metricDefinitions(for: module).forEach { definition in
            if let quantityType = HKObjectType.quantityType(forIdentifier: definition.identifier) {
                objectTypes.insert(quantityType)
            }
        }

        switch module {
        case .sleep:
            if let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
                objectTypes.insert(type)
            }
        case .bloodPressure:
            if let type = HKObjectType.correlationType(forIdentifier: .bloodPressure) {
                objectTypes.insert(type)
            }
            if let systolic = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic) {
                objectTypes.insert(systolic)
            }
            if let diastolic = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic) {
                objectTypes.insert(diastolic)
            }
        case .mindfulness:
            if let type = HKObjectType.categoryType(forIdentifier: .mindfulSession) {
                objectTypes.insert(type)
            }
        default:
            break
        }
        return objectTypes
    }

    func requestAuthorization(for modules: [HealthExportModule], completionHandler: @escaping (Bool) -> Void) {
        var objectTypes = Set<HKObjectType>()
        modules.forEach { objectTypes.formUnion(readObjectTypes(for: $0)) }
        guard !objectTypes.isEmpty else { completionHandler(true); return }
        healthStore?.requestAuthorization(toShare: [], read: objectTypes) { success, _ in
            completionHandler(success)
        }
    }

    func requestEnabledExportAuthorizationIfNeeded(completionHandler: @escaping (Bool) -> Void) {
        let currentVersion = UserDefaults.standard.integer(forKey: UserDefaultKeys.healthExportAuthorizationVersion)
        guard currentVersion < Health.exportAuthorizationVersion else { completionHandler(true); return }
        requestAuthorization(for: Health.enabledExportModules()) { success in
            UserDefaults.standard.set(Health.exportAuthorizationVersion, forKey: UserDefaultKeys.healthExportAuthorizationVersion)
            completionHandler(success)
        }
    }

    func metricDefinitions(for module: HealthExportModule) -> [HealthMetricDefinition] {
        let bpm = HKUnit.count().unitDivided(by: HKUnit.minute())
        let breathsPerMinute = HKUnit.count().unitDivided(by: HKUnit.minute())
        let millilitersPerKilogramMinute = HKUnit.literUnit(with: .milli)
            .unitDivided(by: HKUnit.gramUnit(with: .kilo))
            .unitDivided(by: HKUnit.minute())

        switch module {
        case .body:
            return [
                HealthMetricDefinition(identifier: .bodyMass, name: "Body Mass", unit: .gramUnit(with: .kilo), unitLabel: "kg"),
                HealthMetricDefinition(identifier: .bodyMassIndex, name: "Body Mass Index", unit: .count(), unitLabel: "count"),
                HealthMetricDefinition(identifier: .bodyFatPercentage, name: "Body Fat Percentage", unit: .percent(), unitLabel: "%", multiplier: 100),
                HealthMetricDefinition(identifier: .leanBodyMass, name: "Lean Body Mass", unit: .gramUnit(with: .kilo), unitLabel: "kg"),
                HealthMetricDefinition(identifier: .height, name: "Height", unit: .meter(), unitLabel: "m"),
                HealthMetricDefinition(identifier: .waistCircumference, name: "Waist Circumference", unit: .meter(), unitLabel: "m")
            ]
        case .vitals:
            var definitions = [
                HealthMetricDefinition(identifier: .restingHeartRate, name: "Resting Heart Rate", unit: bpm, unitLabel: "count/min"),
                HealthMetricDefinition(identifier: .walkingHeartRateAverage, name: "Walking Heart Rate Average", unit: bpm, unitLabel: "count/min"),
                HealthMetricDefinition(identifier: .heartRateVariabilitySDNN, name: "Heart Rate Variability SDNN", unit: .secondUnit(with: .milli), unitLabel: "ms"),
                HealthMetricDefinition(identifier: .respiratoryRate, name: "Respiratory Rate", unit: breathsPerMinute, unitLabel: "count/min"),
                HealthMetricDefinition(identifier: .oxygenSaturation, name: "Oxygen Saturation", unit: .percent(), unitLabel: "%", multiplier: 100),
                HealthMetricDefinition(identifier: .vo2Max, name: "VO2 Max", unit: millilitersPerKilogramMinute, unitLabel: "mL/(kg*min)"),
                HealthMetricDefinition(identifier: .bodyTemperature, name: "Body Temperature", unit: .degreeCelsius(), unitLabel: "degC"),
                HealthMetricDefinition(
                    identifier: .bloodGlucose,
                    name: "Blood Glucose",
                    unit: HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci)),
                    unitLabel: "mg/dL"
                )
            ]
            if #available(iOS 16.0, *) {
                definitions.append(HealthMetricDefinition(identifier: .appleSleepingWristTemperature, name: "Sleeping Wrist Temperature", unit: .degreeCelsius(), unitLabel: "degC"))
                definitions.append(HealthMetricDefinition(identifier: .heartRateRecoveryOneMinute, name: "One-Minute Heart Rate Recovery", unit: bpm, unitLabel: "count/min"))
                definitions.append(HealthMetricDefinition(identifier: .atrialFibrillationBurden, name: "Atrial Fibrillation Burden", unit: .percent(), unitLabel: "%", multiplier: 100))
            }
            return definitions
        case .heartRate:
            return [
                HealthMetricDefinition(identifier: .heartRate, name: "Heart Rate", unit: bpm, unitLabel: "count/min")
            ]
        case .nutrition:
            return [
                HealthMetricDefinition(identifier: .dietaryWater, name: "Water", unit: .literUnit(with: .milli), unitLabel: "mL"),
                HealthMetricDefinition(identifier: .dietaryEnergyConsumed, name: "Energy Consumed", unit: .kilocalorie(), unitLabel: "kcal"),
                HealthMetricDefinition(identifier: .dietaryProtein, name: "Protein", unit: .gram(), unitLabel: "g"),
                HealthMetricDefinition(identifier: .dietaryCarbohydrates, name: "Carbohydrates", unit: .gram(), unitLabel: "g"),
                HealthMetricDefinition(identifier: .dietaryFatTotal, name: "Total Fat", unit: .gram(), unitLabel: "g"),
                HealthMetricDefinition(identifier: .dietaryFiber, name: "Fiber", unit: .gram(), unitLabel: "g"),
                HealthMetricDefinition(identifier: .dietarySugar, name: "Sugar", unit: .gram(), unitLabel: "g"),
                HealthMetricDefinition(identifier: .dietarySodium, name: "Sodium", unit: .gramUnit(with: .milli), unitLabel: "mg"),
                HealthMetricDefinition(identifier: .dietaryCaffeine, name: "Caffeine", unit: .gramUnit(with: .milli), unitLabel: "mg")
            ]
        case .mobility:
            if #available(iOS 14.0, *) {
                var definitions = [
                    HealthMetricDefinition(identifier: .sixMinuteWalkTestDistance, name: "Six-Minute Walk Test Distance", unit: .meter(), unitLabel: "m"),
                    HealthMetricDefinition(identifier: .walkingSpeed, name: "Walking Speed", unit: .meter().unitDivided(by: .second()), unitLabel: "m/s"),
                    HealthMetricDefinition(identifier: .walkingStepLength, name: "Walking Step Length", unit: .meter(), unitLabel: "m"),
                    HealthMetricDefinition(identifier: .walkingAsymmetryPercentage, name: "Walking Asymmetry", unit: .percent(), unitLabel: "%", multiplier: 100),
                    HealthMetricDefinition(identifier: .walkingDoubleSupportPercentage, name: "Walking Double Support", unit: .percent(), unitLabel: "%", multiplier: 100),
                    HealthMetricDefinition(identifier: .stairAscentSpeed, name: "Stair Ascent Speed", unit: .meter().unitDivided(by: .second()), unitLabel: "m/s"),
                    HealthMetricDefinition(identifier: .stairDescentSpeed, name: "Stair Descent Speed", unit: .meter().unitDivided(by: .second()), unitLabel: "m/s")
                ]
                if #available(iOS 15.0, *) {
                    definitions.append(HealthMetricDefinition(identifier: .appleWalkingSteadiness, name: "Walking Steadiness", unit: .percent(), unitLabel: "%", multiplier: 100))
                }
                return definitions
            }
            return []
        default:
            return []
        }
    }

    func getHealthRecords(
        for module: HealthExportModule,
        start: Date?,
        end: Date?,
        completionHandler: @escaping ([HealthExportRecord]) -> Void
    ) {
        switch module {
        case .body, .vitals, .nutrition, .mobility:
            getQuantityRecords(definitions: metricDefinitions(for: module), start: start, end: end, completionHandler: completionHandler)
        case .heartRate:
            getDailyHeartRateRecords(start: start, end: end, completionHandler: completionHandler)
        case .sleep:
            getCategoryRecords(identifier: .sleepAnalysis, start: start, end: end, completionHandler: completionHandler)
        case .mindfulness:
            getCategoryRecords(identifier: .mindfulSession, start: start, end: end, completionHandler: completionHandler)
        case .bloodPressure:
            getBloodPressureRecords(start: start, end: end, completionHandler: completionHandler)
        }
    }

    func getQuantityRecords(
        definitions: [HealthMetricDefinition],
        start: Date?,
        end: Date?,
        completionHandler: @escaping ([HealthExportRecord]) -> Void
    ) {
        guard !definitions.isEmpty else { completionHandler([]); return }
        let group = DispatchGroup()
        let lock = NSLock()
        var records: [HealthExportRecord] = []
        let predicate = start == nil ? nil : HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        definitions.forEach { definition in
            guard let sampleType = HKObjectType.quantityType(forIdentifier: definition.identifier) else { return }
            group.enter()
            let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let mapped = (samples as? [HKQuantitySample] ?? []).map { sample in
                    HealthExportRecord(
                        date: sample.startDate,
                        fields: [
                            sample.uuid.uuidString.lowercased(),
                            sample.startDate.toISO(),
                            sample.endDate.toISO(),
                            definition.name,
                            self.formatNumber(sample.quantity.doubleValue(for: definition.unit) * definition.multiplier),
                            definition.unitLabel,
                            sample.sourceRevision.source.name
                        ]
                    )
                }
                lock.lock()
                records.append(contentsOf: mapped)
                lock.unlock()
                group.leave()
            }
            healthStore?.execute(query)
        }
        group.notify(queue: .global(qos: .utility)) {
            completionHandler(self.sortedHealthRecords(records))
        }
    }

    func getDailyHeartRateRecords(
        start: Date?,
        end: Date?,
        completionHandler: @escaping ([HealthExportRecord]) -> Void
    ) {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: .heartRate) else { completionHandler([]); return }
        let calendar = Calendar.current
        let queryStart = start ?? calendar.date(from: DateComponents(year: 2014, month: 1, day: 1))!
        let queryEnd = end ?? today ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: queryEnd, options: [])
        let interval = DateComponents(day: 1)
        let anchor = calendar.startOfDay(for: queryStart)
        let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
        let query = HKStatisticsCollectionQuery(
            quantityType: quantityType,
            quantitySamplePredicate: predicate,
            options: [.discreteMin, .discreteMax, .discreteAverage],
            anchorDate: anchor,
            intervalComponents: interval
        )
        query.initialResultsHandler = { _, results, _ in
            var records: [HealthExportRecord] = []
            results?.enumerateStatistics(from: queryStart, to: queryEnd) { statistics, _ in
                guard
                    let minimum = statistics.minimumQuantity(),
                    let maximum = statistics.maximumQuantity(),
                    let average = statistics.averageQuantity()
                else { return }
                records.append(
                    HealthExportRecord(
                        date: statistics.startDate,
                        fields: [
                            statistics.startDate.toFormat("yyyy-MM-dd"),
                            self.formatNumber(minimum.doubleValue(for: unit)),
                            self.formatNumber(maximum.doubleValue(for: unit)),
                            self.formatNumber(average.doubleValue(for: unit)),
                            "count/min"
                        ]
                    )
                )
            }
            completionHandler(self.sortedHealthRecords(records))
        }
        healthStore?.execute(query)
    }

    func getCategoryRecords(
        identifier: HKCategoryTypeIdentifier,
        start: Date?,
        end: Date?,
        completionHandler: @escaping ([HealthExportRecord]) -> Void
    ) {
        guard let sampleType = HKObjectType.categoryType(forIdentifier: identifier) else { completionHandler([]); return }
        let predicate = start == nil ? nil : HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
            let records = (samples as? [HKCategorySample] ?? []).map { sample in
                let typeName = identifier == .sleepAnalysis ? self.sleepStageName(sample.value) : "Mindful Session"
                return HealthExportRecord(
                    date: sample.startDate,
                    fields: [
                        sample.uuid.uuidString.lowercased(),
                        sample.startDate.toISO(),
                        sample.endDate.toISO(),
                        typeName,
                        String(sample.value),
                        sample.sourceRevision.source.name
                    ]
                )
            }
            completionHandler(self.sortedHealthRecords(records))
        }
        healthStore?.execute(query)
    }

    func getBloodPressureRecords(
        start: Date?,
        end: Date?,
        completionHandler: @escaping ([HealthExportRecord]) -> Void
    ) {
        guard let sampleType = HKObjectType.correlationType(forIdentifier: .bloodPressure) else { completionHandler([]); return }
        let predicate = start == nil ? nil : HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
            let unit = HKUnit.millimeterOfMercury()
            let records = (samples as? [HKCorrelation] ?? []).map { sample in
                let quantities = sample.objects.compactMap { $0 as? HKQuantitySample }
                let systolic = quantities.first { $0.quantityType.identifier == HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue }
                let diastolic = quantities.first { $0.quantityType.identifier == HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue }
                return HealthExportRecord(
                    date: sample.startDate,
                    fields: [
                        sample.uuid.uuidString.lowercased(),
                        sample.startDate.toISO(),
                        sample.endDate.toISO(),
                        systolic.map { self.formatNumber($0.quantity.doubleValue(for: unit)) } ?? "",
                        diastolic.map { self.formatNumber($0.quantity.doubleValue(for: unit)) } ?? "",
                        "mmHg",
                        sample.sourceRevision.source.name
                    ]
                )
            }
            completionHandler(self.sortedHealthRecords(records))
        }
        healthStore?.execute(query)
    }

    func generateContentForHealthRecords(module: HealthExportModule, records: [Any]) -> String {
        let header: [String]
        switch module {
        case .body, .vitals, .nutrition, .mobility:
            header = ["UUID", "Start Date", "End Date", "Type", "Value", "Unit", "Source"]
        case .heartRate:
            header = ["Date", "Minimum", "Maximum", "Average", "Unit"]
        case .sleep, .mindfulness:
            header = ["UUID", "Start Date", "End Date", "Type", "Value", "Source"]
        case .bloodPressure:
            header = ["UUID", "Start Date", "End Date", "Systolic", "Diastolic", "Unit", "Source"]
        }
        let healthRecords = records.compactMap { $0 as? HealthExportRecord }
        let lines = [header] + healthRecords.map { $0.fields }
        return lines.map { row in row.map(self.escapeCSV).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    func sortedHealthRecords(_ records: [HealthExportRecord]) -> [HealthExportRecord] {
        return records.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.fields.joined(separator: "\u{1f}") < $1.fields.joined(separator: "\u{1f}")
        }
    }

    func sleepStageName(_ value: Int) -> String {
        if #available(iOS 16.0, *) {
            switch value {
            case HKCategoryValueSleepAnalysis.awake.rawValue: return "Awake"
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue: return "Core"
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: return "Deep"
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue: return "REM"
            case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: return "Asleep Unspecified"
            case HKCategoryValueSleepAnalysis.inBed.rawValue: return "In Bed"
            default: return "Unknown"
            }
        }
        switch value {
        case HKCategoryValueSleepAnalysis.inBed.rawValue: return "In Bed"
        case HKCategoryValueSleepAnalysis.asleep.rawValue: return "Asleep"
        case HKCategoryValueSleepAnalysis.awake.rawValue: return "Awake"
        default: return "Unknown"
        }
    }

    func formatNumber(_ value: Double) -> String {
        var formatted = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
        while formatted.contains(".") && formatted.last == "0" { formatted.removeLast() }
        if formatted.last == "." { formatted.removeLast() }
        return formatted
    }

    func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}

extension Health {
    func getBiologicalSex() -> HKBiologicalSexObject? {
        var biologicalSex: HKBiologicalSexObject?
        do {
            try biologicalSex = self.healthStore?.biologicalSex()
            return biologicalSex
        } catch {
            return nil
        }
    }

    func getHeartRateForWorkout(_ workout: HKWorkout, completionHandler: @escaping (HKQuantity?, HKQuantity?, HKQuantity?) -> Void) {
        let typeHeart = HKQuantityType.quantityType(forIdentifier: .heartRate)
        let predicate: NSPredicate? = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: [HKQueryOptions.strictStartDate, HKQueryOptions.strictEndDate])
        let squery = HKStatisticsQuery(quantityType: typeHeart!, quantitySamplePredicate: predicate, options: [.discreteAverage, .discreteMax, .discreteMin]) { (_, result, error) in
            if error == nil {
                let average: HKQuantity? = result?.averageQuantity()
                let maximum: HKQuantity? = result?.maximumQuantity()
                let minimum: HKQuantity? = result?.minimumQuantity()
                completionHandler(average, minimum, maximum)
            } else {
                completionHandler(nil, nil, nil)
            }
        }
        healthStore?.execute(squery)
    }

    func getSumQuantityForDate(_ quantity: HKQuantityType, date: Date, completionHandler: @escaping (HKQuantity?) -> Void) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: date)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: quantity, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            guard let result = result, let sum = result.sumQuantity() else {
                completionHandler(nil)
                return
            }

            completionHandler(sum)
        }

        healthStore?.execute(query)
    }

    func getSumQuantityForDates(_ quantity: HKQuantityType, start: Date, end: Date, completionHandler: @escaping ([String: HKQuantity]?) -> Void) {
        let calendar = NSCalendar.current
        let interval = NSDateComponents()
        interval.day = 1

        let anchorComponents = calendar.dateComponents([.day, .month, .year], from: NSDate() as Date)
        let anchorDate = calendar.date(from: anchorComponents)

        let query = HKStatisticsCollectionQuery(quantityType: quantity, quantitySamplePredicate: nil, options: .cumulativeSum, anchorDate: anchorDate!, intervalComponents: interval as DateComponents)
        query.initialResultsHandler = {_, results, _ in
            guard let results = results else {
                completionHandler(nil)
                return
            }

            var mapped: [String: HKQuantity] = [:]
            results.enumerateStatistics(from: start, to: end as Date) { statistics, _ in
                if let quantity = statistics.sumQuantity() {
                    let date = statistics.startDate
                    mapped[date.toFormat("yyyy-MM-dd")] = quantity
                }
            }

            completionHandler(mapped)
        }

        healthStore?.execute(query)
    }

    func getActivityData(completionHandler: @escaping ([HKActivitySummary]?) -> Void) {
        getActivityDataForDates(start: firstOfYear, end: today, completionHandler: completionHandler)
    }

    func getActivityDataForDates(start: Date?, end: Date?, completionHandler: @escaping ([HKActivitySummary]?) -> Void) {
        let calendar = Calendar.current
        var startComponents = calendar.dateComponents([ .day, .month, .year], from: start!)
        var endComponents = calendar.dateComponents([ .day, .month, .year], from: end!)

        // Calendar needs to be non-nil, but isn't auto-populated in dateComponents call
        startComponents.calendar = calendar
        endComponents.calendar = calendar

        var queryReturned = false
        let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: startComponents, end: endComponents)
        let activityQuery = HKActivitySummaryQuery(predicate: predicate) { (_, summaries, _) in
            queryReturned = true

            if let summaries = summaries, summaries.count > 0 {
                completionHandler(summaries)
            } else {
                completionHandler([])
            }
        }
        healthStore?.execute(activityQuery)

        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            if !queryReturned {
                self.healthStore?.stop(activityQuery)
                completionHandler([])
            }
        }
    }

    func generateContentForActivityData(summaries: [Any]?) -> String {
        let header = "Date,Move Actual,Move Goal,Exercise Actual,Exercise Goal,Stand Actual,Stand Goal\n"
        let content: NSMutableString = NSMutableString.init(string: header)
        let calendar = Calendar.current
        summaries?.forEach { summary in
            guard let summary = summary as? HKActivitySummary else { return }

            let date = Calendar.current.date(from: summary.dateComponents(for: calendar))
            guard date != nil else { return }

            var components: [String] = []
            components.append(date!.toFormat("yyyy-MM-dd"))
            components.append(quantityToString(summary.activeEnergyBurned, unit: HKUnit.kilocalorie()))
            components.append(quantityToString(summary.activeEnergyBurnedGoal, unit: HKUnit.kilocalorie()))
            components.append(quantityToString(summary.appleExerciseTime, unit: HKUnit.minute()))
            components.append(quantityToString(summary.appleExerciseTimeGoal, unit: HKUnit.minute()))
            components.append(quantityToString(summary.appleStandHours, unit: HKUnit.count(), int: true))
            components.append(quantityToString(summary.appleStandHoursGoal, unit: HKUnit.count(), int: true))

            content.append(components.joined(separator: ","))
            content.append("\n")
        }
        return String.init(content)
    }

    func getDistances(completionHandler: @escaping ([[String: Any]]?) -> Void) {
        distanceDataSource?.getAllDistances(start: firstOfYear!, end: today!) { distances in
            completionHandler(distances)
        }
    }

    func generateContentForDistances(distances: [Any]?) -> String {
        let header = "Date,Distance Walking/Running,Steps,Distance Swimming,Strokes,Distance Cycling,Distance Wheelchair,Distance Downhill Snowsports\n"
        let content: NSMutableString = NSMutableString.init(string: header)
        distances?.forEach { entry in
            guard let entry = entry as? [String: Any] else { return }

            var components: [String] = []
            components.append(entry["date"] as? String ?? "")
            components.append(quantityToString(entry["walkingDistance"] as? HKQuantity, unit: HKUnit.meter()))
            components.append(quantityToString(entry["steps"] as? HKQuantity, unit: HKUnit.count()))
            components.append(quantityToString(entry["swimmingDistance"] as? HKQuantity, unit: HKUnit.meter()))
            components.append(quantityToString(entry["strokes"] as? HKQuantity, unit: HKUnit.count()))
            components.append(quantityToString(entry["cyclingDistance"] as? HKQuantity, unit: HKUnit.meter()))
            components.append(quantityToString(entry["wheelchairDistance"] as? HKQuantity, unit: HKUnit.meter()))
            components.append(quantityToString(entry["downhillDistance"] as? HKQuantity, unit: HKUnit.meter()))

            content.append(components.joined(separator: ","))
            content.append("\n")
        }
        return String.init(content)
    }

    func getWorkouts(completionHandler: @escaping ([HKSample]?) -> Void) {
        getWorkoutsForDates(start: firstOfYear, end: lastOfYear, completionHandler: completionHandler)
    }

    func getWorkoutsForDates(start: Date?, end: Date?, completionHandler: @escaping ([HKSample]?) -> Void) {
        let predicate = (start != nil ? HKQuery.predicateForSamples(withStart: start, end: end, options: []) : nil)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let sampleQuery = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 0, sortDescriptors: [sortDescriptor]) { (_, workouts, _) in
            completionHandler(workouts)
        }
        healthStore?.execute(sampleQuery)
    }

    func generateContentForWorkouts(workouts: [Any]) -> String {
        let header = "UUID,Start Date,End Date,Type,Name,Duration,Distance,Elevation Ascended,Flights Climbed,Swim Strokes,Total Energy\n"
        let content: NSMutableString = NSMutableString.init(string: header)
        workouts.reversed().forEach { workout in
            guard let workout = workout as? HKWorkout else { return }

            var components: [String] = []
            components.append("\(workout.uuid.uuidString.lowercased())")
            components.append(workout.startDate.toISO())
            components.append(workout.endDate.toISO())
            components.append("\(workout.workoutActivityType.rawValue)")
            components.append(workout.workoutActivityType.name)
            components.append(String(format: "%.3f", workout.duration))
            components.append(quantityToString(workout.totalDistance, unit: HKUnit.meter()))

            if let elevation = workout.metadata?["HKElevationAscended"] as? HKQuantity {
                components.append(quantityToString(elevation, unit: HKUnit.meter()))
            } else {
                components.append("0")
            }

            components.append(quantityToString(workout.totalFlightsClimbed, unit: HKUnit.count(), int: true))
            components.append(quantityToString(workout.totalSwimmingStrokeCount, unit: HKUnit.count(), int: true))
            components.append(quantityToString(workout.totalEnergyBurned, unit: HKUnit.kilocalorie()))

            content.append(components.joined(separator: ","))
            content.append("\n")
        }
        return String.init(content)
    }

    func quantityToString(_ quantity: HKQuantity?, unit: HKUnit, int: Bool = false) -> String {
        return String(format: (int ? "%.0f" : "%.2f"), quantity?.doubleValue(for: unit) ?? 0)
    }

    func freshWorkoutsAvailable(workouts: [HKSample]) -> Bool {
        guard let workout = workouts.first as? HKWorkout else { return false }

        let lastWorkout = UserDefaults.standard.string(forKey: UserDefaultKeys.lastWorkout)
        return lastWorkout == nil || lastWorkout != workout.uuid.uuidString.lowercased()
    }

    func freshActivityAvailable() -> Bool {
        let lastDate = UserDefaults.standard.string(forKey: UserDefaultKeys.lastActivitySyncDate)
        return lastDate == nil || Health.shared().yesterday!.toFormat("yyyy-MM-dd") > lastDate!
    }

    func markLastWorkout(workouts: [HKSample]) {
        guard let workout = workouts.first as? HKWorkout else { return }

        UserDefaults.standard.set(workout.uuid.uuidString.lowercased(), forKey: UserDefaultKeys.lastWorkout)
        UserDefaults.standard.set(Date.init(), forKey: UserDefaultKeys.lastSyncDate)
    }

    func markLastDistance(distances: [[String: Any]]) {
        let lastDate = distances.last?["date"] as? String

        UserDefaults.standard.set(lastDate, forKey: UserDefaultKeys.lastActivitySyncDate)
        UserDefaults.standard.set(Date.init(), forKey: UserDefaultKeys.lastSyncDate)
    }

    func exportData(_ years: [String: [Any]], directory: String, contentHandler: @escaping ([Any]) -> String, completionHandler: @escaping () -> Void) {
        guard let year = years.first else { completionHandler(); return }
        guard !stopExport else { return }

        let content = contentHandler(year.value)
        let filename = "\(directory)/\(year.key).csv"
        GitHub.shared().updateFile(path: filename, content: content, message: "Initial export for \(year.key).") { _ in
            var next = years
            next.removeValue(forKey: year.key)
            self.exportData(next, directory: directory, contentHandler: contentHandler, completionHandler: completionHandler)
        }
    }
}
