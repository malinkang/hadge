import Foundation

@main
struct ExportSerializationTests {
    static func main() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let daily = DailyHealthRecord(
            syncID: "daily-2027-01-15",
            date: date,
            steps: 12345,
            waterMilliliters: 2100,
            sleepMinutes: 462.5,
            activeEnergyKilocalories: 620,
            exerciseMinutes: 55,
            standHours: 12,
            activeEnergyGoal: 500,
            exerciseGoal: 30,
            standGoal: 10
        )
        let workout = WorkoutHealthRecord(
            syncID: "workout-test",
            name: "跑步, 含\"测试\"",
            startDate: date,
            endDate: date.addingTimeInterval(3600),
            activityType: "Running",
            activityCategory: "跑步",
            durationMinutes: 60,
            distanceKilometers: 10.25,
            activeEnergyKilocalories: 500,
            minimumHeartRate: 120,
            averageHeartRate: 150,
            maximumHeartRate: 180,
            routePointCount: 2048,
            includesRoute: true
        )
        let snapshot = HealthExportSnapshot(
            schemaVersion: 1,
            exportedAt: date,
            range: HealthExportDateRange(
                start: date.addingTimeInterval(-86400),
                end: date
            ),
            daily: [daily],
            workouts: [workout],
            rawRecords: [
                RawHealthExportRecord(
                    module: "heart-rate",
                    date: date,
                    fields: ["sample-id", "72", "count/min"]
                )
            ]
        )

        let json = try HealthExportCodec.encodeJSON(snapshot)
        let jsonObject = try JSONSerialization.jsonObject(with: json)
        let jsonDictionary = jsonObject as? [String: Any]
        expect(jsonDictionary?["schemaVersion"] as? Int == 1)
        expect((jsonDictionary?["daily"] as? [[String: Any]])?.count == 1)
        expect((jsonDictionary?["workouts"] as? [[String: Any]])?.count == 1)

        let dailyCSV = HealthExportCodec.dailyCSV([daily])
        expect(dailyCSV.hasPrefix("\u{feff}同步 ID,日期,步数"))
        expect(dailyCSV.contains("12345"))
        expect(dailyCSV.contains("462.5"))

        let workoutCSV = HealthExportCodec.workoutsCSV([workout])
        expect(workoutCSV.contains("\"跑步, 含\"\"测试\"\"\""))
        expect(workoutCSV.contains(",是\r\n"))

        let dailyProperties = NotionPropertyBuilder.dailyProperties(
            daily,
            syncedAt: date
        )
        let workoutProperties = NotionPropertyBuilder.workoutProperties(
            workout,
            syncedAt: date
        )
        expect(JSONSerialization.isValidJSONObject(dailyProperties))
        expect(JSONSerialization.isValidJSONObject(workoutProperties))
        let steps = (dailyProperties["步数"] as? [String: Any])?["number"] as? Double
        expect(steps == 12345)
        let category = (
            workoutProperties["运动类型"] as? [String: Any]
        )?["select"] as? [String: String]
        expect(category?["name"] == "跑步")

        let emptyDaily = DailyHealthRecord(
            syncID: "daily-empty",
            date: date,
            steps: nil,
            waterMilliliters: nil,
            sleepMinutes: nil,
            activeEnergyKilocalories: nil,
            exerciseMinutes: nil,
            standHours: nil,
            activeEnergyGoal: nil,
            exerciseGoal: nil,
            standGoal: nil
        )
        let emptyProperties = NotionPropertyBuilder.dailyProperties(
            emptyDaily,
            syncedAt: date
        )
        let emptySteps = (
            emptyProperties["步数"] as? [String: Any]
        )?["number"]
        expect(emptySteps is NSNull)

        print("ExportSerializationTests passed")
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard condition() else {
            fatalError("Assertion failed at \(file):\(line)")
        }
    }
}
