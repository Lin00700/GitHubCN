import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL, networkError(Error), decodingError(Error), serverError(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "请求地址无效"
        case .networkError(let err): return "网络连接异常: \(err.localizedDescription)"
        case .decodingError(let err): return "数据解析失败: \(err.localizedDescription)"
        case .serverError(let code): return "服务器响应错误 (状态码: \(code))"
        }
    }
}

final class APIClient {
    static let shared = APIClient()
    private let baseURL = "https://api.github.com"
    
    private init() {}
    
    func fetchRepositories(query: String, sort: String = "stars", page: Int = 1) async throws -> [Repository] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "swift"
        guard let url = URL(string: "\(baseURL)/search/repositories?q=\(encodedQuery)&sort=\(sort)&order=desc&page=\(page)&per_page=30") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        
        let result = try JSONDecoder().decode(PaginatedResponse<Repository>.self, from: data)
        return result.items
    }
    
    func fetchIssues(for repoFullName: String) async throws -> [Issue] {
        guard let url = URL(string: "\(baseURL)/repos/\(repoFullName)/issues?state=all") else {
            throw APIError.invalidURL
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([Issue].self, from: data)
    }
}
