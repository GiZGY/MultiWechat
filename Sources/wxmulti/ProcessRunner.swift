import Foundation

struct ProcessResult {
    var status: Int32
    var stdout: String
    var stderr: String
}

private final class LockedDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Data()

    func set(_ data: Data) {
        lock.lock()
        value = data
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        let data = value
        lock.unlock()
        return data
    }
}

struct ProcessRunner {
    @discardableResult
    func run(_ executable: String, _ arguments: [String], allowFailure: Bool = false) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutBox = LockedDataBox()
        let stderrBox = LockedDataBox()
        let group = DispatchGroup()

        try process.run()

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutBox.set(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrBox.set(stderrPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }

        process.waitUntilExit()
        group.wait()

        let stdout = String(data: stdoutBox.data(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrBox.data(), encoding: .utf8) ?? ""
        let result = ProcessResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
        if !allowFailure && result.status != 0 {
            let detail = [stdout, stderr]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            try fail("命令执行失败: \(executable) \(arguments.joined(separator: " "))\n\(detail)")
        }
        return result
    }
}
