// MARK: - Imports
import Foundation
import Combine
import OSLog

// MARK: - Usage ViewModel
@MainActor
final class UsageViewModel: ObservableObject {
    // MARK: Published Properties
    @Published private(set) var usage: UsageData?
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?
    @Published private(set) var currentSession: Session?
    @Published private(set) var recentSessions: [Session] = []
    @Published private(set) var hourlyChartData: [ChartDataPoint] = []
    @Published private(set) var dailyChartData: [ChartDataPoint] = []

    // CLI Integration
    @Published private(set) var isClaudeCodeInstalled = false
    @Published private(set) var cliUsageData: CLIUsageData?

    // JSONL Log Integration
    @Published private(set) var jsonlUsage: AggregatedUsage?
    @Published private(set) var jsonlWeeklyUsage: AggregatedUsage?
    @Published private(set) var debugInfo: String = "Not loaded"

    // CLI /usage Integration (Expect script)
    @Published private(set) var cliUsageResult: CLIUsageResult?
    @Published private(set) var isCLIUsageAvailable = false

    // Active Process Monitoring
    @Published private(set) var activeProcesses: [ActiveClaudeProcess] = []
    @Published private(set) var processSnapshot: ProcessSnapshot?

    // MARK: Computed Properties (CLI /usage 전용)

    /// CLI 결과가 없으면 사용 중이지 않은 것으로 판단
    var isNotInUse: Bool {
        return cliUsageResult == nil
    }

    /// 현재 세션 잔여 퍼센트 (CLI /usage 전용)
    var currentPercentage: Double {
        guard let cliResult = cliUsageResult else { return 100 }
        return Double(cliResult.sessionRemainingPercent)
    }

    /// 현재 세션 사용 퍼센트 (CLI /usage 전용)
    var sessionUsedPercentage: Double {
        guard let cliResult = cliUsageResult else { return 0 }
        return Double(cliResult.sessionUsedPercent)
    }

    /// 주간 잔여 퍼센트 (CLI /usage 전용)
    var weeklyPercentage: Double {
        guard let cliResult = cliUsageResult else { return 100 }
        return Double(cliResult.weeklyRemainingPercent)
    }

    /// 주간 사용 퍼센트 (CLI /usage 전용)
    var weeklyUsedPercentage: Double {
        guard let cliResult = cliUsageResult else { return 0 }
        return Double(cliResult.weeklyUsedPercent)
    }

    /// 세션 리셋 시간 문자열 (CLI /usage 전용)
    var sessionResetTimeString: String? {
        cliUsageResult?.sessionResetTime
    }

    /// 주간 리셋 시간 문자열 (CLI /usage 전용)
    var weeklyResetTimeString: String? {
        cliUsageResult?.weeklyResetTime
    }

    /// 메뉴바/설정에 표시할 리셋 시간
    var currentResetTime: String? {
        guard let cliResult = cliUsageResult else { return nil }
        switch settingsStore.displayMode {
        case .session:
            return formatResetTimeOnly(cliResult.sessionResetTime)  // 세션은 시간만
        case .weekly:
            return formatResetTimeWithDate(cliResult.weeklyResetTime)  // 주간은 날짜 포함
        case .all:
            return formatResetTimeOnly(cliResult.sessionResetTime)
        }
    }
    
    /// 세션 리셋 시간 (시간만 표시)
    var sessionResetTimeFormatted: String? {
        guard let cliResult = cliUsageResult else { return nil }
        return formatResetTimeOnly(cliResult.sessionResetTime)
    }
    
    /// 주간 리셋 시간 (날짜 포함)
    var weeklyResetTimeFormatted: String? {
        guard let cliResult = cliUsageResult else { return nil }
        return formatResetTimeWithDate(cliResult.weeklyResetTime)
    }

    /// 남은 시간 문자열 (세션/주간에 따라)
    var remainingTimeString: String? {
        switch settingsStore.displayMode {
        case .session:
            return sessionRemainingTimeString
        case .weekly:
            return weeklyRemainingTimeString
        case .all:
            return sessionRemainingTimeString
        }
    }
    
    /// 세션 남은 시간 문자열
    var sessionRemainingTimeString: String? {
        guard let cliResult = cliUsageResult,
              let timeStr = cliResult.sessionResetTime else { return nil }
        return calculateRemainingTime(from: timeStr, includeDay: false)
    }
    
