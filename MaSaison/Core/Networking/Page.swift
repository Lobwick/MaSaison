import Foundation

struct Page<T: Decodable>: Decodable {
    let data: [T]
    let lastPage: Int?

    enum CodingKeys: String, CodingKey {
        case data
        case lastPage = "last_page"
    }
}
