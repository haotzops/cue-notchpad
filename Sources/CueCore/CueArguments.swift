import Foundation

/// The deliberately small command-line surface of Cue Notchpad.
public struct CueArguments: Equatable, Sendable {
    public let waitsForEditing: Bool
    public let filePath: String?

    public init(arguments: [String]) throws {
        guard !arguments.isEmpty else { throw CueArgumentError.invalidArguments(arguments) }
        if arguments[0] == "--wait" {
            let rest = Array(arguments.dropFirst())
            if rest.first == "--" {
                guard rest.count == 2 else { throw CueArgumentError.invalidArguments(arguments) }
                self.filePath = rest[1]
            } else {
                guard rest.count <= 1 else { throw CueArgumentError.invalidArguments(arguments) }
                self.filePath = rest.first
            }
        } else if arguments.count == 1 && !arguments[0].hasPrefix("-") {
            // Standard $EDITOR form: cue <file>.
            self.filePath = arguments[0]
        } else {
            throw CueArgumentError.invalidArguments(arguments)
        }
        self.waitsForEditing = true
    }
}

public enum CueArgumentError: Error, Equatable, Sendable {
    case invalidArguments([String])
}

extension CueArgumentError: LocalizedError {
    public var errorDescription: String? {
        "usage: cue --wait"
    }
}
