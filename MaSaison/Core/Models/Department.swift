import Foundation

/// Departmental committee (structure of type DEP).
struct Department: Identifiable, Hashable {
    let id: Int
    let code: String   // "059"
    let name: String    // "UFOLEP 59"

    /// "59" (without leading zero) for compact display.
    var number: String { String(code.drop { $0 == "0" }) }
}

/// Node of `/structures/lazy-tree`; the title is an HTML fragment "<span>…badge code</span> name".
struct TreeNode: Decodable {
    let key: Int
    let title: String
    let children: [TreeNode]?

    var department: Department? {
        let text = title.replacing(#/<[^>]+>/#, with: "|")
            .split(separator: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard text.count >= 2, text[0].allSatisfy(\.isNumber) else { return nil }
        return Department(id: key, code: text[0], name: text[1])
    }
}
