import Foundation

struct CommandError: Error, CustomStringConvertible {
    let message: String

    var description: String {
        message
    }
}

func fail(_ message: String) throws -> Never {
    throw CommandError(message: message)
}