    /// 주간 남은 시간 문자열 (일, 시, 분 표기)
    var weeklyRemainingTimeString: String? {
        guard let cliResult = cliUsageResult,
              let timeStr = cliResult.weeklyResetTime else { return nil }
        return calculateRemainingTime(from: timeStr, includeDay: true)
    }
    
    /// 리셋 시간을 시간만 표시 (24시간제 hh:mm) - 세션용
    private func formatResetTimeOnly(_ timeStr: String?) -> String? {
        guard let timeStr = timeStr else { return nil }
        
        let cleanTime = timeStr
            .replacingOccurrences(of: " (Asia/Seoul)", with: "")
            .replacingOccurrences(of: " (KST)", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        guard let resetDate = parseResetTime(cleanTime) else { return cleanTime }
        
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: resetDate)
        let minute = calendar.component(.minute, from: resetDate)
        
        return String(format: "%02d:%02d", hour, minute)
    }
    
    /// 리셋 시간을 날짜 포함하여 표시 (24시간제 mm.dd hh:mm) - 주간용
    private func formatResetTimeWithDate(_ timeStr: String?) -> String? {
        guard let timeStr = timeStr else { return nil }
        
        let cleanTime = timeStr
            .replacingOccurrences(of: " (Asia/Seoul)", with: "")
            .replacingOccurrences(of: " (KST)", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        guard let resetDate = parseResetTime(cleanTime) else { return cleanTime }
        
        let calendar = Calendar.current
        let month = calendar.component(.month, from: resetDate)
        let day = calendar.component(.day, from: resetDate)
        let hour = calendar.component(.hour, from: resetDate)
        let minute = calendar.component(.minute, from: resetDate)
        
        return String(format: "%02d.%02d %02d:%02d", month, day, hour, minute)
    }
    
    /// 남은 시간 계산 (D-n, hh:mm 형식, 일수가 0이면 hh:mm만)
    private func calculateRemainingTime(from timeStr: String, includeDay: Bool) -> String? {
        let cleanTime = timeStr
            .replacingOccurrences(of: " (Asia/Seoul)", with: "")
            .replacingOccurrences(of: " (KST)", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        guard let resetDate = parseResetTime(cleanTime) else { return nil }
        
        let now = Date()
        let calendar = Calendar.current
        let diff = calendar.dateComponents([.day, .hour, .minute], from: now, to: resetDate)
        let days = diff.day ?? 0
        let hours = diff.hour ?? 0
        let minutes = diff.minute ?? 0
        
        // 이미 리셋 시간이 지났으면
        if days < 0 || hours < 0 || minutes < 0 {
            return "00:00"
        }
        
        if includeDay && days > 0 {
            // D-n, hh:mm 형식
            return String(format: "%02d:%02d, D-%d", hours, minutes, days)
        } else {
            // hh:mm 형식
            return String(format: "%02d:%02d", hours, minutes)
        }
    }
    
    /// 리셋 시간 문자열을 Date로 파싱
    private func parseResetTime(_ timeStr: String) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        let cleanStr = timeStr.trimmingCharacters(in: .whitespaces)
        
        // "4:59pm" 또는 "4:59 pm" 형식 (시:분 포함)
        let hourMinPattern = /^(\d{1,2}):(\d{2})\s*(am|pm)$/.ignoresCase()
        if let match = cleanStr.wholeMatch(of: hourMinPattern) {
            var hour = Int(match.1) ?? 0
            let minute = Int(match.2) ?? 0
            let isPM = match.3.lowercased() == "pm"
            if isPM && hour != 12 { hour += 12 }
            if !isPM && hour == 12 { hour = 0 }
            
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = hour
            components.minute = minute
            
            if let date = calendar.date(from: components) {
                return date > now ? date : calendar.date(byAdding: .day, value: 1, to: date)
            }
        }
        
        // "7pm" 또는 "8am" 형식
        let hourPattern = /^(\d{1,2})\s*(am|pm)$/.ignoresCase()
        if let match = cleanStr.wholeMatch(of: hourPattern) {
            var hour = Int(match.1) ?? 0
            let isPM = match.2.lowercased() == "pm"
            if isPM && hour != 12 { hour += 12 }
            if !isPM && hour == 12 { hour = 0 }
            
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = hour
            components.minute = 0
            
            if let date = calendar.date(from: components) {
                return date > now ? date : calendar.date(byAdding: .day, value: 1, to: date)
            }
        }
        
        // "Dec 31, 8:00am" 또는 "Dec 31, 8am" 형식
        let dateTimePattern = /^(\w+)\s+(\d{1,2}),?\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)$/.ignoresCase()
        if let match = cleanStr.wholeMatch(of: dateTimePattern) {
            let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                          "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]
            
            guard let month = months[String(match.1).lowercased()],
                  let day = Int(match.2) else { return nil }
            
            var hour = Int(match.3) ?? 0
            let minute = match.4.map { Int($0) ?? 0 } ?? 0
            let isPM = match.5.lowercased() == "pm"
            if isPM && hour != 12 { hour += 12 }
            if !isPM && hour == 12 { hour = 0 }
            
            var components = calendar.dateComponents([.year], from: now)
            components.month = month
            components.day = day
            components.hour = hour
            components.minute = minute
            
            if let date = calendar.date(from: components) {
                // 이미 지났거나 너무 과거면 내년으로 (단, 2일 이내의 오차는 허용)
                if date < now.addingTimeInterval(-86400 * 2) {
                    return calendar.date(byAdding: .year, value: 1, to: date)
                }
                return date
            }
        }
        
        // "12/31 8am" 또는 "12/31 8:00pm" 형식 (숫자 월)
        let numericDatePattern = /^(\d{1,2})\/(\d{1,2})\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)$/.ignoresCase()
        if let match = cleanStr.wholeMatch(of: numericDatePattern) {
            guard let month = Int(match.1),
                  let day = Int(match.2) else { return nil }
            
            var hour = Int(match.3) ?? 0
            let minute = match.4.map { Int($0) ?? 0 } ?? 0
            let isPM = match.5.lowercased() == "pm"
            if isPM && hour != 12 { hour += 12 }
            if !isPM && hour == 12 { hour = 0 }
            
            var components = calendar.dateComponents([.year], from: now)
            components.month = month
            components.day = day
            components.hour = hour
            components.minute = minute
            
            if let date = calendar.date(from: components) {
                if date < now.addingTimeInterval(-86400 * 2) {
                    return calendar.date(byAdding: .year, value: 1, to: date)
                }
                return date
            }
        }
        
