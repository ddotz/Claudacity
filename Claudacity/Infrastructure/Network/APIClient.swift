// MARK: - Imports
import Foundation
import OSLog

// MARK: - API Client Protocol
protocol APIClient: Sendable {
    func send<T: Decodable>(_ request: APIRequest) async throws -> T
}

// MARK: - API Request
struct APIRequest {
    let method: HTTPMethod
    let endpoint: String
    let headers: [String: String]
    let body: Data?
    let timeout: TimeInterval

    init(
        method: HTTPMethod = .get,
        endpoint: String,
        headers: [String: String] = [:],
        body: Encodable? = nil,
        timeout: TimeInterval = 30
    ) throws {
        self.method = method
        self.endpoint = endpoint
        self.headers = headers
        self.body = try body.map { try JSONEncoder().encode($0) }
        self.timeout = timeout
    }
}

// MARK: - HTTP Method
enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

// MARK: - URL Session API Client
final class URLSessionAPIClient: APIClient, @unchecked Sendable {
    // MARK: Properties
    private let session: URLSession
    private let baseURL: URL
    private let decoder: JSONDecoder

    // MARK: Init
    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: APIClient
    func send<T: Decodable>(_ request: APIRequest) async throws -> T {
        let urlRequest = try buildURLRequest(from: request)

        logDebug("[\(request.method.rawValue)] \(request.endpoint)", category: .network)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            logError("Invalid response type", category: .network)
            throw AppError.invalidResponse
        }

        logDebug("Response: \(httpResponse.statusCode), size: \(data.count) bytes", category: .network)

        try validateResponse(httpResponse, data: data)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            logError("JSON parsing failed for \(T.self)", category: .network, error: error)
            throw AppError.parsingFailed
        }
    }

    // MARK: Private Methods
    private func buildURLRequest(from request: APIRequest) throws -> URLRequest {
        guard let url = URL(string: request.endpoint, relativeTo: baseURL) else {
            throw AppError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.timeoutInterval = request.timeout
        urlRequest.httpBody = request.body

        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        return urlRequest
    }

    private func validateResponse(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw AppError.authRequired
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) } ?? 60
            throw AppError.rateLimited(retryAfter: retryAfter)
        case 500..<600:
            throw AppError.serverError(response.statusCode)
        default:
            throw AppError.invalidResponse
        }
    }
}
