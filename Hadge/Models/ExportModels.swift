import Foundation

struct HealthExportDateRange: Codable, Equatable {
    let start: Date
    let end: Date
}

struct DailyHealthRecord: Codable, Equatable {
    let syncID: String
    let date: Date
    let steps: Double?
    let waterMilliliters: Double?
    let sleepMinutes: Double?
    let activeEnergyKilocalories: Double?
    let exerciseMinutes: Double?
    let standHours: Double?
    let activeEnergyGoal: Double?
    let exerciseGoal: Double?
    let standGoal: Double?
}

struct WorkoutHealthRecord: Codable, Equatable {
    let syncID: String
    let name: String
    let startDate: Date
    let endDate: Date
    let activityType: String
    let activityCategory: String
    let durationMinutes: Double
    let distanceKilometers: Double?
    let activeEnergyKilocalories: Double?
    let minimumHeartRate: Double?
    let averageHeartRate: Double?
    let maximumHeartRate: Double?
    let routePointCount: Int
    let includesRoute: Bool
}

struct RawHealthExportRecord: Codable, Equatable {
    let module: String
    let date: Date
    let fields: [String]
}

struct HealthExportSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let exportedAt: Date
    let range: HealthExportDateRange
    let daily: [DailyHealthRecord]
    let workouts: [WorkoutHealthRecord]
    let rawRecords: [RawHealthExportRecord]

    static let empty = HealthExportSnapshot(
        schemaVersion: 1,
        exportedAt: Date(),
        range: HealthExportDateRange(start: Date(), end: Date()),
        daily: [],
        workouts: [],
        rawRecords: []
    )
}

enum HealthExportSerializationError: LocalizedError {
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            return "无法将导出内容编码为 UTF-8。"
        }
    }
}

enum HealthExportCodec {
    static func encodeJSON(_ snapshot: HealthExportSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(snapshot)
    }

    static func dailyCSV(_ records: [DailyHealthRecord]) -> String {
        HealthCSVWriter.make(
            header: [
                "同步 ID",
                "日期",
                "步数",
                "饮水（毫升）",
                "睡眠（分钟）",
                "活动能量（千卡）",
                "锻炼（分钟）",
                "站立（小时）",
                "活动能量目标",
                "锻炼目标",
                "站立目标"
            ],
            rows: records.map { record in
                [
                    record.syncID,
                    HealthExportFormatter.isoDay(record.date),
                    HealthExportFormatter.number(record.steps),
                    HealthExportFormatter.number(record.waterMilliliters),
                    HealthExportFormatter.number(record.sleepMinutes),
                    HealthExportFormatter.number(record.activeEnergyKilocalories),
                    HealthExportFormatter.number(record.exerciseMinutes),
                    HealthExportFormatter.number(record.standHours),
                    HealthExportFormatter.number(record.activeEnergyGoal),
                    HealthExportFormatter.number(record.exerciseGoal),
                    HealthExportFormatter.number(record.standGoal)
                ]
            }
        )
    }

    static func workoutsCSV(_ records: [WorkoutHealthRecord]) -> String {
        HealthCSVWriter.make(
            header: [
                "同步 ID",
                "名称",
                "开始时间",
                "结束时间",
                "运动类型",
                "类型分类",
                "时长（分钟）",
                "距离（公里）",
                "活动能量（千卡）",
                "最小心率",
                "平均心率",
                "最大心率",
                "轨迹点数",
                "包含轨迹"
            ],
            rows: records.map { record in
                [
                    record.syncID,
                    record.name,
                    HealthExportFormatter.isoDateTime(record.startDate),
                    HealthExportFormatter.isoDateTime(record.endDate),
                    record.activityType,
                    record.activityCategory,
                    HealthExportFormatter.number(record.durationMinutes),
                    HealthExportFormatter.number(record.distanceKilometers),
                    HealthExportFormatter.number(record.activeEnergyKilocalories),
                    HealthExportFormatter.number(record.minimumHeartRate),
                    HealthExportFormatter.number(record.averageHeartRate),
                    HealthExportFormatter.number(record.maximumHeartRate),
                    "\(record.routePointCount)",
                    record.includesRoute ? "是" : "否"
                ]
            }
        )
    }

    static func rawRecordsCSV(_ records: [RawHealthExportRecord]) -> String {
        HealthCSVWriter.make(
            header: ["模块", "日期", "字段"],
            rows: records.map { record in
                [
                    record.module,
                    HealthExportFormatter.isoDateTime(record.date),
                    record.fields.joined(separator: " | ")
                ]
            }
        )
    }
}

enum HealthExportFormatter {
    static let isoDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let isoDateTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func isoDay(_ date: Date) -> String {
        isoDayFormatter.string(from: date)
    }

    static func isoDateTime(_ date: Date) -> String {
        isoDateTimeFormatter.string(from: date)
    }

    static func number(_ value: Double?) -> String {
        guard let value = value, value.isFinite else { return "" }
        var formatted = String(
            format: "%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
        while formatted.contains(".") && formatted.last == "0" {
            formatted.removeLast()
        }
        if formatted.last == "." {
            formatted.removeLast()
        }
        return formatted
    }
}

enum HealthCSVWriter {
    static func make(header: [String], rows: [[String]]) -> String {
        let lines = [header] + rows
        return "\u{feff}" + lines
            .map { row in row.map(escape).joined(separator: ",") }
            .joined(separator: "\r\n") + "\r\n"
    }

