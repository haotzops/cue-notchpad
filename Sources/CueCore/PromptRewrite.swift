import Foundation

public enum PromptRewriteTemplate {
    public static let messageVariable = "${message}"

    public static func render(_ template: String, message: String?) -> String {
        template.replacingOccurrences(of: messageVariable, with: message ?? "")
    }
}
