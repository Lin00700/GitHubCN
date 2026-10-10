import Foundation

struct Repository: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let fullName: String
    let description: String?
    let stargazersCount: Int
    let forksCount: Int
    let language: String?
    let htmlURL: String
    let owner: Owner?
    let updatedAt: String?
    
    struct Owner: Codable, Hashable {
        let login: String
        let avatarURL: String?
        
        enum CodingKeys: String, CodingKey {
            case login
            case avatarURL = "avatar_url"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, description, language, owner
        case fullName = "full_name"
        case stargazersCount = "stargazers_count"
        case forksCount = "forks_count"
        case htmlURL = "html_url"
        case updatedAt = "updated_at"
    }
}

struct Issue: Codable, Identifiable, Hashable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let state: String
    let createdAt: String
    let user: Repository.Owner?
    
    enum CodingKeys: String, CodingKey {
        case id, number, title, body, state, user
        case createdAt = "created_at"
    }
}

struct PaginatedResponse<T: Codable>: Codable {
    let totalCount: Int
    let items: [T]
    
    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case items
    }
}
