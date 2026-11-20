import Foundation
import KeychainAccess

enum NotionExportScope: Int, CaseIterable {
    case oneYear
    case threeYears
    case all

    var title: String {
        switch self {
        case .oneYear: return "最近 1 年"
        case .threeYears: return "最近 3 年"
        case .all: return "全部历史"
        }
    }

    func startDate(relativeTo end: Date, fullRangeStart: Date) -> Date {
        guard self != .all else {
            return fullRangeStart
        }
        let years = self == .oneYear ? -1 : -3
        guard let date = Calendar.current.date(
            byAdding: .year,
            value: years,
            to: end
        ) else {
            return fullRangeStart
        }
        return max(fullRangeStart, date)
    }
}
enum NotionExportSettings {
    static let defaultTemplatePageID = "41e86019c92c81e8bf9dcbc142ba8003"
    static let defaultTemplateURL = "https://app.notion.com/p/Hadge-41e86019c92c81e8bf9dcbc142ba8003"
    static let templatePageKey = "notionExport.templatePageID"
    static let templateURLKey = "notionExport.templateURL"
    static let scopeKey = "notionExport.scope"
    static let lastSyncKey = "notionExport.lastSuccessfulSync"
    static let lastScopeKey = "notionExport.lastScope"

    private static let keychainService = "io.entire.hadge.notion-token"

    static var token: String? {
        get { Keychain(service: keychainService)["token"] }
        set {
            let keychain = Keychain(service: keychainService)
            keychain["token"] = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    static var templatePageID: String {
        get {
            UserDefaults.standard.string(forKey: templatePageKey)
                ?? defaultTemplatePageID
        }
        set {
            UserDefaults.standard.set(newValue, forKey: templatePageKey)
        }
    }

    static var templateURL: String {
        get {
            UserDefaults.standard.string(forKey: templateURLKey)
                ?? defaultTemplateURL
        }
        set {
            UserDefaults.standard.set(newValue, forKey: templateURLKey)
        }
    }

    static var scope: NotionExportScope {
        get {
            guard UserDefaults.standard.object(forKey: scopeKey) != nil else {
                return .all
            }
            let raw = UserDefaults.standard.integer(forKey: scopeKey)
            return NotionExportScope(rawValue: raw) ?? .all
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: scopeKey)
        }
    }

    static var lastSuccessfulSync: Date? {
        get { UserDefaults.standard.object(forKey: lastSyncKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastSyncKey) }
    }

    static var lastScope: NotionExportScope? {
        get {
            guard UserDefaults.standard.object(forKey: lastScopeKey) != nil else {
                return nil
            }
            return NotionExportScope(
                rawValue: UserDefaults.standard.integer(forKey: lastScopeKey)
            )
        }
        set {
            UserDefaults.standard.set(newValue?.rawValue, forKey: lastScopeKey)
        }
    }

    static func clear() {
        token = nil
        lastSuccessfulSync = nil
        lastScope = nil
    }
}

struct NotionTemplateDatabases {
    let dailyDatabaseID: String
    let workoutDatabaseID: String
}

struct NotionSyncResult {
    let dailyCreated: Int
    let dailyUpdated: Int
    let workoutsCreated: Int
    let workoutsUpdated: Int

    var total: Int {
        dailyCreated + dailyUpdated + workoutsCreated + workoutsUpdated
    }
}

enum NotionExportError: LocalizedError {
    case missingToken
    case invalidTemplateURL
    case missingTemplateDatabase(String)
    case invalidResponse
    case http(status: Int, message: String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "请填写 Notion 集成 Token。"
        case .invalidTemplateURL:
            return "无法识别 Notion 模板页面链接或页面 ID。"
        case .missingTemplateDatabase(let name):
            return "模板页面中找不到“\(name)”数据库。请确认页面已分享给 Notion 集成。"
        case .invalidResponse:
            return "Notion 返回了无法识别的数据。"
        case .http(let status, let message):
            return "Notion API 请求失败（\(status)）：\(message)"
        case .transport(let message):
            return "无法连接 Notion：\(message)"
        }
    }
}

final class NotionExportClient {
    private let token: String
    private let session: URLSession
    private let baseURL = URL(string: "https://api.notion.com/v1")!

    init(token: String) {
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 90
        self.session = URLSession(configuration: configuration)
    }

