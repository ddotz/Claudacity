// MARK: - Imports
import Foundation
import SwiftData

// MARK: - Dependency Container
@MainActor
final class Dependencies {
    // MARK: Singleton
    static let shared = Dependencies()

    // MARK: Properties
    private(set) lazy var modelContainer: ModelContainer = {
        do {
            return try DataManagerFactory.createModelContainer()
        } catch {
            logError("Failed to create ModelContainer: \(error)", category: .data)
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    private(set) lazy var dataManager: DataManagerProtocol = {
        DataManager(modelContainer: modelContainer)
    }()

    private(set) lazy var settingsStore: SettingsStore = {
        SettingsStore()
    }()

    private(set) lazy var notificationService: NotificationServiceProtocol = {
        NotificationService()
    }()

    private(set) lazy var usageRepository: UsageRepository = {
        #if DEBUG
        let dataSource = MockDataSource()
        #else
        let dataSource = MockDataSource() // TODO: Replace with real API client
        #endif
        return UsageRepositoryImpl(dataSource: dataSource)
    }()

    private(set) lazy var sessionDetector: SessionDetector = {
        SessionDetector.create(dataManager: dataManager, settingsStore: settingsStore)
    }()

    private(set) lazy var cliRunner: CLIRunnerProtocol = {
        // 항상 실제 CLI Runner 사용 (프로세스 모니터링에 필요)
        CLIRunner()
    }()

    private(set) lazy var cliUsageService: CLIUsageServiceProtocol = {
        // 항상 실제 CLI 서비스 사용 (실시간 데이터 필요)
        CLIUsageService()
    }()

    private(set) lazy var processDiscovery: ProcessDiscovery = {
        ProcessDiscoveryImpl()
    }()

    private(set) lazy var logReader: ClaudeLogReader = {
        ClaudeLogReaderImpl()
    }()

    private(set) lazy var activeProcessMonitor: ActiveProcessMonitor = {
        ActiveProcessMonitorImpl(
            processDiscovery: processDiscovery,
            logReader: logReader
        )
    }()

    private(set) lazy var usageViewModel: UsageViewModel = {
        UsageViewModel(
            repository: usageRepository,
            notificationService: notificationService,
            settingsStore: settingsStore,
            dataManager: dataManager,
            sessionDetector: sessionDetector,
            cliRunner: cliRunner,
            cliUsageService: cliUsageService,
            activeProcessMonitor: activeProcessMonitor
        )
    }()

    // MARK: Init
    private init() {}
}
