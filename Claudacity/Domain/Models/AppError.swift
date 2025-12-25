// MARK: - Imports
import Foundation

// MARK: - App Error
enum AppError: Error, LocalizedError, Equatable {
    // Auth
    case authRequired
    case sessionExpired
    case invalidCredentials

    // Network
    case networkUnavailable
    case requestTimeout
    case serverError(Int)
    case rateLimited(retryAfter: TimeInterval)
    case invalidURL
    case invalidResponse

    // Data
    case parsingFailed
    case dataNotFound

    // CLI
    case cliNotInstalled
    case cliExecutionFailed(String)

    // Unknown
    case unknown

    // MARK: Category
    enum Category {
        case auth
        case network
        case server
        case data
        case cli
    }

    var category: Category {
        switch self {
        case .authRequired, .sessionExpired, .invalidCredentials:
            return .auth
        case .networkUnavailable, .requestTimeout, .invalidURL:
            return .network
        case .serverError, .rateLimited:
            return .server
        case .parsingFailed, .dataNotFound, .invalidResponse:
            return .data
        case .cliNotInstalled, .cliExecutionFailed:
            return .cli
        case .unknown:
            return .network
        }
    }

    // MARK: LocalizedError
    var errorDescription: String? {
        switch self {
        case .authRequired:
            return "로그인이 필요합니다"
        case .sessionExpired:
            return "세션이 만료되었습니다"
        case .invalidCredentials:
            return "인증 정보가 올바르지 않습니다"
        case .networkUnavailable:
            return "네트워크에 연결할 수 없습니다"
        case .requestTimeout:
            return "요청 시간이 초과되었습니다"
        case .serverError(let code):
            return "서버 오류 (\(code))"
        case .rateLimited(let retry):
            return "요청 제한 초과. \(Int(retry))초 후 재시도"
        case .invalidURL:
            return "잘못된 URL입니다"
        case .invalidResponse:
            return "잘못된 응답입니다"
        case .parsingFailed:
            return "데이터 파싱에 실패했습니다"
        case .dataNotFound:
            return "데이터를 찾을 수 없습니다"
        case .cliNotInstalled:
            return "Claude Code가 설치되어 있지 않습니다"
        case .cliExecutionFailed(let msg):
            return "CLI 실행 실패: \(msg)"
        case .unknown:
            return "알 수 없는 오류가 발생했습니다"
        }
    }

    // MARK: Equatable
    static func == (lhs: AppError, rhs: AppError) -> Bool {
        switch (lhs, rhs) {
        case (.authRequired, .authRequired),
             (.sessionExpired, .sessionExpired),
             (.invalidCredentials, .invalidCredentials),
             (.networkUnavailable, .networkUnavailable),
             (.requestTimeout, .requestTimeout),
             (.invalidURL, .invalidURL),
             (.invalidResponse, .invalidResponse),
             (.parsingFailed, .parsingFailed),
             (.dataNotFound, .dataNotFound),
             (.cliNotInstalled, .cliNotInstalled),
             (.unknown, .unknown):
            return true
        case (.serverError(let a), .serverError(let b)):
            return a == b
        case (.rateLimited(let a), .rateLimited(let b)):
            return a == b
        case (.cliExecutionFailed(let a), .cliExecutionFailed(let b)):
            return a == b
        default:
            return false
        }
    }
}
