import Foundation

public enum PromptRewriteTemplate {
    public static let messageVariable = "${message}"

    public static func render(_ template: String, message: String?) -> String {
        template.replacingOccurrences(of: messageVariable, with: message ?? "")
    }
}

public struct DeepSeekModelList: Decodable, Sendable {
    public struct Model: Decodable, Sendable {
        public let id: String
        public let object: String
        public let ownedBy: String

        enum CodingKeys: String, CodingKey {
            case id, object
            case ownedBy = "owned_by"
        }
    }

    public let object: String
    public let data: [Model]
}