    static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}

enum NotionPropertyBuilder {
    static func dailyProperties(
        _ record: DailyHealthRecord,
        syncedAt: Date
    ) -> [String: Any] {
        var properties: [String: Any] = [
            "名称": title("\(HealthExportFormatter.isoDay(record.date)) 健康"),
            "同步 ID": richText(record.syncID),
            "日期": date(record.date),
            "来源": select("Apple 健康"),
            "最近同步": date(syncedAt)
        ]
        setNumber("步数", value: record.steps, in: &properties)
        setNumber("饮水（毫升）", value: record.waterMilliliters, in: &properties)
        setNumber("睡眠（分钟）", value: record.sleepMinutes, in: &properties)
        setNumber("活动能量（千卡）", value: record.activeEnergyKilocalories, in: &properties)
        setNumber("锻炼（分钟）", value: record.exerciseMinutes, in: &properties)
        setNumber("站立（小时）", value: record.standHours, in: &properties)
        setNumber("活动能量目标", value: record.activeEnergyGoal, in: &properties)
        setNumber("锻炼目标", value: record.exerciseGoal, in: &properties)
        setNumber("站立目标", value: record.standGoal, in: &properties)
        return properties
    }

    static func workoutProperties(
        _ record: WorkoutHealthRecord,
        syncedAt: Date
    ) -> [String: Any] {
        var properties: [String: Any] = [
            "名称": title(record.name),
            "同步 ID": richText(record.syncID),
            "开始时间": date(record.startDate),
            "结束时间": date(record.endDate),
            "运动类型": select(record.activityCategory),
            "时长（分钟）": number(record.durationMinutes),
            "轨迹点数": number(Double(record.routePointCount)),
            "包含轨迹": checkbox(record.includesRoute),
            "来源": select("Apple 健康"),
            "最近同步": date(syncedAt)
        ]
        setNumber("距离（公里）", value: record.distanceKilometers, in: &properties)
        setNumber("活动能量（千卡）", value: record.activeEnergyKilocalories, in: &properties)
        setNumber("最小心率", value: record.minimumHeartRate, in: &properties)
        setNumber("平均心率", value: record.averageHeartRate, in: &properties)
        setNumber("最大心率", value: record.maximumHeartRate, in: &properties)
        return properties
    }

    static func title(_ value: String) -> [String: Any] {
        [
            "type": "title",
            "title": [[
                "type": "text",
                "text": ["content": value]
            ]]
        ]
    }

    static func richText(_ value: String) -> [String: Any] {
        [
            "type": "rich_text",
            "rich_text": [[
                "type": "text",
                "text": ["content": value]
            ]]
        ]
    }

    static func date(_ value: Date) -> [String: Any] {
        [
            "type": "date",
            "date": ["start": HealthExportFormatter.isoDateTime(value)]
        ]
    }

    static func select(_ value: String) -> [String: Any] {
        [
            "type": "select",
            "select": ["name": value]
        ]
    }

    static func number(_ value: Double) -> [String: Any] {
        [
            "type": "number",
            "number": value
        ]
    }

    static func checkbox(_ value: Bool) -> [String: Any] {
        [
            "type": "checkbox",
            "checkbox": value
        ]
    }

    private static func setNumber(
        _ key: String,
        value: Double?,
        in properties: inout [String: Any]
    ) {
        guard let value = value, value.isFinite else {
            properties[key] = [
                "type": "number",
                "number": NSNull()
            ]
            return
        }
        properties[key] = number(value)
    }
}

enum HealthExportFileFormat {
    case json
    case csv

    var fileExtension: String {
        switch self {
        case .json: return "json"
        case .csv: return "csv"
        }
    }

    var displayName: String {
        switch self {
        case .json: return "JSON"
        case .csv: return "CSV"
        }
    }
}

enum HealthExportFileService {
    static func write(
        snapshot: HealthExportSnapshot,
        format: HealthExportFileFormat
    ) throws -> [URL] {
        let manager = FileManager.default
        let documents = try manager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let stamp = exportStamp(snapshot.exportedAt)
        let directory = documents
            .appendingPathComponent("Hadge Exports", isDirectory: true)
            .appendingPathComponent(stamp, isDirectory: true)
        try manager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        switch format {
        case .json:
            let url = directory.appendingPathComponent("hadge-health-\(stamp).json")
            try HealthExportCodec.encodeJSON(snapshot).write(
                to: url,
                options: .atomic
            )
            return [url]
        case .csv:
            let dailyURL = directory.appendingPathComponent("daily-health-\(stamp).csv")
            let workoutsURL = directory.appendingPathComponent("workouts-\(stamp).csv")
            let rawURL = directory.appendingPathComponent("health-records-\(stamp).csv")
            try writeUTF8(
                HealthExportCodec.dailyCSV(snapshot.daily),
                to: dailyURL
            )
            try writeUTF8(
                HealthExportCodec.workoutsCSV(snapshot.workouts),
                to: workoutsURL
            )
            try writeUTF8(
                HealthExportCodec.rawRecordsCSV(snapshot.rawRecords),
                to: rawURL
            )
            return [dailyURL, workoutsURL, rawURL]
        }
    }

    private static func writeUTF8(_ content: String, to url: URL) throws {
        guard let data = content.data(using: .utf8) else {
            throw HealthExportSerializationError.invalidUTF8
        }
        try data.write(to: url, options: .atomic)
    }

    private static func exportStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