        NSLog("[UsageViewModel] Failed to parse reset time: '%@'", cleanStr)
        return nil
    }

    // MARK: Private Properties
    private let repository: UsageRepository
    private let notificationService: NotificationServiceProtocol
    private let settingsStore: SettingsStore
    private let dataManager: DataManagerProtocol
    private let sessionDetector: SessionDetector
    private let cliRunner: CLIRunnerProtocol
    private let cliUsageService: CLIUsageServiceProtocol
    private let logReader: ClaudeLogReader
    private let usageAggregator: UsageAggregator
    private let activeProcessMonitor: ActiveProcessMonitor
    private var refreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var lastNotifiedThreshold: Int?

    // MARK: Init
    init(
        repository: UsageRepository,
        notificationService: NotificationServiceProtocol,
        settingsStore: SettingsStore,
        dataManager: DataManagerProtocol,
        sessionDetector: SessionDetector,
        cliRunner: CLIRunnerProtocol,
        cliUsageService: CLIUsageServiceProtocol = CLIUsageService(),
        logReader: ClaudeLogReader = ClaudeLogReaderImpl(),
        usageAggregator: UsageAggregator = UsageAggregatorImpl(),
        activeProcessMonitor: ActiveProcessMonitor
    ) {
        self.repository = repository
        self.notificationService = notificationService
        self.settingsStore = settingsStore
        self.dataManager = dataManager
        self.sessionDetector = sessionDetector
        self.cliRunner = cliRunner
        self.cliUsageService = cliUsageService
        self.logReader = logReader
        self.usageAggregator = usageAggregator
        self.activeProcessMonitor = activeProcessMonitor

        // Load cached data
        if let cached = repository.getCachedUsage() {
            self.usage = cached
        }

        // Observe settings changes
        settingsStore.$settings
            .dropFirst()
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Subscribe to process updates
        activeProcessMonitor.processUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.processSnapshot = snapshot
                self?.activeProcesses = snapshot.processes
            }
            .store(in: &cancellables)

        // Setup session detector callbacks
        setupSessionDetectorCallbacks()

        // Load sessions only (CLI availability check delayed to first usage)
        Task {
            self.writeDebugLog("UsageViewModel init - starting Task")
            await loadSessions()
            await sessionDetector.startMonitoring()
            // CLI 가용성 체크와 서비스 가용성 체크는 첫 사용 시 지연 로딩 (권한 요청 최소화)
            // 초기 데이터 로드는 startAutoRefresh()에서 loadUsage()로 처리됨
            self.writeDebugLog("UsageViewModel init - completed")
        }
    }

    deinit {
        refreshTask?.cancel()
        activeProcessMonitor.stopMonitoring()
    }

    // MARK: Public Methods
    func loadUsage() async {
        guard !isLoading else {
            writeDebugLog("loadUsage skipped - already loading")
            return
        }

        logDebug("Loading usage data via CLI /usage...", category: .cli)
        isLoading = true
        error = nil

        // CLI /usage 로드 (단일 데이터 소스)
        await loadCLIUsage()

        // CLI 결과로 알림 체크
        if let cliResult = cliUsageResult {
            logInfo("CLI /usage loaded: session=\(cliResult.sessionRemainingPercent)%, weekly=\(cliResult.weeklyRemainingPercent)%", category: .cli)

            // 세션 감지기 업데이트 (잔여 퍼센트 기반)
            await sessionDetector.updateUsage(
                percentage: Double(cliResult.sessionRemainingPercent),
                tokensUsed: 0  // CLI에서 토큰 수는 제공하지 않음
            )

            // 알림 체크
            await checkAndSendCLINotifications()
        } else {
            logWarning("CLI /usage returned no data", category: .cli)
        }

        isLoading = false
    }

    /// CLI 결과 기반 알림 체크
    private func checkAndSendCLINotifications() async {
        guard let cliResult = cliUsageResult else {
            writeDebugLog("[Notification] No CLI result, skipping notification check")
            return
        }

        let percentage = cliResult.sessionRemainingPercent
        let settings = settingsStore.settings

        writeDebugLog("[Notification] Checking: percentage=\(percentage)%, lowThreshold=\(settings.lowThreshold)%, criticalThreshold=\(settings.criticalThreshold)%, lastNotified=\(String(describing: lastNotifiedThreshold))")

        // Critical notification
        if settings.enableCriticalNotification &&
           percentage <= settings.criticalThreshold &&
           lastNotifiedThreshold != settings.criticalThreshold {
            writeDebugLog("[Notification] Sending CRITICAL notification")
            await notificationService.send(NotificationRequest(
                type: .criticalUsage,
                title: "거의 소진됨",
                body: "토큰 잔여량이 \(percentage)%입니다.",
                sound: settings.enableSound
            ))
            lastNotifiedThreshold = settings.criticalThreshold
        }
        // Low notification
        else if settings.enableLowNotification &&
                percentage <= settings.lowThreshold &&
                percentage > settings.criticalThreshold &&
                lastNotifiedThreshold != settings.lowThreshold {
            writeDebugLog("[Notification] Sending LOW notification")
            await notificationService.send(NotificationRequest(
                type: .lowUsage,
                title: "잔량 낮음",
                body: "토큰 잔여량이 \(percentage)%입니다.",
                sound: settings.enableSound
            ))
            lastNotifiedThreshold = settings.lowThreshold
        } else {
            writeDebugLog("[Notification] No notification needed")
        }

        // Reset threshold if percentage is back to normal
        if percentage > settings.lowThreshold {
            lastNotifiedThreshold = nil
        }
    }

    /// 테스트 알림 전송
    func sendTestNotification() async {
        writeDebugLog("[Notification] Sending TEST notification")
        await notificationService.send(NotificationRequest(
            type: .lowUsage,
            title: "테스트 알림",
            body: "Claudacity 알림 기능이 정상 작동합니다.",
            sound: settingsStore.settings.enableSound
        ))
    }

    func refresh() {
        Task {
            await loadUsage()
        }
    }

    func startAutoRefresh() {
        stopAutoRefresh()

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.loadUsage()

                guard let interval = self?.settingsStore.refreshInterval else { break }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: Session Methods
    func loadSessions() async {
        do {
            currentSession = try await dataManager.getCurrentSession()
            recentSessions = try await dataManager.getRecentSessions(limit: 10)
            logDebug("Loaded sessions: current=\(currentSession?.name ?? "none"), recent=\(recentSessions.count)", category: .data)
        } catch {
            logError("Failed to load sessions", category: .data, error: error)
        }
    }

    // MARK: Chart Data Methods
    func loadChartData(for period: TimePeriod) async {
        guard logReader.isClaudeCodeInstalled else {
            logDebug("Skipping chart data load - Claude Code not installed", category: .data)
            return
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let entries = try await logReader.readAllEntries()
            
            switch period {
            case .hourly:
                let hourlyData = usageAggregator.aggregateHourly(entries: entries, hours: 24, bucketHours: 1)
                hourlyChartData = hourlyData.map { date, usage in
                    ChartDataPoint(timestamp: date, periodEnd: usage.period.end, value: Double(usage.rateLimitTokens))
                }.sorted { $0.timestamp < $1.timestamp }

            case .daily:
                let dailyData = usageAggregator.aggregateDaily(entries: entries, days: 7)
                dailyChartData = dailyData.map { date, usage in
                    ChartDataPoint(timestamp: date, value: Double(usage.rateLimitTokens))
                }.sorted { $0.timestamp < $1.timestamp }
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            logDebug("[성능] Loaded chart data for \(period.rawValue): \(period == .hourly ? hourlyChartData.count : dailyChartData.count) points in \(String(format: "%.3f", elapsed))s", category: .data)
        } catch {
            logError("Failed to load chart data from JSONL", category: .data, error: error)
        }
    }

    /// 모든 차트 데이터 로드 - 한 번의 엔트리 로드로 최적화
    func loadAllChartData() async {
        guard logReader.isClaudeCodeInstalled else {
            logDebug("Skipping chart data load - Claude Code not installed", category: .data)
            return
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            // 한 번만 엔트리 로드
            let entries = try await logReader.readAllEntries()
            
            // hourly 집계 (1시간 단위)
            let hourlyData = usageAggregator.aggregateHourly(entries: entries, hours: 24, bucketHours: 1)
            hourlyChartData = hourlyData.map { date, usage in
                ChartDataPoint(timestamp: date, periodEnd: usage.period.end, value: Double(usage.rateLimitTokens))
            }.sorted { $0.timestamp < $1.timestamp }
            
            // daily 집계
            let dailyData = usageAggregator.aggregateDaily(entries: entries, days: 7)
            dailyChartData = dailyData.map { date, usage in
                ChartDataPoint(timestamp: date, periodEnd: usage.period.end, value: Double(usage.rateLimitTokens))
            }.sorted { $0.timestamp < $1.timestamp }
            
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            logDebug("[성능] Loaded all chart data: hourly=\(hourlyChartData.count), daily=\(dailyChartData.count) in \(String(format: "%.3f", elapsed))s", category: .data)
        } catch {
            logError("Failed to load chart data from JSONL", category: .data, error: error)
        }
    }

    func chartData(for period: TimePeriod) -> [ChartDataPoint] {
        switch period {
        case .hourly:
            return hourlyChartData.isEmpty ? generateEmptyData(for: period) : hourlyChartData
        case .daily:
            return dailyChartData.isEmpty ? generateEmptyData(for: period) : dailyChartData
        }
    }

    private func generateEmptyData(for period: TimePeriod) -> [ChartDataPoint] {
        let count = period == .hourly ? 24 : 7
        let interval: TimeInterval = period == .hourly ? 3600 : 86400
        let now = Date()

        return (0..<count).map { index in
            ChartDataPoint(
                timestamp: now.addingTimeInterval(TimeInterval(-index) * interval),
                value: 0
            )
        }.reversed()
    }

    func startNewSession(name: String? = nil) async {
        do {
            let session = try await dataManager.createSession(name: name)
            currentSession = session
            await loadSessions()
            logInfo("Started new session: \(session.name)", category: .data)
        } catch {
            logError("Failed to start session", category: .data, error: error)
        }
    }

    func endCurrentSession() async {
        do {
            try await dataManager.endCurrentSession()
            currentSession = nil
            await loadSessions()
            logInfo("Ended current session", category: .data)
        } catch {
            logError("Failed to end session", category: .data, error: error)
        }
    }

    // MARK: CLI Methods
    func checkClaudeCodeInstallation() async {
        isClaudeCodeInstalled = await cliRunner.isClaudeCodeInstalled()
        logInfo("Claude Code installation status: \(isClaudeCodeInstalled)", category: .cli)
    }

    /// CLI /usage 서비스 사용 가능 여부 확인
    func checkCLIUsageAvailability() async {
        isCLIUsageAvailable = await cliUsageService.isAvailable()
        logInfo("CLI /usage service availability: \(isCLIUsageAvailable)", category: .cli)
    }

    /// CLI /usage 명령으로 사용량 로드 (Expect 스크립트 전용)
    func loadCLIUsage() async {
        // 첫 호출 시에만 서비스 사용 가능 여부 확인 (지연 로딩으로 권한 요청 최소화)
        if !isCLIUsageAvailable {
            logDebug("First CLI /usage check, verifying availability...", category: .cli)
            await checkCLIUsageAvailability()
        }

        guard isCLIUsageAvailable else {
            logWarning("CLI /usage not available", category: .cli)
            return
        }

        do {
            cliUsageResult = try await cliUsageService.fetchUsage()
            if let result = cliUsageResult {
                logInfo("CLI /usage loaded: session=\(result.sessionUsedPercent)% used (\(result.sessionRemainingPercent)% remaining), weekly=\(result.weeklyUsedPercent)% used", category: .cli)
                writeDebugLog("CLI /usage: session=\(result.sessionRemainingPercent)%, weekly=\(result.weeklyRemainingPercent)%, reset=\(result.sessionResetTime ?? "nil")")
            }
        } catch let cliError {
            logError("CLI /usage failed: \(cliError)", category: .cli)
            writeDebugLog("CLI /usage failed: \(cliError)")
        }
    }

    // MARK: Private Methods
    private func checkAndSendNotifications(for usage: UsageData) async {
        // CLI /usage 결과가 있으면 우선 사용
        let percentage: Int
        if let cliResult = cliUsageResult {
            percentage = cliResult.sessionRemainingPercent
        } else {
            percentage = Int(usage.session.percentage)
        }
        let settings = settingsStore.settings

        // Critical notification
        if settings.enableCriticalNotification &&
           percentage <= settings.criticalThreshold &&
           lastNotifiedThreshold != settings.criticalThreshold {
            await notificationService.send(NotificationRequest(
                type: .criticalUsage,
                title: "거의 소진됨",
                body: "토큰 잔여량이 \(percentage)%입니다.",
                sound: settings.enableSound
            ))
            lastNotifiedThreshold = settings.criticalThreshold
        }
        // Low notification
        else if settings.enableLowNotification &&
                percentage <= settings.lowThreshold &&
                percentage > settings.criticalThreshold &&
                lastNotifiedThreshold != settings.lowThreshold {
            await notificationService.send(NotificationRequest(
                type: .lowUsage,
                title: "잔량 낮음",
                body: "토큰 잔여량이 \(percentage)%입니다.",
                sound: settings.enableSound
            ))
            lastNotifiedThreshold = settings.lowThreshold
        }

        // Reset threshold if percentage is back to normal
        if percentage > settings.lowThreshold {
            lastNotifiedThreshold = nil
        }
    }

    private func setupSessionDetectorCallbacks() {
        sessionDetector.onSessionStarted = { [weak self] session in
            Task { @MainActor [weak self] in
                self?.currentSession = session
                await self?.loadSessions()
            }
        }

        sessionDetector.onSessionEnded = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.currentSession = nil
                await self?.loadSessions()
            }
        }

        sessionDetector.onIdleDetected = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.loadSessions()
            }
        }
    }

    private func updateCurrentSessionTokens(from usage: UsageData) async {
        guard let session = currentSession else { return }

        // Calculate token usage from breakdown
        let inputTokens = usage.breakdown.inputTokens
        let outputTokens = usage.breakdown.outputTokens
        let cachedTokens = usage.breakdown.cachedTokens

        do {
            try await dataManager.updateSessionTokens(
                session,
                input: inputTokens,
                output: outputTokens,
                cached: cachedTokens
            )
        } catch {
            logError("Failed to update session tokens", category: .data, error: error)
        }
    }

    /// Merge repository usage data with CLI usage data
    /// CLI data takes precedence when available as it's more accurate for CLI usage
    private func mergeUsageData(repositoryData: UsageData, cliData: CLIUsageData?) -> UsageData {
        guard let cliData = cliData else {
            return repositoryData
        }

        // Calculate merged session data
        let mergedSession: UsageLevel
        if let cliSessionUsed = cliData.sessionTokensUsed {
            // Add CLI session tokens to repository session tokens
            let totalUsed = repositoryData.session.used + cliSessionUsed
            mergedSession = UsageLevel(
                used: totalUsed,
                limit: repositoryData.session.limit,
                resetAt: repositoryData.session.resetAt
            )
        } else {
            mergedSession = repositoryData.session
        }

        // Calculate merged daily data
        let mergedDaily: UsageLevel
        if let cliDailyUsed = cliData.dailyTokensUsed {
            let totalUsed = repositoryData.daily.used + cliDailyUsed
            mergedDaily = UsageLevel(
                used: totalUsed,
                limit: repositoryData.daily.limit,
                resetAt: repositoryData.daily.resetAt
            )
        } else {
            mergedDaily = repositoryData.daily
        }

        // Calculate merged weekly data
        let mergedWeekly: UsageLevel
        if let cliWeeklyUsed = cliData.weeklyTokensUsed {
            let totalUsed = repositoryData.weekly.used + cliWeeklyUsed
            mergedWeekly = UsageLevel(
                used: totalUsed,
                limit: repositoryData.weekly.limit,
                resetAt: repositoryData.weekly.resetAt
            )
        } else {
            mergedWeekly = repositoryData.weekly
        }

        // Merge token breakdown
        let mergedBreakdown: TokenBreakdown
        if let cliInput = cliData.inputTokens, let cliOutput = cliData.outputTokens {
            mergedBreakdown = TokenBreakdown(
                inputTokens: repositoryData.breakdown.inputTokens + cliInput,
                outputTokens: repositoryData.breakdown.outputTokens + cliOutput,
                cachedTokens: repositoryData.breakdown.cachedTokens
            )
        } else {
            mergedBreakdown = repositoryData.breakdown
        }

        logDebug("Merged usage data: repository session=\(repositoryData.session.used), cli session=\(cliData.sessionTokensUsed ?? 0)", category: .cli)

        return UsageData(
            session: mergedSession,
            daily: mergedDaily,
            weekly: mergedWeekly,
            breakdown: mergedBreakdown,
            rate: repositoryData.rate,
            updatedAt: cliData.lastUpdated ?? repositoryData.updatedAt
        )
    }

    // MARK: - JSONL Log Methods

    /// 디버그 로그를 파일에 저장 (권한 문제 방지를 위해 /tmp 사용)
    private func writeDebugLog(_ message: String) {
        let logFile = URL(fileURLWithPath: "/tmp/claudacity_jsonl_debug.log")
        let line = "\(Date()): \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFile)
            }
        }
    }

    /// JSONL 로그 파일에서 사용량 로드
    func loadJSONLUsage() async {
        let username = NSUserName()
        let claudePath = "/Users/\(username)/.claude/projects"
        let exists = FileManager.default.fileExists(atPath: claudePath)
        let dirs = logReader.getLogDirectories()

        NSLog("[Claudacity] loadJSONLUsage: user=%@, path=%@, exists=%d, dirs=%d", username, claudePath, exists ? 1 : 0, dirs.count)
        writeDebugLog("loadJSONLUsage: user=\(username), path=\(claudePath), exists=\(exists), dirs=\(dirs.count)")
        for dir in dirs.prefix(3) {
            writeDebugLog("- dir: \(dir.lastPathComponent)")
        }

        guard logReader.isClaudeCodeInstalled else {
            debugInfo = "Not installed: \(claudePath)"
            writeDebugLog("Claude Code not installed at \(claudePath)")
            return
        }

        do {
            NSLog("[Claudacity] Starting to read all entries...")
            let entries = try await logReader.readAllEntries()
            let entriesWithUsage = entries.filter { $0.usage != nil }

            NSLog("[Claudacity] Loaded entries: total=%d, withUsage=%d", entries.count, entriesWithUsage.count)
            writeDebugLog("Loaded entries: total=\(entries.count), withUsage=\(entriesWithUsage.count)")

            // 샘플 usage 출력 (처음 3개)
            for (idx, entry) in entriesWithUsage.prefix(3).enumerated() {
                if let usage = entry.usage {
                    writeDebugLog("Sample \(idx): input=\(usage.inputTokens), output=\(usage.outputTokens)")
                }
            }

            // 5시간 윈도우 집계 (현재 세션)
            jsonlUsage = usageAggregator.aggregateCurrentWindow(entries: entries)

            // 롤링 7일 주간 집계 (주간 한도용)
            jsonlWeeklyUsage = usageAggregator.aggregateRollingWeek(entries: entries)

            let windowTokens = jsonlUsage?.rateLimitTokens ?? 0
            let _ = jsonlWeeklyUsage?.rateLimitTokens ?? 0  // 로깅용

            let limit = settingsStore.settings.subscriptionPlan.estimatedTokenLimit
            let usedPercent = Double(windowTokens) / Double(limit) * 100
            let remainPercent = max(0, 100 - usedPercent)

            NSLog("[Claudacity] Aggregated: 5h=%lld, limit=%lld, used=%.1f%%, remain=%.1f%%",
                  windowTokens, limit, usedPercent, remainPercent)
            writeDebugLog("Aggregated: 5h=\(windowTokens), limit=\(limit), used=\(String(format: "%.1f", usedPercent))%, remain=\(String(format: "%.1f", remainPercent))%")

            debugInfo = "dirs=\(dirs.count), entries=\(entries.count), withUsage=\(entriesWithUsage.count), 5h=\(windowTokens)"
        } catch {
            debugInfo = "Error: \(error.localizedDescription)"
            writeDebugLog("Error: \(error)")
        }
    }

    /// 구독 플랜 기준 잔여 퍼센트 계산
    var jsonlRemainingPercentage: Double {
        guard let usage = jsonlUsage else { return 100 }
        let limit = settingsStore.settings.subscriptionPlan.estimatedTokenLimit
        return usage.remainingPercentage(limit: limit)
    }

    /// 구독 플랜 기준 사용 퍼센트 계산
    var jsonlUsagePercentage: Double {
        100 - jsonlRemainingPercentage
    }
    
    /// 주간 잔여 퍼센트 계산
    var jsonlWeeklyRemainingPercentage: Double {
        guard let usage = jsonlWeeklyUsage else { return 100 }
        // 주간 한도는 5시간 윈도우의 약 4배 (실제 사용량 역산 기반)
        let weeklyLimit = settingsStore.settings.subscriptionPlan.estimatedTokenLimit * 4
        return usage.remainingPercentage(limit: weeklyLimit)
    }

    /// 현재 5시간 윈도우의 토큰 사용량 (rate limit 계산용)
    var currentWindowTokens: Int64 {
        jsonlUsage?.rateLimitTokens ?? 0
    }

    /// 이번 주 토큰 사용량 (롤링 7일)
    var weeklyTokens: Int64 {
        jsonlWeeklyUsage?.rateLimitTokens ?? 0
    }

    /// 캐시 효율성 (0-100%)
    var cacheEfficiencyPercent: Double {
        jsonlUsage?.cacheEfficiencyPercent ?? 0
    }

    /// 캐시로 절약된 토큰 수
    var tokensSavedByCache: Int64 {
        jsonlUsage?.tokensSavedByCache ?? 0
    }

    /// 구독 플랜 기준 토큰 한도
    var tokenLimit: Int64 {
        settingsStore.settings.subscriptionPlan.estimatedTokenLimit
    }

    // MARK: - Active Process Monitoring

    /// Starts monitoring active Claude Code processes
    func startProcessMonitoring(interval: TimeInterval = 5.0) {
        logInfo("Starting active process monitoring with \(interval)s interval", category: .cli)
        activeProcessMonitor.startMonitoring(interval: interval)
    }

    /// Stops monitoring active Claude Code processes
    func stopProcessMonitoring() {
        logInfo("Stopping active process monitoring", category: .cli)
        activeProcessMonitor.stopMonitoring()
    }

    /// Gets the current snapshot of active processes
    func getCurrentProcessSnapshot() async -> ProcessSnapshot {
        await activeProcessMonitor.getCurrentSnapshot()
    }
}