    func resolveTemplate(
        pageID: String,
        completion: @escaping (Result<NotionTemplateDatabases, Error>) -> Void
    ) {
        fetchChildBlocks(
            blockID: pageID,
            cursor: nil,
            accumulator: []
        ) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let blocks):
                let databases = blocks.compactMap { block -> (String, String)? in
                    guard let type = block["type"] as? String,
                          type == "child_database",
                          let database = block[type] as? [String: Any],
                          let title = database["title"] as? String,
                          let id = block["id"] as? String else {
                        return nil
                    }
                    return (title, id)
                }
                guard let daily = databases.first(where: {
                    $0.0.contains("每日健康")
                })?.1 else {
                    completion(.failure(
                        NotionExportError.missingTemplateDatabase("每日健康")
                    ))
                    return
                }
                guard let workout = databases.first(where: {
                    $0.0.contains("运动记录")
                })?.1 else {
                    completion(.failure(
                        NotionExportError.missingTemplateDatabase("运动记录")
                    ))
                    return
                }
                completion(.success(NotionTemplateDatabases(
                    dailyDatabaseID: daily,
                    workoutDatabaseID: workout
                )))
            }
        }
    }

    func existingPages(
        databaseID: String,
        dateProperty: String,
        since: Date,
        completion: @escaping (Result<[String: String], Error>) -> Void
    ) {
        let body: [String: Any] = [
            "page_size": 100,
            "filter": [
                "property": dateProperty,
                "date": [
                    "on_or_after": HealthExportFormatter.isoDay(since)
                ]
            ]
        ]
        queryDatabasePages(
            databaseID: databaseID,
            body: body,
            cursor: nil,
            accumulator: [:],
            completion: completion
        )
    }

    func createPage(
        databaseID: String,
        properties: [String: Any],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let body: [String: Any] = [
            "parent": [
                "type": "database_id",
                "database_id": databaseID
            ],
            "properties": properties
        ]
        request(
            path: "/pages",
            method: "POST",
            body: body
        ) { result in
            completion(result.map { _ in () })
        }
    }

    func updatePage(
        pageID: String,
        properties: [String: Any],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        request(
            path: "/pages/\(pageID)",
            method: "PATCH",
            body: ["properties": properties]
        ) { result in
            completion(result.map { _ in () })
        }
    }

    static func normalizePageID(from value: String) -> String? {
        let compact = value.replacingOccurrences(of: "-", with: "")
        guard let regex = try? NSRegularExpression(
            pattern: "[0-9a-fA-F]{32}"
        ) else {
            return nil
        }
        let range = NSRange(compact.startIndex..<compact.endIndex, in: compact)
        guard let match = regex.firstMatch(
            in: compact,
            range: range
        ), let matchRange = Range(match.range, in: compact) else {
            return nil
        }
        let raw = String(compact[matchRange]).lowercased()
        return [
            String(raw.prefix(8)),
            String(raw.dropFirst(8).prefix(4)),
            String(raw.dropFirst(12).prefix(4)),
            String(raw.dropFirst(16).prefix(4)),
            String(raw.dropFirst(20).prefix(12))
        ].joined(separator: "-")
    }

    private func fetchChildBlocks(
        blockID: String,
        cursor: String?,
        accumulator: [[String: Any]],
        completion: @escaping (Result<[[String: Any]], Error>) -> Void
    ) {
        var query = "page_size=100"
        if let cursor = cursor {
            query += "&start_cursor=\(cursor)"
        }
        request(
            path: "/blocks/\(blockID)/children?\(query)",
            method: "GET",
            body: nil
        ) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let json):
                let blocks = json["results"] as? [[String: Any]] ?? []
                let next = json["has_more"] as? Bool == true
                    ? json["next_cursor"] as? String
                    : nil
                if let next = next {
                    self.fetchChildBlocks(
                        blockID: blockID,
                        cursor: next,
                        accumulator: accumulator + blocks,
                        completion: completion
                    )
                } else {
                    completion(.success(accumulator + blocks))
                }
            }
        }
    }

    private func queryDatabasePages(
        databaseID: String,
        body: [String: Any],
        cursor: String?,
        accumulator: [String: String],
        completion: @escaping (Result<[String: String], Error>) -> Void
    ) {
        var requestBody = body
        if let cursor = cursor {
            requestBody["start_cursor"] = cursor
        }
        request(
            path: "/databases/\(databaseID)/query",
            method: "POST",
            body: requestBody
        ) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let json):
                let pages = json["results"] as? [[String: Any]] ?? []
                var next = accumulator
                pages.forEach { page in
                    guard
                        let id = page["id"] as? String,
                        let properties = page["properties"] as? [String: Any],
                        let syncID = self.syncID(from: properties),
                        !syncID.isEmpty
                    else {
                        return
                    }
                    next[syncID] = id
                }
                if json["has_more"] as? Bool == true,
                   let nextCursor = json["next_cursor"] as? String {
                    self.queryDatabasePages(
                        databaseID: databaseID,
                        body: body,
                        cursor: nextCursor,
                        accumulator: next,
                        completion: completion
                    )
                } else {
                    completion(.success(next))
                }
            }
        }
    }

    private func syncID(from properties: [String: Any]) -> String? {
        guard
            let property = properties["同步 ID"] as? [String: Any],
            let richText = property["rich_text"] as? [[String: Any]]
        else {
            return nil
        }
        return richText.compactMap { $0["plain_text"] as? String }.joined()
    }

    private func request(
        path: String,
        method: String,
        body: [String: Any]?,
        retryCount: Int = 0,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            completion(.failure(NotionExportError.invalidResponse))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Hadge/1.1", forHTTPHeaderField: "User-Agent")
        if let body = body {
            do {
                request.httpBody = try JSONSerialization.data(
                    withJSONObject: body,
                    options: []
                )
            } catch {
                completion(.failure(error))
                return
            }
        }

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(
                    NotionExportError.transport(error.localizedDescription)
                ))
                return
            }
            guard
                let httpResponse = response as? HTTPURLResponse,
                let data = data
            else {
                completion(.failure(NotionExportError.invalidResponse))
                return
            }
            let json = (try? JSONSerialization.jsonObject(with: data))
                as? [String: Any]
            if (200..<300).contains(httpResponse.statusCode),
               let json = json {
                completion(.success(json))
                return
            }

            let message = (json?["message"] as? String)
                ?? HTTPURLResponse.localizedString(
                    forStatusCode: httpResponse.statusCode
                )
            let shouldRetry = (
                httpResponse.statusCode == 429
                    || httpResponse.statusCode >= 500
            ) && retryCount < 2
            if shouldRetry {
                let retryAfter = httpResponse.value(
                    forHTTPHeaderField: "Retry-After"
                ).flatMap(TimeInterval.init) ?? Double(retryCount + 1)
                DispatchQueue.global().asyncAfter(
                    deadline: .now() + min(max(retryAfter, 0.5), 5)
                ) {
                    self.request(
                        path: path,
                        method: method,
                        body: body,
                        retryCount: retryCount + 1,
                        completion: completion
                    )
                }
                return
            }
            completion(.failure(
                NotionExportError.http(
                    status: httpResponse.statusCode,
                    message: message
                )
            ))
        }.resume()
    }
}

