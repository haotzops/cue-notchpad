import Foundation

public enum CueDocument: Codable, Sendable, Equatable {
    case standardInput
    case file(path: String)

    private enum CodingKeys: String, CodingKey { case kind, path }
    private enum Kind: String, Codable { case standardInput, file }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .standardInput: self = .standardInput
        case .file: self = .file(path: try container.decode(String.self, forKey: .path))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .standardInput: try container.encode(Kind.standardInput, forKey: .kind)
        case .file(let path):
            try container.encode(Kind.file, forKey: .kind)
            try container.encode(path, forKey: .path)
        }
    }
}

public struct CueSessionRequest: Codable, Sendable, Equatable {
    public let version: Int
    public let id: UUID
    public let initialText: String
    public let document: CueDocument
    public let callerPID: Int32
    public let callerName: String?
    public let workingDirectory: String

    public init(id: UUID = UUID(), initialText: String, document: CueDocument, callerPID: Int32, callerName: String?, workingDirectory: String) {
        self.version = 1
        self.id = id
        self.initialText = initialText
        self.document = document
        self.callerPID = callerPID
        self.callerName = callerName
        self.workingDirectory = workingDirectory
    }
}

public enum CueSessionResponse: Codable, Sendable, Equatable {
    case submitted(String)
    case cancelled
    case failed(String)

    private enum CodingKeys: String, CodingKey { case result, text, message }
    private enum Result: String, Codable { case submitted, cancelled, failed }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Result.self, forKey: .result) {
        case .submitted: self = .submitted(try c.decode(String.self, forKey: .text))
        case .cancelled: self = .cancelled
        case .failed: self = .failed(try c.decode(String.self, forKey: .message))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .submitted(let text): try c.encode(Result.submitted, forKey: .result); try c.encode(text, forKey: .text)
        case .cancelled: try c.encode(Result.cancelled, forKey: .result)
        case .failed(let message): try c.encode(Result.failed, forKey: .result); try c.encode(message, forKey: .message)
        }
    }
}

public enum CueIPC {
    public static let socketPath = (FileManager.default.homeDirectoryForCurrentUser.path as NSString)
        .appendingPathComponent("Library/Caches/dev.zen1th.cue-notepad/cue.sock")
    public static let maximumMessageBytes = 8 * 1024 * 1024

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        return data
    }
}
