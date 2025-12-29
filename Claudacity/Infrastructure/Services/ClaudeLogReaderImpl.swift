// MARK: - Imports
import Foundation
import OSLog

// MARK: - Claude Log Reader Implementation
/// Claude Code JSONL 로그 파일을 읽고 파싱하는 구현체
/// 경로: ~/.claude/projects/[project]/conversation.jsonl
final class ClaudeLogReaderImpl: ClaudeLogReader, @unchecked Sendable {
    // MARK: Properties
    private let fileManager = FileManager.default
    private let claudeDir: URL
    private let logger = Logger(subsystem: "com.claudacity.app", category: "ClaudeLogReader")
    private let decoder: JSONDecoder
    
    // MARK: 캐싱 관련
    private var cachedEntries: [ClaudeLogEntry] = []
    private var lastLoadTime: Date?
    private let cacheValiditySeconds: TimeInterval = 30  // 캐시 유효 시간 (30초)
    private let cacheLock = NSLock()

    // MARK: Initialization
    init() {
        // 샌드박스 환경에서는 NSHomeDirectory()가 컨테이너 경로를 반환하므로
        // 직접 /Users/사용자이름 경로를 구성
        let username = NSUserName()
        let homeDir = URL(fileURLWithPath: "/Users/\(username)")
        self.claudeDir = homeDir.appendingPathComponent(".claude/projects")

        logger.info("Claude projects directory: \(self.claudeDir.path), username: \(username)")

        self.decoder = JSONDecoder()
        // ISO8601 밀리초 형식 지원 (예: 2025-12-23T00:10:34.068Z)
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            // 밀리초 포함 ISO8601 형식 시도
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            // 밀리초 없는 ISO8601 형식 시도
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
        }
    }

    // MARK: - ClaudeLogReader Protocol

    var isClaudeCodeInstalled: Bool {
        let exists = fileManager.fileExists(atPath: claudeDir.path)
        // 디버그용 출력
        print("[ClaudeLogReader] Checking Claude Code: path=\(self.claudeDir.path), exists=\(exists)")
        logger.info("Checking Claude Code: path=\(self.claudeDir.path), exists=\(exists)")
        return exists
    }

    func getLogDirectories() -> [URL] {
        NSLog("[ClaudeLogReader] getLogDirectories called, claudeDir=%@", claudeDir.path)

        guard fileManager.fileExists(atPath: claudeDir.path) else {
            NSLog("[ClaudeLogReader] Directory does not exist: %@", claudeDir.path)
            logger.warning("Claude projects directory not found: \(self.claudeDir.path)")
            return []
        }

        do {
            // 심볼릭 링크를 따라가지 않도록 옵션 추가 (권한 요청 방지)
            let contents = try fileManager.contentsOfDirectory(
                at: claudeDir,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            NSLog("[ClaudeLogReader] Found %d items in directory", contents.count)

            // 디렉토리이면서 .jsonl 파일이 있는 것만 필터링
            // 심볼릭 링크는 건너뜀 (권한 요청 방지)
            let dirs = contents.filter { url in
                // 심볼릭 링크 체크 (권한 요청 방지)
                if let isSymlink = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink,
                   isSymlink == true {
                    NSLog("[ClaudeLogReader] Skipping symbolic link: %@", url.lastPathComponent)
                    return false
                }

                var isDirectory: ObjCBool = false
                let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
                guard exists && isDirectory.boolValue else { return false }

                // .jsonl 파일이 있는지 확인
                do {
                    let subContents = try fileManager.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: [.isSymbolicLinkKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    )
                    let hasJsonl = subContents.contains { $0.pathExtension == "jsonl" }
                    return hasJsonl
                } catch {
                    NSLog("[ClaudeLogReader] Error reading subdirectory %@: %@", url.lastPathComponent, error.localizedDescription)
                    return false
                }
            }
            NSLog("[ClaudeLogReader] Filtered to %d directories with JSONL files", dirs.count)
            return dirs
        } catch {
            NSLog("[ClaudeLogReader] Error listing directory: %@", error.localizedDescription)
            logger.error("Failed to list project directories: \(error.localizedDescription)")
            return []
        }
    }

    func readEntriesBySession(from projectDir: URL, activeMinutes: Int = 30) async throws -> [SessionEntries] {
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.isSymbolicLinkKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )

            // 심볼릭 링크가 아닌 .jsonl 파일만 필터링
            let jsonlFiles = contents.filter { url in
                // 심볼릭 링크 건너뛰기
                if let isSymlink = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink,
                   isSymlink == true {
                    return false
                }
                return url.pathExtension == "jsonl"
            }

            // 최근 N분 이내 수정된 파일만 선택 (활성 세션)
            let cutoffDate = Date().addingTimeInterval(-Double(activeMinutes) * 60)
            let activeFiles = jsonlFiles.filter { url in
                if let modDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                    return modDate > cutoffDate
                }
                return false
            }

            logger.debug("Found \(activeFiles.count) active sessions in \(projectDir.lastPathComponent)")

            // 각 파일에서 세션 정보 추출
            var sessionEntries: [SessionEntries] = []

            for fileURL in activeFiles {
                do {
                    let entries = try await readSingleFile(fileURL)

                    // session ID 추출 (파일명에서 추출 가능)
                    let fileName = fileURL.deletingPathExtension().lastPathComponent
                    let sessionId = fileName.hasPrefix("agent-") ? fileName : fileName

                    let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()

                    let session = SessionEntries(
                        sessionId: sessionId,
                        sessionFile: fileURL,
                        entries: entries,
                        lastModified: modDate
                    )

                    sessionEntries.append(session)
                } catch {
                    logger.warning("Failed to read session file \(fileURL.lastPathComponent): \(error.localizedDescription)")
                    continue
                }
            }

            // 최근 수정 시간 순으로 정렬
            sessionEntries.sort { $0.lastModified > $1.lastModified }

            return sessionEntries
        } catch {
            logger.error("Failed to read sessions from \(projectDir.lastPathComponent): \(error.localizedDescription)")
            return []
        }
    }

    func readEntries(from projectDir: URL) async throws -> [ClaudeLogEntry] {
        // 프로젝트 디렉토리 내의 가장 최근 .jsonl 파일만 읽기 (현재 활성 세션)
        guard fileManager.fileExists(atPath: projectDir.path) else {
            logger.debug("Project directory not found: \(projectDir.lastPathComponent)")
            return []
        }

        do {
            // 심볼릭 링크를 건너뛰도록 옵션 추가 (권한 요청 방지)
            let contents = try fileManager.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.isSymbolicLinkKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )

            // 심볼릭 링크가 아닌 .jsonl 파일만 필터링
            let jsonlFiles = contents.filter { url in
                // 심볼릭 링크 건너뛰기
                if let isSymlink = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink,
                   isSymlink == true {
                    return false
                }
                return url.pathExtension == "jsonl"
            }

            // 가장 최근에 수정된 파일 찾기 (현재 활성 세션)
            guard let mostRecentFile = jsonlFiles.max(by: { file1, file2 in
                let date1 = try? file1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let date2 = try? file2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return (date1 ?? .distantPast) < (date2 ?? .distantPast)
            }) else {
                logger.debug("No .jsonl files found in \(projectDir.lastPathComponent)")
                return []
            }

            logger.debug("Reading most recent file: \(mostRecentFile.lastPathComponent)")
            let entries = try await readSingleFile(mostRecentFile)
            return entries
        } catch {
            logger.error("Failed to read project directory: \(error.localizedDescription)")
            return []
        }
    }

    func readSessionFile(_ sessionFile: URL) async throws -> [ClaudeLogEntry] {
        guard sessionFile.pathExtension == "jsonl" else {
            logger.warning("Not a JSONL file: \(sessionFile.lastPathComponent)")
            return []
        }

        guard fileManager.fileExists(atPath: sessionFile.path) else {
            logger.debug("Session file not found: \(sessionFile.lastPathComponent)")
            return []
        }

        logger.debug("Reading session file: \(sessionFile.lastPathComponent)")
        return try await readSingleFile(sessionFile)
    }

    private func readSingleFile(_ logFile: URL) async throws -> [ClaudeLogEntry] {
        return try await Task.detached(priority: .utility) { [decoder, logger] in
            do {
                let data = try Data(contentsOf: logFile)
                let content = String(data: data, encoding: .utf8) ?? ""
                let lines = content.components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

                var entries: [ClaudeLogEntry] = []
                entries.reserveCapacity(lines.count)
                var parseErrorCount = 0

                for line in lines {
                    guard let lineData = line.data(using: .utf8) else { continue }
                    do {
                        let entry = try decoder.decode(ClaudeLogEntry.self, from: lineData)
                        entries.append(entry)
                    } catch {
                        parseErrorCount += 1
                        // 첫 번째 에러만 로그
                        if parseErrorCount == 1 {
                            logger.debug("Parse error in \(logFile.lastPathComponent): \(error.localizedDescription)")
                        }
                    }
                }

                if parseErrorCount > 0 {
                    logger.info("File \(logFile.lastPathComponent): parsed \(entries.count)/\(lines.count) lines, \(parseErrorCount) errors")
                }

                return entries
            } catch {
                logger.error("Failed to read log file \(logFile.lastPathComponent): \(error.localizedDescription)")
                throw error
            }
        }.value
    }

    func readAllEntries() async throws -> [ClaudeLogEntry] {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // 캐시 유효성 확인
        cacheLock.lock()
        if let lastLoad = lastLoadTime,
           Date().timeIntervalSince(lastLoad) < cacheValiditySeconds,
           !cachedEntries.isEmpty {
            let cached = cachedEntries
            cacheLock.unlock()
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            logger.info("[성능] 캐시 반환: \(cached.count) entries in \(String(format: "%.3f", elapsed))s")
            return cached
        }
        cacheLock.unlock()
        
        let directories = getLogDirectories()
        var allEntries: [ClaudeLogEntry] = []
        allEntries.reserveCapacity(15000)  // 예상 엔트리 수만큼 미리 할당

        logger.info("Reading entries from \(directories.count) directories")

        // 병렬 처리 적용
        await withTaskGroup(of: [ClaudeLogEntry].self) { group in
            for dir in directories {
                group.addTask {
                    do {
                        return try await self.readEntries(from: dir)
                    } catch {
                        self.logger.warning("Failed to read entries from \(dir.lastPathComponent): \(error.localizedDescription)")
                        return []
                    }
                }
            }
            
            for await entries in group {
                allEntries.append(contentsOf: entries)
            }
        }

        let entriesWithUsage = allEntries.filter { $0.usage != nil }

        // 타임스탬프 기준 정렬
        let sortedEntries = allEntries.sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }

        // 디버그: 최근 5개 엔트리 로그
        let recentEntries = entriesWithUsage.suffix(5)
        for entry in recentEntries {
            if let timestamp = entry.timestamp, let usage = entry.usage {
                let tokens = usage.inputTokens + usage.outputTokens + (usage.cacheCreationInputTokens ?? 0)
                logger.debug("[최근 엔트리] \(timestamp): \(tokens) 토큰")
            }
        }

        // 캐시 업데이트
        cacheLock.lock()
        cachedEntries = sortedEntries
        lastLoadTime = Date()
        cacheLock.unlock()

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        logger.info("[성능] 전체 로드: \(allEntries.count) entries, with usage: \(entriesWithUsage.count), 소요시간: \(String(format: "%.3f", elapsed))s")

        return sortedEntries
    }
    
    /// 캐시 무효화 (파일 변경 시 호출)
    func invalidateCache() {
        cacheLock.lock()
        cachedEntries = []
        lastLoadTime = nil
        cacheLock.unlock()
        logger.debug("Cache invalidated")
    }

    func watchForChanges() -> AsyncStream<URL> {
        AsyncStream { continuation in
            // FSEvents 기반 파일 감시 구현
            // TODO: DispatchSource.makeFileSystemObjectSource 사용하여 구현
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: open(claudeDir.path, O_EVTONLY),
                eventMask: [.write, .extend],
                queue: .global(qos: .utility)
            )

            source.setEventHandler {
                continuation.yield(self.claudeDir)
            }

            source.setCancelHandler {
                continuation.finish()
            }

            continuation.onTermination = { _ in
                source.cancel()
            }

            source.resume()
        }
    }
}