final class NotionHealthExporter {
    private let client: NotionExportClient
    private let pageID: String

    init(token: String, pageID: String) {
        self.client = NotionExportClient(token: token)
        self.pageID = pageID
    }

    func sync(
        snapshot: HealthExportSnapshot,
        scope: NotionExportScope,
        progress: @escaping (String) -> Void,
        completion: @escaping (Result<NotionSyncResult, Error>) -> Void
    ) {
        progress("连接 Notion 模板")
        client.resolveTemplate(pageID: pageID) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let databases):
                self.syncDatabases(
                    databases,
                    snapshot: snapshot,
                    scope: scope,
                    progress: progress,
                    completion: completion
                )
            }
        }
    }

    private func syncDatabases(
        _ databases: NotionTemplateDatabases,
        snapshot: HealthExportSnapshot,
        scope: NotionExportScope,
        progress: @escaping (String) -> Void,
        completion: @escaping (Result<NotionSyncResult, Error>) -> Void
    ) {
        let previousScope = NotionExportSettings.lastScope
        let incremental = NotionExportSettings.lastSuccessfulSync != nil
            && previousScope == scope
        let since: Date
        if incremental, let lastSync = NotionExportSettings.lastSuccessfulSync {
            since = max(
                snapshot.range.start,
                Calendar.current.date(byAdding: .day, value: -7, to: lastSync)
                    ?? snapshot.range.start
            )
        } else {
            since = scope.startDate(
                relativeTo: snapshot.range.end,
                fullRangeStart: snapshot.range.start
            )
        }

        let daily = snapshot.daily.filter { $0.date >= since }
        let workouts = snapshot.workouts.filter { $0.startDate >= since }
        let group = DispatchGroup()
        let lock = NSLock()
        var existingDaily: [String: String] = [:]
        var existingWorkouts: [String: String] = [:]
        var loadError: Error?

        progress("读取 Notion 已有记录")
        group.enter()
        client.existingPages(
            databaseID: databases.dailyDatabaseID,
            dateProperty: "日期",
            since: since
        ) { result in
            lock.lock()
            switch result {
            case .success(let pages):
                existingDaily = pages
            case .failure(let error):
                loadError = error
            }
            lock.unlock()
            group.leave()
        }

        group.enter()
        client.existingPages(
            databaseID: databases.workoutDatabaseID,
            dateProperty: "开始时间",
            since: since
        ) { result in
            lock.lock()
            switch result {
            case .success(let pages):
                existingWorkouts = pages
            case .failure(let error):
                loadError = error
            }
            lock.unlock()
            group.leave()
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            if let error = loadError {
                completion(.failure(error))
                return
            }

            let writes = daily.map { SyncWrite.daily($0) }
                + workouts.map { SyncWrite.workout($0) }
            let total = writes.count
            if total == 0 {
                NotionExportSettings.lastSuccessfulSync = Date()
                NotionExportSettings.lastScope = scope
                completion(.success(NotionSyncResult(
                    dailyCreated: 0,
                    dailyUpdated: 0,
                    workoutsCreated: 0,
                    workoutsUpdated: 0
                )))
                return
            }

            self.write(
                writes,
                index: 0,
                databaseIDs: databases,
                existingDaily: existingDaily,
                existingWorkouts: existingWorkouts,
                progress: progress,
                completion: completion
            )
        }
    }

    private func write(
        _ writes: [SyncWrite],
        index: Int,
        databaseIDs: NotionTemplateDatabases,
        existingDaily: [String: String],
        existingWorkouts: [String: String],
        progress: @escaping (String) -> Void,
        completion: @escaping (Result<NotionSyncResult, Error>) -> Void
    ) {
        guard index < writes.count else {
            NotionExportSettings.lastSuccessfulSync = Date()
            completion(.success(.init(
                dailyCreated: dailyCreated,
                dailyUpdated: dailyUpdated,
                workoutsCreated: workoutsCreated,
                workoutsUpdated: workoutsUpdated
            )))
            return
        }

        let write = writes[index]
        let writeCompletion: (Result<Void, Error>) -> Void = { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success:
                self.updateCounts(for: write, isUpdate: write.pageID(
                    existingDaily: existingDaily,
                    existingWorkouts: existingWorkouts
                ) != nil)
                progress("同步 Notion \(index + 1)/\(writes.count)")
                DispatchQueue.global().asyncAfter(
                    deadline: .now() + 0.36
                ) {
                    self.write(
                        writes,
                        index: index + 1,
                        databaseIDs: databaseIDs,
                        existingDaily: existingDaily,
                        existingWorkouts: existingWorkouts,
                        progress: progress,
                        completion: completion
                    )
                }
            }
        }

        switch write {
        case .daily(let record):
            let properties = NotionPropertyBuilder.dailyProperties(
                record,
                syncedAt: Date()
            )
            if let pageID = existingDaily[record.syncID] {
                client.updatePage(
                    pageID: pageID,
                    properties: properties,
                    completion: writeCompletion
                )
            } else {
                client.createPage(
                    databaseID: databaseIDs.dailyDatabaseID,
                    properties: properties,
                    completion: writeCompletion
                )
            }
        case .workout(let record):
            let properties = NotionPropertyBuilder.workoutProperties(
                record,
                syncedAt: Date()
            )
            if let pageID = existingWorkouts[record.syncID] {
                client.updatePage(
                    pageID: pageID,
                    properties: properties,
                    completion: writeCompletion
                )
            } else {
                client.createPage(
                    databaseID: databaseIDs.workoutDatabaseID,
                    properties: properties,
                    completion: writeCompletion
                )
            }
        }
    }

    private var dailyCreated = 0
    private var dailyUpdated = 0
    private var workoutsCreated = 0
    private var workoutsUpdated = 0

    private func updateCounts(for write: SyncWrite, isUpdate: Bool) {
        switch write {
        case .daily:
            if isUpdate {
                dailyUpdated += 1
            } else {
                dailyCreated += 1
            }
        case .workout:
            if isUpdate {
                workoutsUpdated += 1
            } else {
                workoutsCreated += 1
            }
        }
    }
}

private enum SyncWrite {
    case daily(DailyHealthRecord)
    case workout(WorkoutHealthRecord)

    func pageID(
        existingDaily: [String: String],
        existingWorkouts: [String: String]
    ) -> String? {
        switch self {
        case .daily(let record):
            return existingDaily[record.syncID]
        case .workout(let record):
            return existingWorkouts[record.syncID]
        }
    }
}
