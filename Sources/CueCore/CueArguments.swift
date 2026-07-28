import Foundation

/// The deliberately small command-line surface of Cue Notepad.
public struct CueArguments: Equatable, Sendable {
    public let waitsForEditing: Bool

    public init(arguments: [String]) throws {
        guard arguments == ["--wait"] else {
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
